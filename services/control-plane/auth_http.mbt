///|
let session_cookie_name = "mooncraft_session"

///|
let session_max_age_seconds : Int = 60 * 60 * 24 * 14

///|
let session_max_age_millis : UInt64 = 14UL * 24UL * 60UL * 60UL * 1000UL

///|
let oauth_state_max_age_millis : UInt64 = 10UL * 60UL * 1000UL

///|
fn mooncraft_app_mode() -> String {
  match @env.get_env_var("MOONCRAFT_APP_MODE") {
    Some(value) =>
      match value.trim().to_lower() {
        "dev" | "development" => "development"
        "test" => "test"
        "prod" | "production" => "production"
        _ => "production"
      }
    None => "production"
  }
}

///|
fn mooncraft_development_mode() -> Bool {
  mooncraft_app_mode() == "development"
}

///|
struct GitHubCallbackPayload {
  code : String
  state : String
} derive(Debug, @json.FromJson)

///|
struct DevAuthRequest {
  email : String
  display_name : String?
  github_login : String?
} derive(Debug, @json.FromJson)

///|
struct GitHubUserProfile {
  id : String
  login : String
  email : String?
  name : String?
} derive(Debug)

///|
struct GitHubUserEmail {
  email : String
  primary : Bool
  verified : Bool
} derive(Debug, @json.FromJson)

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
  match @env.get_env_var("MOONCRAFT_PUBLIC_BASE_URL") {
    Some(value) if value != "" && value.has_suffix("/") =>
      value[:value.length() - 1].to_owned()
    Some(value) if value != "" => value
    _ =>
      match @env.get_env_var("MOONCRAFT_PORT") {
        Some(port) if port != "" => "http://localhost:\{port}"
        _ => "http://localhost:8080"
      }
  }
}

///|
fn github_callback_url() -> String {
  "\{github_public_base_url()}/auth/github/callback"
}

///|
fn github_client_id_hint(client_id : String) -> String {
  if client_id.length() <= 8 {
    client_id
  } else {
    "\{client_id[:8].to_owned()}..."
  }
}

///|
fn log_github_token_exchange_failure(
  stage : String,
  client_id : String,
  status : @mocket.StatusCode?,
  response_body : String?,
) -> Unit {
  let status_text = match status {
    Some(code) => code.to_int().to_string()
    None => "no-response"
  }
  let body_text = match response_body {
    Some(body) if body.contains("\"access_token\"") =>
      "<redacted GitHub token response>"
    Some(body) if body != "" => body
    _ => "<empty>"
  }
  println(
    "warning: GitHub OAuth token exchange failed\n  stage: \{stage}\n  status: \{status_text}\n  callback_url: \{github_callback_url()}\n  client_id: \{github_client_id_hint(client_id)}\n  client_secret: <redacted>\n  response_body: \{body_text}",
  )
}

///|
fn log_github_callback_failure(reason : String) -> Unit {
  println(
    "warning: GitHub OAuth callback failed\n  reason: \{reason}\n  callback_url: \{github_callback_url()}",
  )
}

