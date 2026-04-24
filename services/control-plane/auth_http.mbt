///|
let session_cookie_name = "moonbitcloud_session"

///|
let session_max_age_seconds : Int = 60 * 60 * 24 * 14

///|
let session_max_age_millis : UInt64 = 14UL * 24UL * 60UL * 60UL * 1000UL

///|
let oauth_state_max_age_millis : UInt64 = 10UL * 60UL * 1000UL

///|
let password_reset_max_age_millis : UInt64 = 60UL * 60UL * 1000UL

///|
let email_verification_max_age_millis : UInt64 = 24UL * 60UL * 60UL * 1000UL

///|
fn password_reset_purpose() -> String {
  "password_reset"
}

///|
fn email_verification_purpose() -> String {
  "email_verification"
}

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
    _ =>
      match @env.get_env_var("MOONBITCLOUD_PORT") {
        Some(port) if port != "" => "http://localhost:\{port}"
        _ => "http://localhost:8080"
      }
  }
}

///|
fn account_email_outbox_path(root : String) -> String {
  root + "/data/control-plane/account-emails.log"
}

///|
fn append_account_email(
  ctx : AppContext,
  to : String,
  subject : String,
  body : String,
) -> Unit {
  ensure_dir(ctx.root + "/data")
  ensure_dir(ctx.root + "/data/control-plane")
  let entry = "---\nqueued_at: " +
    now_string() +
    "\nto: " +
    to +
    "\nsubject: " +
    subject +
    "\n\n" +
    body +
    "\n\n"
  safe_append_string(account_email_outbox_path(ctx.root), entry)
  println("account email queued for \{to}: \{subject}")
}

