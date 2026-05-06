///|
fn json_response(
  code : @mocket.StatusCode,
  value : &ToJson,
) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(code).json(value)
}

///|
fn json_ok(value : &ToJson) -> @mocket.HttpResponse {
  json_response(OK, value)
}

///|
fn json_created(value : &ToJson) -> @mocket.HttpResponse {
  json_response(Created, value)
}

///|
fn json_no_content() -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(NoContent).body("")
}

///|
fn api_error_response(
  status : @mocket.StatusCode,
  code : @sdk.ApiErrorCode,
  message : String,
) -> @mocket.HttpResponse {
  json_response(status, @sdk.ApiErrorResponse::{ error: { code, message } })
}

///|
fn text_response(
  code : @mocket.StatusCode,
  message : String,
) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(code).body(message)
}

///|
fn html_response(content : String) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(OK).body(@mocket.html(content))
}

///|
fn javascript_response(content : Bytes) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(
    OK,
    headers={ "Content-Type": "text/javascript; charset=utf-8" },
    raw_body=content,
  )
}

///|
fn asset_response_bytes(
  content_type : String,
  content : Bytes,
) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(
    OK,
    headers={ "Content-Type": content_type },
    raw_body=content,
  )
}

///|
fn platform_logo_asset_path(root : String) -> String {
  root + "/apps/web/assets/logo.svg"
}

///|
fn unauthorized_response() -> @mocket.HttpResponse {
  api_error_response(Unauthorized, Unauthorized, "Sign in to continue.")
}