///|
fn github_credentials() -> (String, String)? {
  match
    (
      @env.get_env_var("MOONCRAFT_GITHUB_CLIENT_ID"),
      @env.get_env_var("MOONCRAFT_GITHUB_CLIENT_SECRET"),
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
fn dev_auth_enabled() -> Bool {
  match @env.get_env_var("MOONCRAFT_ENABLE_DEV_AUTH") {
    Some(value) => value == "1" || value.to_lower() == "true"
    None => false
  }
}

///|
fn normalized_email(email : String) -> String {
  email.trim().to_owned().to_lower()
}

///|
fn display_name_from_email(email : String) -> String {
  let parts = email.split("@").to_array()
  match parts[0].to_owned() {
    "" => "MoonCraft Builder"
    local_part =>
      local_part
      .replace_all(old=".", new=" ")
      .replace_all(old="_", new=" ")
      .replace_all(old="-", new=" ")
  }
}

///|
async fn session_user_from_event(
  ctx : AppContext,
  event : @mocket.MocketEvent,
) -> @sdk.UserSummary? noraise {
  match event.req.get_cookie(session_cookie_name) {
    Some(cookie) if cookie.value != "" =>
      ctx.store.get_user_by_session_token_hash(session_token_hash(cookie.value))
    _ => None
  }
}

///|
async fn require_session_user(
  ctx : AppContext,
  event : @mocket.MocketEvent,
) -> Result[@sdk.UserSummary, @mocket.HttpResponse] noraise {
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
    same_site=Lax,
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
    same_site=Lax,
  )
}

///|
async fn authenticated_response(
  ctx : AppContext,
  event : @mocket.MocketEvent,
  user : @sdk.UserSummary,
  status? : @mocket.StatusCode = OK,
) -> @mocket.HttpResponse noraise {
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
async fn github_authorization_response(
  ctx : AppContext,
) -> @mocket.HttpResponse noraise {
  match github_credentials() {
    Some((client_id, _)) => {
      let state = new_oauth_state()
      let verifier = new_pkce_verifier()
      ctx.store.save_oauth_state(
        github_provider_name(),
        state,
        verifier,
        future_unix_millis_string(oauth_state_max_age_millis),
      )
      redirect_response(
        github_authorization_url(
          client_id,
          github_callback_url(),
          state,
          verifier,
        ),
      )
    }
    None =>
      text_response(ServiceUnavailable, "Sign-in is temporarily unavailable.")
  }
}

///|
async fn dev_authenticated_response(
  ctx : AppContext,
  event : @mocket.MocketEvent,
  request : DevAuthRequest,
) -> Result[@mocket.HttpResponse, String] noraise {
  if !dev_auth_enabled() {
    return Err("Development auth is not enabled.")
  }
  let email = normalized_email(request.email)
  if email == "" || !email.contains("@") {
    return Err("Enter a valid email address.")
  }
  let login = match request.github_login {
    Some(value) if value.trim() != "" => value.trim().to_owned()
    _ =>
      email.split("@").to_array()[0]
      .to_owned()
      .replace_all(old=".", new="-")
      .replace_all(old="_", new="-")
  }
  let user = match ctx.store.get_user_by_email(email) {
    Some(existing) => {
      ctx.store.set_user_email_verified(existing.id)
      ctx.store.update_user_github_login(existing.id, login)
      ctx.store.get_user_by_id(existing.id).unwrap_or(existing)
    }
    None => {
      let display_name = match request.display_name {
        Some(value) if value.trim() != "" => value.trim().to_owned()
        _ => display_name_from_email(email)
      }
      match
        ctx.store.create_user(email, None, display_name, Some(login), true) {
        Ok(user) => user
        Err(message) => return Err(message)
      }
    }
  }
  Ok(authenticated_response(ctx, event, user))
}

///|
fn github_api_headers(access_token : String) -> Map[String, String] {
  {
    "Accept": "application/vnd.github+json",
    "Authorization": "Bearer \{access_token}",
    "User-Agent": "mooncraft",
    "X-GitHub-Api-Version": "2022-11-28",
  }
}

///|
fn[T : @json.FromJson] decode_json_text(text : String) -> Result[T, String] {
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
fn github_required_string_field(
  fields : Map[String, Json],
  name : String,
) -> Result[String, String] {
  match fields.get(name) {
    Some(String(value)) if value != "" => Ok(value)
    _ => Err("The upstream response did not match the expected shape.")
  }
}

///|
fn github_optional_string_field(
  fields : Map[String, Json],
  name : String,
) -> Result[String?, String] {
  match fields.get(name) {
    Some(String(value)) => Ok(Some(value))
    Some(Null) | None => Ok(None)
    _ => Err("The upstream response did not match the expected shape.")
  }
}

///|
fn github_id_field(fields : Map[String, Json]) -> Result[String, String] {
  match fields.get("id") {
    Some(value) =>
      match value {
        Number(_, ..) => Ok(value.stringify())
        String(text) if text != "" => Ok(text)
        _ => Err("The upstream response did not match the expected shape.")
      }
    _ => Err("The upstream response did not match the expected shape.")
  }
}

///|
fn github_user_profile_from_response(
  body : String,
) -> Result[GitHubUserProfile, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("The upstream response was not valid JSON.")
  }
  match parsed {
    Object(fields) => {
      let id = match github_id_field(fields) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let login = match github_required_string_field(fields, "login") {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let email = match github_optional_string_field(fields, "email") {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let name = match github_optional_string_field(fields, "name") {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      Ok({ id, login, email, name })
    }
    _ => Err("The upstream response did not match the expected shape.")
  }
}

///|
async fn github_fetch_profile(
  access_token : String,
) -> Result[GitHubUserProfile, String] noraise {
  let headers = github_api_headers(access_token)
  let response = match http_get("https://api.github.com/user", headers~) {
    Ok(value) => value
    Err(_) => return Err("GitHub user details could not be loaded.")
  }
  if !http_status_success(response.code) {
    return Err("GitHub user details could not be loaded.")
  }
  github_user_profile_from_response(http_response_text(response))
}

///|
async fn github_fetch_email(
  access_token : String,
) -> Result[String, String] noraise {
  let headers = github_api_headers(access_token)
  let response = match
    http_get("https://api.github.com/user/emails", headers~) {
    Ok(value) => value
    Err(_) => return Err("GitHub email addresses could not be loaded.")
  }
  if !http_status_success(response.code) {
    return Err("GitHub email addresses could not be loaded.")
  }
  let emails : Array[GitHubUserEmail] = match
    decode_json_text(http_response_text(response)) {
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
    Some(name) if name.trim() != "" => name.trim().to_owned()
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
    None => {
      log_github_callback_failure("missing server credentials")
      return Err("Sign-in is temporarily unavailable.")
    }
  }
  let pkce_verifier = match
    self.store.consume_oauth_state(github_provider_name(), payload.state) {
    Some(value) => value
    None => {
      log_github_callback_failure("state missing or expired")
      return Err("This GitHub sign-in link is invalid or has expired.")
    }
  }
  let headers : Map[String, String] = {
    "Accept": "application/json",
    "Content-Type": "application/x-www-form-urlencoded",
  }
  let token_response = match
    http_post(
      "https://github.com/login/oauth/access_token",
      github_token_request_body(
        client_id,
        client_secret,
        payload.code,
        github_callback_url(),
        pkce_verifier,
      ),
      headers~,
    ) {
    Ok(response) => response
    Err(_) => {
      log_github_token_exchange_failure("request", client_id, None, None)
      return Err(
        "GitHub sign-in failed while exchanging the authorization code.",
      )
    }
  }
  if !http_status_success(token_response.code) {
    log_github_token_exchange_failure(
      "response",
      client_id,
      Some(@mocket.StatusCode::from_int(token_response.code)),
      Some(http_response_text(token_response)),
    )
    return Err("GitHub sign-in failed while exchanging the authorization code.")
  }
  let access_token = match
    github_access_token_from_response(http_response_text(token_response)) {
    Ok(token) => token
    Err(message) =>
      return Err(
        "GitHub sign-in failed while parsing the access token response: \{message}",
      )
  }
  let profile = match github_fetch_profile(access_token) {
    Ok(profile) => profile
    Err(message) => return Err(message)
  }
  let email = match github_fetch_email(access_token) {
    Ok(email) => email
    Err(message) => return Err(message)
  }
  let provider_user_id = profile.id
  if self.store.find_user_by_oauth_account(
      github_provider_name(),
      provider_user_id,
    )
    is Some(user) {
    self.store.link_oauth_account(
      user.id,
      github_provider_name(),
      provider_user_id,
      access_token,
    )
    self.store.update_user_github_login(user.id, profile.login)
    self.store.set_user_email_verified(user.id)
    return Ok(self.store.get_user_by_id(user.id).unwrap_or(user))
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
    access_token,
  )
  self.store.update_user_github_login(user.id, profile.login)
  Ok(self.store.get_user_by_id(user.id).unwrap_or(user))
}

///|
async fn session_status_response(
  ctx : AppContext,
  event : @mocket.MocketEvent,
) -> @sdk.SessionResponse noraise {
  let user = session_user_from_event(ctx, event)
  {
    authenticated: user is Some(_),
    user,
    github_enabled: github_oauth_enabled(),
    app_mode: mooncraft_app_mode(),
  }
}

///|
async fn github_callback_page_html(root : String) -> String noraise {
  web_public_string(
    root, "control-plane-assets/auth/github-callback/index.html", "",
  )
}
