///|
let session_cookie_name = "moonbitcloud_session"

///|
let session_max_age_seconds : Int = 60 * 60 * 24 * 14

///|
let session_max_age_millis : UInt64 = 14UL * 24UL * 60UL * 60UL * 1000UL

///|
let oauth_state_max_age_millis : UInt64 = 10UL * 60UL * 1000UL

///|
struct GitHubCallbackPayload {
  code : String
  state : String
} derive(Debug, FromJson)

///|
struct GitHubUserProfile {
  id : Int
  login : String
  email : String?
  name : String?
} derive(Debug, FromJson)

///|
struct GitHubUserEmail {
  email : String
  primary : Bool
  verified : Bool
} derive(Debug, FromJson)

///|
fn unix_millis_string() -> String {
  @env.now().to_string()
}

///|
fn future_unix_millis_string(offset : UInt64) -> String {
  (@env.now() + offset).to_string()
}

///|
fn github_provider_name() -> String {
  "github"
}

///|
fn github_public_base_url() -> String {
  match @env.get_env_var("MOONBITCLOUD_PUBLIC_BASE_URL") {
    Some(value) if value != "" && value.has_suffix("/") =>
      value[:value.length() - 1].to_string()
    Some(value) if value != "" => value
    _ => "http://localhost:8080"
  }
}

///|
fn github_callback_url() -> String {
  github_public_base_url() + "/auth/github/callback"
}

///|
fn github_credentials() -> (String, String)? {
  match
    (
      @env.get_env_var("MOONBITCLOUD_GITHUB_CLIENT_ID"),
      @env.get_env_var("MOONBITCLOUD_GITHUB_CLIENT_SECRET"),
    ) {
    (Some(client_id), Some(client_secret)) =>
      if client_id != "" && client_secret != "" {
        Some((client_id, client_secret))
      } else {
        None
      }
    _ => None
  }
}

///|
fn github_oauth_enabled() -> Bool {
  github_credentials() is Some(_)
}

///|
fn normalized_email(email : String) -> String {
  email.trim().to_string().to_lower()
}

///|
fn default_display_name_from_email(email : String) -> String {
  let parts = email.split("@").to_array()
  match parts[0].to_string() {
    "" => "MoonBit Builder"
    local_part =>
      local_part
      .replace_all(old=".", new=" ")
      .replace_all(old="_", new=" ")
      .replace_all(old="-", new=" ")
  }
}

///|
fn session_user_from_event(
  ctx : AppContext,
  event : @mocket.MocketEvent,
) -> @sdk.UserSummary? {
  match event.req.get_cookie(session_cookie_name) {
    Some(cookie) if cookie.value != "" =>
      ctx.store.get_user_by_session_token_hash(session_token_hash(cookie.value))
    _ => None
  }
}

///|
fn require_session_user(
  ctx : AppContext,
  event : @mocket.MocketEvent,
) -> Result[@sdk.UserSummary, @mocket.HttpResponse] {
  match session_user_from_event(ctx, event) {
    Some(user) => Ok(user)
    None => Err(unauthorized_response())
  }
}

///|
fn set_session_cookie(response : @mocket.HttpResponse, token : String) -> Unit {
  response.set_cookie(
    session_cookie_name,
    token,
    max_age=session_max_age_seconds,
    path="/",
    http_only=true,
    same_site=@mocket.Lax,
  )
}

///|
fn clear_session_cookie(response : @mocket.HttpResponse) -> Unit {
  response.set_cookie(
    session_cookie_name,
    "",
    max_age=0,
    path="/",
    http_only=true,
    same_site=@mocket.Lax,
  )
}

///|
fn authenticated_response(
  ctx : AppContext,
  event : @mocket.MocketEvent,
  user : @sdk.UserSummary,
  status? : @mocket.StatusCode = OK,
) -> @mocket.HttpResponse {
  let token = new_session_token()
  ctx.store.create_session(
    user.id,
    session_token_hash(token),
    future_unix_millis_string(session_max_age_millis),
  )
  set_session_cookie(event.res, token)
  json_response(status, @sdk.AuthResponse::{ user, })
}

///|
fn signup_user(
  ctx : AppContext,
  request : @sdk.SignupRequest,
) -> Result[@sdk.UserSummary, String] {
  let email = normalized_email(request.email)
  if email == "" || !email.contains("@") {
    return Err("Enter a valid email address.")
  }
  if request.password.length() < 8 {
    return Err("Passwords must be at least 8 characters long.")
  }
  let display_name = match request.display_name {
    Some(value) if value.trim() != "" => value.trim().to_string()
    _ => default_display_name_from_email(email)
  }
  ctx.store.create_user(
    email,
    Some(hash_password(request.password)),
    display_name,
    None,
  )
}