///|
fn admin_token() -> String? {
  match @env.get_env_var("MOONCRAFT_ADMIN_TOKEN") {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn request_header(event : @mocket.MocketEvent, name : String) -> String? {
  match event.req.headers.get(name) {
    Some(value) => Some(value.to_owned())
    None =>
      event.req.headers.get(name.to_lower()).map(fn(value) { value.to_owned() })
  }
}

///|
fn bearer_token(value : String) -> String? {
  match value.strip_prefix("Bearer ") {
    Some(token) if token.trim() != "" => Some(token.trim().to_owned())
    _ => None
  }
}

///|
fn request_admin_token(event : @mocket.MocketEvent) -> String? {
  match request_header(event, "Authorization").bind(bearer_token) {
    Some(token) => Some(token)
    None =>
      request_header(event, "X-Mooncraft-Admin-Token").map(fn(value) {
        value.trim().to_owned()
      })
  }
}

///|
fn require_admin_token(
  event : @mocket.MocketEvent,
) -> Result[Unit, @mocket.HttpResponse] {
  let expected = match admin_token() {
    Some(value) => value
    None =>
      return Err(
        api_error_response(
          ServiceUnavailable,
          ServiceUnavailable,
          "Admin diagnostics are not configured.",
        ),
      )
  }
  match request_admin_token(event) {
    Some(value) if value == expected => Ok(())
    _ =>
      Err(
        api_error_response(
          Unauthorized,
          Unauthorized,
          "A valid admin token is required.",
        ),
      )
  }
}

///|
fn public_run_error_message(run : @sdk.RunStatusResponse) -> String? {
  if !(run.state is Failed) {
    run.error_message
  } else {
    match run.summary {
      Some(message) => Some(message)
      None => Some("The run failed before the preview could be refreshed.")
    }
  }
}

///|
fn public_run_status(run : @sdk.RunStatusResponse) -> @sdk.RunStatusResponse {
  if mooncraft_development_mode() {
    run
  } else {
    { ..run, error_message: public_run_error_message(run), failure_debug: None }
  }
}

///|
let admin_log_content_limit = 200_000

///|
fn limit_admin_log_content(content : String) -> (String, Bool) {
  if content.length() <= admin_log_content_limit {
    (content, false)
  } else {
    (
      content.unsafe_substring(
        start=content.length() - admin_log_content_limit,
        end=content.length(),
      ),
      true,
    )
  }
}

///|
fn read_admin_log_file(label : String, path : String?) -> @sdk.AdminRunLogFile {
  match path {
    None =>
      {
        label,
        path: None,
        exists: false,
        truncated: false,
        content: None,
        error: Some("No log path was recorded for this run."),
      }
    Some(path) =>
      if !@fs.path_exists(path) {
        {
          label,
          path: Some(path),
          exists: false,
          truncated: false,
          content: None,
          error: Some("The log file does not exist on this node."),
        }
      } else {
        let content = @fs.read_file_to_string(path) catch {
          _ =>
            return {
              label,
              path: Some(path),
              exists: true,
              truncated: false,
              content: None,
              error: Some("The log file could not be read."),
            }
        }
        let (content, truncated) = limit_admin_log_content(content)
        {
          label,
          path: Some(path),
          exists: true,
          truncated,
          content: Some(content),
          error: None,
        }
      }
  }
}

///|
async fn admin_run_logs_response(
  ctx : AppContext,
  run : @sdk.RunStatusResponse,
) -> @sdk.AdminRunLogsResponse noraise {
  let debug = run.failure_debug
  let logs : Array[@sdk.AdminRunLogFile] = []
  logs.push(
    read_admin_log_file(
      "builder",
      debug.bind(fn(debug) { debug.codex_log_path }),
    ),
  )
  logs.push(
    read_admin_log_file(
      "validation",
      debug.bind(fn(debug) { debug.validation_log_path }),
    ),
  )
  logs.push(
    read_admin_log_file(
      "final_summary",
      debug.bind(fn(debug) { debug.final_summary_path }),
    ),
  )
  {
    run,
    events: ctx.store.list_run_events(run.project_id, run.run_id, 0),
    logs,
  }
}

///|
fn redirect_response(location : String) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(Found, headers={ "Location": location }).body("")
}

///|
fn[T : FromJson] decode_json_body(
  event : @mocket.MocketEvent,
) -> Result[T, @mocket.HttpResponse] {
  let body : Json = event.req.body() catch {
    _ =>
      return Err(
        api_error_response(
          BadRequest,
          InvalidJson,
          "The request body must be valid JSON.",
        ),
      )
  }
  Ok(
    @json.from_json(body) catch {
      _ =>
        return Err(
          api_error_response(
            BadRequest,
            InvalidJson,
            "The JSON body does not match the expected shape.",
          ),
        )
    },
  )
}

///|
fn path_param(
  event : @mocket.MocketEvent,
  name : String,
) -> Result[String, @mocket.HttpResponse] {
  match event.params.get(name) {
    Some(value) => Ok(value.to_owned())
    None =>
      Err(
        api_error_response(
          BadRequest,
          ValidationFailed,
          "Missing route parameter: \{name}.",
        ),
      )
  }
}

///|
fn admin_limit_param(event : @mocket.MocketEvent) -> Int {
  let raw = match path_param(event, "limit") {
    Ok(value) => @string.parse_int(value) catch { _ => 50 }
    Err(_) => 50
  }
  if raw < 1 {
    1
  } else if raw > 200 {
    200
  } else {
    raw
  }
}

///|
async fn admin_project_diagnostics_response(
  ctx : AppContext,
  project : @sdk.ProjectDetail,
) -> @sdk.AdminProjectDiagnosticsResponse noraise {
  {
    project,
    messages: ctx.store.list_messages(project.id),
    runs: ctx.store.list_project_runs(project.id, 50),
  }
}

///|
fn proxy_method(http_method_name : String) -> @mocket.HttpMethod {
  match http_method_name {
    "POST" => POST
    "PUT" => PUT
    "PATCH" => PATCH
    "DELETE" => DELETE
    "HEAD" => HEAD
    "OPTIONS" => OPTIONS
    "TRACE" => TRACE
    "CONNECT" => CONNECT
    _ => GET
  }
}

///|
fn proxy_request_headers(event : @mocket.MocketEvent) -> Map[String, String] {
  let headers : Map[String, String] = {}
  match event.req.headers.get("Content-Type") {
    Some(value) => headers["Content-Type"] = value.to_owned()
    None =>
      match event.req.headers.get("content-type") {
        Some(value) => headers["Content-Type"] = value.to_owned()
        None => ignore(())
      }
  }
  match event.req.headers.get("Accept") {
    Some(value) => headers["Accept"] = value.to_owned()
    None =>
      match event.req.headers.get("accept") {
        Some(value) => headers["Accept"] = value.to_owned()
        None => ignore(())
      }
  }
  headers
}

///|
fn proxy_response_headers(
  response : @mocket.HttpResponse,
) -> Map[StringView, StringView] {
  let headers : Map[StringView, StringView] = {}
  match response.headers.get("Content-Type") {
    Some(value) => headers["Content-Type"] = value
    None =>
      match response.headers.get("content-type") {
        Some(value) => headers["Content-Type"] = value
        None => ignore(())
      }
  }
  match response.headers.get("Location") {
    Some(value) => headers["Location"] = value
    None =>
      match response.headers.get("location") {
        Some(value) => headers["Location"] = value
        None => ignore(())
      }
  }
  headers
}

///|
fn proxy_response_body(response : @mocket.HttpResponse) -> Bytes {
  if response.raw_body.length() > 0 {
    response.raw_body
  } else {
    let body : String = response.read_body() catch { _ => "" }
    @utf8.encode(body)
  }
}

///|
fn preview_target_path(remainder : String) -> String {
  if remainder == "" {
    "/"
  } else if remainder.has_prefix("/") {
    remainder
  } else {
    "/" + remainder
  }
}

///|
fn preview_asset_response(
  path : String,
  content_type : String,
) -> @mocket.HttpResponse {
  if !@fs.path_exists(path) {
    return text_response(NotFound, "Not Found")
  }
  asset_response_bytes(content_type, safe_read_bytes_or(path, b""))
}

///|
fn static_preview_content_type(path : String) -> String {
  if path.has_suffix(".html") {
    "text/html; charset=utf-8"
  } else if path.has_suffix(".css") {
    "text/css; charset=utf-8"
  } else if path.has_suffix(".js") || path.has_suffix(".mjs") {
    "text/javascript; charset=utf-8"
  } else if path.has_suffix(".json") || path.has_suffix(".map") {
    "application/json; charset=utf-8"
  } else if path.has_suffix(".wasm") {
    "application/wasm"
  } else if path.has_suffix(".svg") {
    "image/svg+xml"
  } else if path.has_suffix(".png") {
    "image/png"
  } else if path.has_suffix(".jpg") || path.has_suffix(".jpeg") {
    "image/jpeg"
  } else if path.has_suffix(".webp") {
    "image/webp"
  } else if path.has_suffix(".ico") {
    "image/x-icon"
  } else if path.has_suffix(".txt") {
    "text/plain; charset=utf-8"
  } else {
    "application/octet-stream"
  }
}

///|
fn static_preview_relative_path(target_path : String) -> String? {
  let normalized_target = match target_path {
    "/" => "index.html"
    "/app" => "app.js"
    "/styles" => "styles.css"
    other => other
  }
  let parts = normalized_target.split("/").to_array()
  let safe_parts : Array[String] = []
  for part in parts {
    let piece = part.to_owned()
    if piece == "" {
      continue
    }
    if piece == "." || piece == ".." {
      return None
    }
    safe_parts.push(piece)
  }
  if safe_parts.length() == 0 {
    Some("index.html")
  } else {
    Some(safe_parts.join("/"))
  }
}

///|
fn static_preview_response(
  static_dir : String,
  target_path : String,
) -> @mocket.HttpResponse {
  if target_path == "/__health" || target_path == "/api/health" {
    return json_ok(@sdk.HealthResponse::{ ok: true })
  }
  match static_preview_relative_path(target_path) {
    Some(relative_path) =>
      preview_asset_response(
        static_dir + "/" + relative_path,
        static_preview_content_type(relative_path),
      )
    None => text_response(NotFound, "Not Found")
  }
}

///|
fn run_static_preview_mode(port : Int, static_dir : String) -> Unit {
  let app = @mocket.new()
  app.get("/__health", _ => json_ok(@sdk.HealthResponse::{ ok: true }))
  app.get("/api/health", _ => json_ok(@sdk.HealthResponse::{ ok: true }))
  app.get("/", _ => static_preview_response(static_dir, "/"))
  app.get("/**", event => {
    let remainder = event.params
      .get("_")
      .map(fn(value) { value.to_owned() })
      .unwrap_or("")
    static_preview_response(static_dir, preview_target_path(remainder))
  })
  @async.run_async_main(() => app.listen("0.0.0.0:\{port}"))
}

///|
fn workspace_page_html(root : String) -> String {
  control_plane_asset_string(root, "platform/index.html", "")
}

///|
fn AppContext::ensure_platform_web_bundle(self : AppContext) -> Unit {
  ensure_dir(platform_web_dist_dir(self.root))
  let code = shell_status(
    "cd '\{self.root}' && moon build --manifest-path '\{self.root}/moon.work' \{self.build_profile.cli_flag()}>/dev/null 2>&1",
  )
  if code != 0 {
    println("warning: failed to build apps/web bundle")
    return
  }
  let source = platform_web_build_output_path(self.root, self.build_profile)
  if !@fs.path_exists(source) {
    println("warning: apps/web bundle was built but the artifact was not found")
    return
  }
  let bundle = safe_read_bytes_or(source, b"")
  if bundle.length() == 0 {
    println("warning: apps/web bundle was built but the artifact was empty")
    return
  }
  safe_write_bytes(platform_web_staged_bundle_path(self.root), bundle)
}

///|
fn AppContext::serve_platform_bundle(self : AppContext) -> @mocket.HttpResponse {
  let bundle_path = platform_web_staged_bundle_path(self.root)
  let bundle = safe_read_bytes_or(bundle_path, b"")
  if bundle.length() == 0 {
    return text_response(
      ServiceUnavailable,
      "The UI bundle has not been staged yet. Restart the control plane after building apps/web.",
    )
  }
  javascript_response(bundle)
}

///|
fn AppContext::serve_platform_logo(self : AppContext) -> @mocket.HttpResponse {
  asset_response_bytes(
    "image/svg+xml; charset=utf-8",
    safe_read_bytes_or(platform_logo_asset_path(self.root), b""),
  )
}

///|
fn AppContext::serve_platform_asset(
  self : AppContext,
  event : @mocket.MocketEvent,
) -> @mocket.HttpResponse {
  match event.params.get("_") {
    Some(value) if value.to_owned() == "logo.svg" => self.serve_platform_logo()
    _ => text_response(NotFound, "Not found")
  }
}

///|
fn control_plane_port() -> Int {
  match @env.get_env_var("MOONCRAFT_PORT") {
    Some(value) => @string.parse_int(value) catch { _ => 8080 }
    None => 8080
  }
}

///|
fn main {
  let root = @env.current_dir().unwrap_or(".")
  let args = @env.args()
  if args.length() > 3 && args[1] == "run-static-preview" {
    let port = @string.parse_int(args[2]) catch { _ => 4300 }
    run_static_preview_mode(port, args[3])
    return
  }
  if args.length() > 3 && args[1] == "run-worker" {
    @async.run_async_main(() => run_worker_mode(root, args[2], args[3]))
    return
  }
  let port = control_plane_port()
  let ctx = match AppContext::try_new(root) {
    Ok(ctx) => ctx
    Err(message) => abort("Mooncraft cannot start: " + message)
  }
  let stale_runs_ref : Ref[Int] = @ref.new(0)
  @async.run_async_main(async fn() {
    stale_runs_ref.val = ctx.store.fail_stale_running_runs_on_startup()
  })
  let stale_runs = stale_runs_ref.val
  if stale_runs > 0 {
    println(
      "Recovered \{stale_runs} stale running run(s); marked them failed so they can be retried.",
    )
  }
  ctx.ensure_platform_web_bundle()

  let app = @mocket.new()

  app.get("/", _ => html_response(workspace_page_html(ctx.root)))
  app.get("/control-plane-assets/**", event => {
    let remainder = event.params
      .get("_")
      .map(fn(value) { value.to_owned() })
      .unwrap_or("")
    control_plane_asset_response(ctx.root, remainder)
  })
  app.get("/app", _ => ctx.serve_platform_bundle())
  app.get("/assets/**", event => ctx.serve_platform_asset(event))
  app.get(@sdk.health_path(), async fn(_) noraise {
    if ctx.store.is_available() {
      json_ok(@sdk.HealthResponse::{ ok: true })
    } else {
      api_error_response(
        ServiceUnavailable,
        ServiceUnavailable,
        "The database is not available.",
      )
    }
  })
  app.get(@sdk.session_path(), async fn(event) noraise {
    json_ok(session_status_response(ctx, event))
  })
  app.get(@sdk.admin_run_logs_route().path_pattern, async fn(event) noraise {
    match require_admin_token(event) {
      Ok(_) => ignore(())
      Err(response) => return response
    }
    let run_id = match path_param(event, "run_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_run_by_id(run_id) {
      Some(run) => json_ok(admin_run_logs_response(ctx, run))
      None => api_error_response(NotFound, NotFound, "Run not found.")
    }
  })
  app.get(@sdk.admin_recent_runs_route().path_pattern, event => {
    match require_admin_token(event) {
      Ok(_) => ignore(())
      Err(response) => return response
    }
    json_ok(@sdk.AdminListRunsResponse::{
      items: ctx.store.list_recent_runs(admin_limit_param(event)),
    })
  })
  app.get(@sdk.admin_run_route().path_pattern, event => {
    match require_admin_token(event) {
      Ok(_) => ignore(())
      Err(response) => return response
    }
    let run_id = match path_param(event, "run_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_run_by_id(run_id) {
      Some(run) => json_ok(run)
      None => api_error_response(NotFound, NotFound, "Run not found.")
    }
  })
  app.get(@sdk.admin_run_events_route().path_pattern, event => {
    match require_admin_token(event) {
      Ok(_) => ignore(())
      Err(response) => return response
    }
    let run_id = match path_param(event, "run_id") {
      Ok(value) => value
      Err(response) => return response
    }
    let run = match ctx.store.get_run_by_id(run_id) {
      Some(run) => run
      None => return api_error_response(NotFound, NotFound, "Run not found.")
    }
    let after_seq = match path_param(event, "after_seq") {
      Ok(value) => @string.parse_int(value) catch { _ => 0 }
      Err(_) => 0
    }
    json_ok(@sdk.ListRunEventsResponse::{
      items: ctx.store.list_run_events(run.project_id, run.run_id, after_seq),
    })
  })
  app.get(@sdk.admin_recent_projects_route().path_pattern, event => {
    match require_admin_token(event) {
      Ok(_) => ignore(())
      Err(response) => return response
    }
    json_ok(@sdk.AdminListProjectsResponse::{
      items: ctx.store.list_recent_projects(admin_limit_param(event)),
    })
  })
  app.get(@sdk.admin_project_route().path_pattern, async fn(event) noraise {
    match require_admin_token(event) {
      Ok(_) => ignore(())
      Err(response) => return response
    }
    let project_id = match path_param(event, "project_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_project_detail(project_id) {
      Some(project) => json_ok(admin_project_diagnostics_response(ctx, project))
      None => api_error_response(NotFound, NotFound, "Project not found.")
    }
  })
  app.post(@sdk.signup_path(), async fn(event) noraise {
    let request : @sdk.SignupRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match signup_user(ctx, request) {
      Ok(user) => authenticated_response(ctx, event, user, status=Created)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.post(@sdk.login_path(), async fn(event) noraise {
    let request : @sdk.LoginRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match login_user(ctx, request) {
      Ok(user) => authenticated_response(ctx, event, user)
      Err(message) =>
        api_error_response(Unauthorized, InvalidCredentials, message)
    }
  })
  app.post(@sdk.logout_path(), async fn(event) noraise {
    match event.req.get_cookie(session_cookie_name) {
      Some(cookie) if cookie.value != "" =>
        ctx.store.delete_session(session_token_hash(cookie.value))
      _ => ignore(())
    }
    clear_session_cookie(event.res)
    json_no_content()
  })
  app.get("/auth/email/verify", _ => {
    html_response(email_verification_page_html(ctx.root))
  })
  app.get("/auth/password/reset", _ => {
    html_response(password_reset_page_html(ctx.root))
  })
  app.post(@sdk.request_password_reset_path(), async fn(event) noraise {
    let request : @sdk.RequestPasswordResetRequest = match
      decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    json_ok(request_password_reset(ctx, request))
  })
  app.post(@sdk.reset_password_path(), async fn(event) noraise {
    let request : @sdk.ResetPasswordRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match reset_password(ctx, request) {
      Ok(response) => json_ok(response)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.post(@sdk.change_password_path(), async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let request : @sdk.ChangePasswordRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match change_password(ctx, user, request) {
      Ok(response) => json_ok(response)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.post(@sdk.resend_email_verification_path(), async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    json_ok(resend_email_verification(ctx, user))
  })
  app.post(@sdk.verify_email_path(), async fn(event) noraise {
    let request : @sdk.VerifyEmailRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match verify_email(ctx, request) {
      Ok(response) => json_ok(response)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.get(@sdk.ai_settings_path(), async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    match ctx.store.get_ai_settings(user.id) {
      Some(settings) => json_ok(settings)
      None => api_error_response(NotFound, NotFound, "User not found.")
    }
  })
  app.get(@sdk.ai_model_options_route().path_pattern, async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let provider = match path_param(event, "provider") {
      Ok(provider) => provider
      Err(response) => return response
    }
    let credentials = match ctx.store.get_ai_credential_settings(user.id) {
      Some(settings) => settings
      None => return api_error_response(NotFound, NotFound, "User not found.")
    }
    match list_ai_model_options(user.id, provider, credentials) {
      Ok(response) => json_ok(response)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.put(@sdk.ai_settings_path(), async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let request : @sdk.UpdateAiSettingsRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match
      ctx.store.update_ai_settings(
        user.id,
        request.provider,
        request.model,
        request.api_key,
      ) {
      Ok(settings) => json_ok(settings)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.get("/auth/github/start", async fn(_) noraise {
    github_authorization_response(ctx)
  })
  app.get("/auth/github/callback", _ => {
    html_response(github_callback_page_html(ctx.root))
  })
  app.post("/api/auth/github/callback", async fn(event) noraise {
    let payload : GitHubCallbackPayload = match decode_json_body(event) {
      Ok(payload) => payload
      Err(response) => return response
    }
    match ctx.complete_github_sign_in(payload) {
      Ok(user) => authenticated_response(ctx, event, user)
      Err(message) => api_error_response(BadRequest, ValidationFailed, message)
    }
  })

  app.get(@sdk.projects_path(), async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    json_ok(@sdk.ListProjectsResponse::{
      items: ctx.store.list_projects_for_user(user.id),
    })
  })
  app.post(@sdk.projects_path(), async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let request : @sdk.CreateProjectRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    let project_id = next_id("project")
    let workspace_path = project_workspace(ctx.root, project_id)
    let project = ctx.store.create_project_for_user(
      user.id,
      project_id,
      request.display_name,
      workspace_path,
    )
    match ctx.materialize_project_workspace(project) {
      Ok(_) => json_created(@sdk.CreateProjectResponse::{ project, })
      Err(message) => {
        safe_remove_tree(project_root(ctx.root, project_id))
        ignore(ctx.store.delete_project(project_id))
        api_error_response(ServiceUnavailable, ServiceUnavailable, message)
      }
    }
  })
  app.delete(@sdk.delete_project_route().path_pattern, async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    if ctx.store.get_project_detail_for_user(project_id, user.id) is None {
      return api_error_response(NotFound, NotFound, "Project not found.")
    }
    match ctx.delete_project(project_id) {
      Ok(_) => json_no_content()
      Err(message) =>
        if message == "Project not found." {
          api_error_response(NotFound, NotFound, message)
        } else {
          api_error_response(Conflict, Conflict, message)
        }
    }
  })
  app.get(@sdk.project_route().path_pattern, async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_project_detail_for_user(project_id, user.id) {
      Some(project) => json_ok(project)
      None => api_error_response(NotFound, NotFound, "Project not found.")
    }
  })
  app.get(@sdk.list_messages_route().path_pattern, async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.list_messages_for_user(user.id, project_id) {
      Some(messages) => json_ok(@sdk.ListMessagesResponse::{ items: messages })
      None => api_error_response(NotFound, NotFound, "Project not found.")
    }
  })
  app.post(@sdk.create_run_route().path_pattern, async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    let request : @sdk.CreateRunRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    if request.content == "" {
      return api_error_response(
        UnprocessableEntity,
        ValidationFailed,
        "Message content cannot be empty.",
      )
    }
    let run = match
      ctx.store.start_run_for_user(user.id, project_id, request.content) {
      Ok(run) => run
      Err(message) => return api_error_response(Conflict, Conflict, message)
    }
    match ctx.spawn_project_turn_worker(project_id, run.run_id) {
      Ok(worker_pid) => {
        ctx.store.set_run_worker_pid(project_id, run.run_id, worker_pid)
        json_created(@sdk.CreateRunResponse::{
          run: public_run_status(run),
          poll_after_ms: Some(1000),
        })
      }
      Err(message) => {
        ctx.store.finish_run_failure(
          project_id,
          run.run_id,
          "The background worker could not be started for that update.",
          message,
          None,
        )
        let latest_run = ctx.store
          .get_run(project_id, run.run_id)
          .unwrap_or(run)
        json_created(@sdk.CreateRunResponse::{
          run: public_run_status(latest_run),
          poll_after_ms: None,
        })
      }
    }
  })
  app.get(@sdk.get_run_route().path_pattern, async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    let run_id = match path_param(event, "run_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_run_for_user(user.id, project_id, run_id) {
      Some(run) => json_ok(public_run_status(run))
      None => api_error_response(NotFound, NotFound, "Run not found.")
    }
  })
  app.get(@sdk.list_run_events_route().path_pattern, event => {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    let run_id = match path_param(event, "run_id") {
      Ok(value) => value
      Err(response) => return response
    }
    let after_seq = match path_param(event, "after_seq") {
      Ok(value) => @string.parse_int(value) catch { _ => 0 }
      Err(_) => 0
    }
    match
      ctx.store.list_run_events_for_user(user.id, project_id, run_id, after_seq) {
      Some(items) => json_ok(@sdk.ListRunEventsResponse::{ items, })
      None => api_error_response(NotFound, NotFound, "Run not found.")
    }
  })
  app.all(@sdk.preview_route_pattern(), async fn(event) noraise {
    let preview_public_id = match path_param(event, "preview_public_id") {
      Ok(value) => value
      Err(response) => return response
    }
    let remainder = event.params
      .get("_")
      .map(fn(value) { value.to_owned() })
      .unwrap_or("")
    let project = match
      ctx.store.get_project_detail_by_preview_public_id(preview_public_id) {
      Some(project) => project
      None => return text_response(NotFound, "Project not found.")
    }
    match project.preview {
      Some(preview) => {
        let target_path = preview_target_path(remainder)
        let target_url = "http://127.0.0.1:\{preview.port}\{target_path}"
        let headers = proxy_request_headers(event)
        let upstream = try {
          if event.req.raw_body.length() == 0 {
            @mocket.fetch(
              target_url,
              proxy_method(event.req.http_method),
              headers~,
            )
          } else {
            let body = bytes_to_string(event.req.raw_body)
            @mocket.fetch(
              target_url,
              proxy_method(event.req.http_method),
              body~,
              headers~,
            )
          }
        } catch {
          _ =>
            return text_response(
              BadGateway,
              "The preview is not reachable right now. Try rerunning the project.",
            )
        } noraise {
          response => response
        }
        @mocket.HttpResponse::new(
          upstream.status_code,
          headers=proxy_response_headers(upstream),
          raw_body=proxy_response_body(upstream),
        )
      }
      None =>
        text_response(NotFound, "No preview is available for this project yet.")
    }
  })

  println("Mooncraft running at http://localhost:\{port}")
  @async.run_async_main(() => serve_mocket_async(app, port))
}