///|
fn account_action_url(path : String, token : String) -> String {
  github_public_base_url() + path + "?token=" + token
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
fn validate_password(password : String) -> Result[Unit, String] {
  if password.length() < 8 {
    Err("Passwords must be at least 8 characters long.")
  } else {
    Ok(())
  }
}

///|
fn queue_email_verification(ctx : AppContext, user : @sdk.UserSummary) -> Unit {
  let token = new_account_action_token()
  ctx.store.save_account_action_token(
    user.id,
    email_verification_purpose(),
    account_action_token_hash(token),
    future_unix_millis_string(email_verification_max_age_millis),
  )
  let url = account_action_url("/auth/email/verify", token)
  append_account_email(
    ctx,
    user.email,
    "Verify your MoonBit Cloud email",
    "Open this link to verify your email address:\n\{url}",
  )
}

///|
fn queue_password_reset(ctx : AppContext, user : @sdk.UserSummary) -> Unit {
  let token = new_account_action_token()
  ctx.store.save_account_action_token(
    user.id,
    password_reset_purpose(),
    account_action_token_hash(token),
    future_unix_millis_string(password_reset_max_age_millis),
  )
  let url = account_action_url("/auth/password/reset", token)
  append_account_email(
    ctx,
    user.email,
    "Reset your MoonBit Cloud password",
    "Open this link to set a new password:\n\{url}",
  )
}

///|
fn request_password_reset(
  ctx : AppContext,
  request : @sdk.RequestPasswordResetRequest,
) -> @sdk.AuthActionResponse {
  let email = normalized_email(request.email)
  match ctx.store.get_user_by_email(email) {
    Some(user) => queue_password_reset(ctx, user)
    None => ignore(())
  }
  @sdk.AuthActionResponse::{
    message: "If that email is registered, a reset link has been queued.",
  }
}

///|
fn reset_password(
  ctx : AppContext,
  request : @sdk.ResetPasswordRequest,
) -> Result[@sdk.AuthActionResponse, String] {
  let token = request.token.trim().to_string()
  if token == "" {
    return Err("The reset link is missing its token.")
  }
  match validate_password(request.password) {
    Err(message) => return Err(message)
    Ok(_) => ignore(())
  }
  let user_id = match
    ctx.store.consume_account_action_token(
      password_reset_purpose(),
      account_action_token_hash(token),
    ) {
    Some(user_id) => user_id
    None => return Err("This reset link is invalid or has expired.")
  }
  ctx.store.update_user_password_hash(user_id, hash_password(request.password))
  ctx.store.set_user_email_verified(user_id)
  ctx.store.delete_sessions_for_user(user_id)
  Ok(@sdk.AuthActionResponse::{
    message: "Password updated. Sign in with the new password.",
  })
}

///|
fn change_password(
  ctx : AppContext,
  user : @sdk.UserSummary,
  request : @sdk.ChangePasswordRequest,
) -> Result[@sdk.AuthActionResponse, String] {
  match validate_password(request.new_password) {
    Err(message) => return Err(message)
    Ok(_) => ignore(())
  }
  match ctx.store.get_user_with_password_hash(user.email) {
    Some((_, Some(password_hash))) =>
      if verify_password(request.current_password, password_hash) {
        ctx.store.update_user_password_hash(
          user.id,
          hash_password(request.new_password),
        )
        Ok(@sdk.AuthActionResponse::{ message: "Password changed." })
      } else {
        Err("The current password is incorrect.")
      }
    _ =>
      Err(
        "This account does not have a password. Use password reset to set one.",
      )
  }
}

///|
fn resend_email_verification(
  ctx : AppContext,
  user : @sdk.UserSummary,
) -> @sdk.AuthActionResponse {
  if user.email_verified {
    @sdk.AuthActionResponse::{ message: "Email is already verified." }
  } else {
    queue_email_verification(ctx, user)
    @sdk.AuthActionResponse::{ message: "Verification link has been queued." }
  }
}

///|
fn verify_email(
  ctx : AppContext,
  request : @sdk.VerifyEmailRequest,
) -> Result[@sdk.AuthActionResponse, String] {
  let token = request.token.trim().to_string()
  if token == "" {
    return Err("The verification link is missing its token.")
  }
  let user_id = match
    ctx.store.consume_account_action_token(
      email_verification_purpose(),
      account_action_token_hash(token),
    ) {
    Some(user_id) => user_id
    None => return Err("This verification link is invalid or has expired.")
  }
  ctx.store.set_user_email_verified(user_id)
  Ok(@sdk.AuthActionResponse::{ message: "Email address verified." })
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
  match validate_password(request.password) {
    Err(message) => return Err(message)
    Ok(_) => ignore(())
  }
  let display_name = match request.display_name {
    Some(value) if value.trim() != "" => value.trim().to_string()
    _ => default_display_name_from_email(email)
  }
  let user = match
    ctx.store.create_user(
      email,
      Some(hash_password(request.password)),
      display_name,
      None,
      false,
    ) {
    Ok(user) => user
    Err(message) => return Err(message)
  }
  queue_email_verification(ctx, user)
  Ok(user)
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
      self.store.set_user_email_verified(user.id)
      return Ok(self.store.get_user_by_id(user.id).unwrap_or(user))
    }
    None => ignore(())
  }
  let user = match self.store.get_user_by_email(email) {
    Some(existing) => {
      self.store.set_user_email_verified(existing.id)
      self.store.get_user_by_id(existing.id).unwrap_or(existing)
    }
    None =>
      match
        self.store.create_user(
          email,
          None,
          github_display_name(profile),
          Some(profile.login),
          true,
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
    #|    <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%2305080c'/%3E%3Cpath d='M14 18h14v28H14zm22 0h14v28H36z' fill='%2338efb7'/%3E%3C/svg%3E" />
    #|    <style>
    #|      body {
    #|        margin: 0;
    #|        min-height: 100vh;
    #|        display: grid;
    #|        place-items: center;
    #|        background:
    #|          radial-gradient(circle at top left, rgba(24, 255, 176, 0.12), transparent 28%),
    #|          radial-gradient(circle at top right, rgba(45, 125, 255, 0.14), transparent 24%),
    #|          linear-gradient(180deg, #091119, #05080c);
    #|        color: #eff7ff;
    #|        font-family: "IBM Plex Sans", "Helvetica Neue", sans-serif;
    #|      }
    #|      .card {
    #|        width: min(420px, calc(100vw - 32px));
    #|        padding: 28px;
    #|        border-radius: 16px;
    #|        background: rgba(8, 13, 19, 0.92);
    #|        border: 1px solid rgba(120, 140, 166, 0.16);
    #|        box-shadow: 0 24px 90px rgba(0, 0, 0, 0.36);
    #|      }
    #|      h1 {
    #|        margin: 0 0 10px;
    #|        font-size: 28px;
    #|      }
    #|      p {
    #|        margin: 0;
    #|        font-size: 15px;
    #|        line-height: 1.7;
    #|        color: #a7bad0;
    #|      }
    #|      #status {
    #|        margin-top: 16px;
    #|        color: #ffcf66;
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

///|
fn account_action_page_style() -> String {
  (
    #|body {
    #|  margin: 0;
    #|  min-height: 100vh;
    #|  display: grid;
    #|  place-items: center;
    #|  background: #101113;
    #|  color: #f4f4f5;
    #|  font-family: "IBM Plex Sans", "Helvetica Neue", sans-serif;
    #|}
    #|.card {
    #|  width: min(420px, calc(100vw - 32px));
    #|  padding: 24px;
    #|  border-radius: 8px;
    #|  background: #17181b;
    #|  border: 1px solid rgba(255, 255, 255, 0.10);
    #|  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.22);
    #|}
    #|h1 {
    #|  margin: 0 0 10px;
    #|  font-size: 28px;
    #|}
    #|p {
    #|  margin: 0;
    #|  color: #c7c7cb;
    #|  line-height: 1.6;
    #|}
    #|input, button {
    #|  width: 100%;
    #|  box-sizing: border-box;
    #|  border-radius: 6px;
    #|  font: inherit;
    #|}
    #|input {
    #|  margin-top: 18px;
    #|  padding: 12px 14px;
    #|  color: #f4f4f5;
    #|  background: #222328;
    #|  border: 1px solid rgba(47, 132, 255, 0.72);
    #|}
    #|button, a.button {
    #|  display: flex;
    #|  justify-content: center;
    #|  margin-top: 14px;
    #|  padding: 12px 14px;
    #|  color: #fff;
    #|  background: #2f84ff;
    #|  border: 1px solid rgba(255, 255, 255, 0.09);
    #|  text-decoration: none;
    #|  font-weight: 700;
    #|  cursor: pointer;
    #|}
    #|#status {
    #|  margin-top: 14px;
    #|  color: #ffcf66;
    #|}
  )
}

///|
fn email_verification_page_html() -> String {
  let style = account_action_page_style()
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8" />
    #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
    #|    <title>Verify Email - MoonBit Cloud</title>
    #|    <style>
  ) +
  style +
  (
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <div class="card">
    #|      <h1>Verify email</h1>
    #|      <p>MoonBit Cloud is checking your verification link.</p>
    #|      <p id="status"></p>
    #|      <a class="button" href="/">Back to app</a>
    #|    </div>
    #|    <script>
    #|      async function errorMessage(response) {
    #|        const text = await response.text();
    #|        try {
    #|          const payload = JSON.parse(text);
    #|          return payload.error?.message || text || "Verification failed.";
    #|        } catch (_) {
    #|          return text || "Verification failed.";
    #|        }
    #|      }
    #|      const token = new URLSearchParams(window.location.search).get("token");
    #|      const status = document.getElementById("status");
    #|      if (!token) {
    #|        status.textContent = "This verification link is missing its token.";
    #|      } else {
    #|        fetch("/api/auth/email/verification/confirm", {
    #|          method: "POST",
    #|          headers: { "Content-Type": "application/json" },
    #|          credentials: "same-origin",
    #|          body: JSON.stringify({ token })
    #|        }).then(async (response) => {
    #|          if (!response.ok) throw new Error(await errorMessage(response));
    #|          const payload = await response.json();
    #|          status.textContent = payload.message || "Email address verified.";
    #|        }).catch((err) => {
    #|          status.textContent = err.message || "Verification failed.";
    #|        });
    #|      }
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
fn password_reset_page_html() -> String {
  let style = account_action_page_style()
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8" />
    #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
    #|    <title>Reset Password - MoonBit Cloud</title>
    #|    <style>
  ) +
  style +
  (
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <form class="card" id="reset-form">
    #|      <h1>Reset password</h1>
    #|      <p>Set a new password for your MoonBit Cloud account.</p>
    #|      <input id="password" type="password" placeholder="New password" autocomplete="new-password" />
    #|      <button type="submit">Update Password</button>
    #|      <p id="status"></p>
    #|      <a class="button" href="/">Back to sign in</a>
    #|    </form>
    #|    <script>
    #|      async function errorMessage(response) {
    #|        const text = await response.text();
    #|        try {
    #|          const payload = JSON.parse(text);
    #|          return payload.error?.message || text || "Password reset failed.";
    #|        } catch (_) {
    #|          return text || "Password reset failed.";
    #|        }
    #|      }
    #|      const token = new URLSearchParams(window.location.search).get("token");
    #|      const form = document.getElementById("reset-form");
    #|      const password = document.getElementById("password");
    #|      const status = document.getElementById("status");
    #|      if (!token) {
    #|        status.textContent = "This reset link is missing its token.";
    #|      }
    #|      form.addEventListener("submit", async (event) => {
    #|        event.preventDefault();
    #|        if (!token) return;
    #|        status.textContent = "Updating password...";
    #|        try {
    #|          const response = await fetch("/api/auth/password-reset/confirm", {
    #|            method: "POST",
    #|            headers: { "Content-Type": "application/json" },
    #|            credentials: "same-origin",
    #|            body: JSON.stringify({ token, password: password.value })
    #|          });
    #|          if (!response.ok) throw new Error(await errorMessage(response));
    #|          const payload = await response.json();
    #|          status.textContent = payload.message || "Password updated.";
    #|          password.value = "";
    #|        } catch (err) {
    #|          status.textContent = err.message || "Password reset failed.";
    #|        }
    #|      });
    #|    </script>
    #|  </body>
    #|</html>
  )
}