///|
fn login_user(
  ctx : AppContext,
  request : @sdk.LoginRequest,
) -> Result[@sdk.UserSummary, String] {
  let email = normalized_email(request.email)
  match ctx.store.get_user_with_password_hash(email) {
    Some((user, Some(password_hash))) =>
      if verify_password(request.password, password_hash) {
        Ok(user)
      } else {
        Err("The email or password is incorrect.")
      }
    _ => Err("The email or password is incorrect.")
  }
}

///|
fn github_authorization_response(ctx : AppContext) -> @mocket.HttpResponse {
  match github_credentials() {
    Some((client_id, _)) => {
      let state = new_oauth_state()
      let verifier = new_pkce_verifier()
      let challenge = @oauth2.PkceCodeChallenge::from_verifier_s256(
        @oauth2.PkceCodeVerifier::new(verifier),
      )
      let request = @oauth2.AuthorizationRequest::new_with_pkce(
        @oauth2.AuthUrl::new("https://github.com/login/oauth/authorize"),
        @oauth2.ClientId::new(client_id),
        @oauth2.RedirectUrl::new(github_callback_url()),
        [@oauth2.Scope::new("read:user"), @oauth2.Scope::new("user:email")],
        @oauth2.CsrfToken::new(state),
        challenge,
      )
      ctx.store.save_oauth_state(
        github_provider_name(),
        state,
        verifier,
        future_unix_millis_string(oauth_state_max_age_millis),
      )
      redirect_response(request.build_authorization_url())
    }
    None =>
      text_response(
        ServiceUnavailable,
        "GitHub sign-in is not configured on this server.",
      )
  }
}

///|
fn github_api_headers(access_token : String) -> Map[String, String] {
  {
    "Accept": "application/vnd.github+json",
    "Authorization": "Bearer \{access_token}",
    "User-Agent": "moonbitcloud",
    "X-GitHub-Api-Version": "2022-11-28",
  }
}

///|
fn[T : FromJson] decode_json_text(text : String) -> Result[T, String] {
  let parsed = @json.parse(text) catch {
    _ => return Err("The upstream response was not valid JSON.")
  }
  Ok(
    @json.from_json(parsed) catch {
      _ => return Err("The upstream response did not match the expected shape.")
    },
  )
}

///|
async fn github_fetch_profile(
  access_token : String,
) -> Result[GitHubUserProfile, String] noraise {
  let headers = github_api_headers(access_token)
  let response = try
    @mocket.fetch("https://api.github.com/user", GET, headers~)
  catch {
    _ => return Err("GitHub user details could not be loaded.")
  } noraise {
    value => value
  }
  if response.status_code != OK {
    return Err("GitHub user details could not be loaded.")
  }
  decode_json_text(bytes_to_string(response.raw_body))
}

///|
async fn github_fetch_email(
  access_token : String,
) -> Result[String, String] noraise {
  let headers = github_api_headers(access_token)
  let response = try
    @mocket.fetch("https://api.github.com/user/emails", GET, headers~)
  catch {
    _ => return Err("GitHub email addresses could not be loaded.")
  } noraise {
    value => value
  }
  if response.status_code != OK {
    return Err("GitHub email addresses could not be loaded.")
  }
  let emails : Array[GitHubUserEmail] = match
    decode_json_text(bytes_to_string(response.raw_body)) {
    Ok(items) => items
    Err(message) => return Err(message)
  }
  for item in emails {
    if item.primary && item.verified && item.email != "" {
      return Ok(normalized_email(item.email))
    }
  }
  for item in emails {
    if item.verified && item.email != "" {
      return Ok(normalized_email(item.email))
    }
  }
  Err("A verified GitHub email address is required to sign in.")
}

///|
fn github_display_name(profile : GitHubUserProfile) -> String {
  match profile.name {
    Some(name) if name.trim() != "" => name.trim().to_string()
    _ => profile.login
  }
}

///|
async fn AppContext::complete_github_sign_in(
  self : AppContext,
  payload : GitHubCallbackPayload,
) -> Result[@sdk.UserSummary, String] noraise {
  let (client_id, client_secret) = match github_credentials() {
    Some(creds) => creds
    None => return Err("GitHub sign-in is not configured on this server.")
  }
  let pkce_verifier = match
    self.store.consume_oauth_state(github_provider_name(), payload.state) {
    Some(value) => value
    None => return Err("This GitHub sign-in link is invalid or has expired.")
  }
  let token_request = @oauth2.TokenRequest::new_with_pkce(
    @oauth2.TokenUrl::new("https://github.com/login/oauth/access_token"),
    @oauth2.ClientId::new(client_id),
    @oauth2.ClientSecret::new(client_secret),
    payload.code,
    @oauth2.RedirectUrl::new(github_callback_url()),
    @oauth2.PkceCodeVerifier::new(pkce_verifier),
  )
  let headers : Map[String, String] = {
    "Accept": "application/json",
    "Content-Type": "application/x-www-form-urlencoded",
  }
  let token_response = try
    @mocket.fetch(
      "https://github.com/login/oauth/access_token",
      POST,
      body=token_request.build_request_body(),
      headers~,
    )
  catch {
    _ =>
      return Err(
        "GitHub sign-in failed while exchanging the authorization code.",
      )
  } noraise {
    response => response
  }
  if token_response.status_code != OK {
    return Err("GitHub sign-in failed while exchanging the authorization code.")
  }
  let token = match
    @oauth2.parse_token_response(bytes_to_string(token_response.raw_body)) {
    Ok(token) => token
    Err(error) =>
      return Err(
        "GitHub sign-in failed while parsing the access token response: \{error.message()}",
      )
  }
  let access_token = token.access_token().to_string()
  let profile = match github_fetch_profile(access_token) {
    Ok(profile) => profile
    Err(message) => return Err(message)
  }
  let email = match github_fetch_email(access_token) {
    Ok(email) => email
    Err(message) => return Err(message)
  }
  let provider_user_id = profile.id.to_string()
  match
    self.store.find_user_by_oauth_account(
      github_provider_name(),
      provider_user_id,
    ) {
    Some(user) => {
      self.store.update_user_github_login(user.id, profile.login)
      return Ok(self.store.get_user_by_id(user.id).unwrap_or(user))
    }
    None => ignore(())
  }
  let user = match self.store.get_user_by_email(email) {
    Some(existing) => existing
    None =>
      match
        self.store.create_user(
          email,
          None,
          github_display_name(profile),
          Some(profile.login),
        ) {
        Ok(created) => created
        Err(message) => return Err(message)
      }
  }
  self.store.link_oauth_account(
    user.id,
    github_provider_name(),
    provider_user_id,
  )
  self.store.update_user_github_login(user.id, profile.login)
  Ok(self.store.get_user_by_id(user.id).unwrap_or(user))
}

///|
fn session_status_response(
  ctx : AppContext,
  event : @mocket.MocketEvent,
) -> @sdk.SessionResponse {
  let user = session_user_from_event(ctx, event)
  @sdk.SessionResponse::{
    authenticated: user is Some(_),
    user,
    github_enabled: github_oauth_enabled(),
  }
}

///|
fn github_callback_page_html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8" />
    #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
    #|    <title>MoonBit Cloud GitHub Sign-In</title>
    #|    <style>
    #|      body {
    #|        margin: 0;
    #|        min-height: 100vh;
    #|        display: grid;
    #|        place-items: center;
    #|        background: linear-gradient(180deg, #f6f9fd, #edf4ff);
    #|        color: #17304a;
    #|        font-family: "Inter", "Helvetica Neue", sans-serif;
    #|      }
    #|      .card {
    #|        width: min(420px, calc(100vw - 32px));
    #|        padding: 28px;
    #|        border-radius: 28px;
    #|        background: rgba(255, 255, 255, 0.96);
    #|        box-shadow: 0 30px 80px rgba(19, 48, 74, 0.14);
    #|      }
    #|      h1 {
    #|        margin: 0 0 10px;
    #|        font-size: 28px;
    #|      }
    #|      p {
    #|        margin: 0;
    #|        font-size: 15px;
    #|        line-height: 1.7;
    #|        color: #55708a;
    #|      }
    #|      #status {
    #|        margin-top: 16px;
    #|        color: #b34722;
    #|      }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <div class="card">
    #|      <h1>Finishing GitHub sign-in</h1>
    #|      <p>MoonBit Cloud is verifying your GitHub account and preparing your workspace.</p>
    #|      <p id="status"></p>
    #|    </div>
    #|    <script>
    #|      const params = new URLSearchParams(window.location.search);
    #|      const code = params.get("code");
    #|      const state = params.get("state");
    #|      const error = params.get("error");
    #|      const status = document.getElementById("status");
    #|      if (error) {
    #|        status.textContent = "GitHub returned an error: " + error;
    #|      } else if (!code || !state) {
    #|        status.textContent = "The GitHub callback is missing the required parameters.";
    #|      } else {
    #|        fetch("/api/auth/github/callback", {
    #|          method: "POST",
    #|          headers: { "Content-Type": "application/json" },
    #|          credentials: "same-origin",
    #|          body: JSON.stringify({ code, state })
    #|        }).then(async (response) => {
    #|          if (!response.ok) {
    #|            throw new Error((await response.text()) || "GitHub sign-in failed.");
    #|          }
    #|          window.location.replace("/");
    #|        }).catch((err) => {
    #|          status.textContent = err.message || "GitHub sign-in failed.";
    #|        });
    #|      }
    #|    </script>
    #|  </body>
    #|</html>
  )
}
