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
fn validated_project_display_name(value : String) -> Result[String, String] {
  let name = value.trim().to_owned()
  if name == "" {
    Err("Project name is required.")
  } else if name.length() > 80 {
    Err("Project name must be 80 characters or fewer.")
  } else {
    Ok(name)
  }
}

///|
fn ai_model_summary_from_admin(
  model : @sdk.AdminAiModelSummary,
) -> @sdk.AiModelSummary {
  {
    id: model.id,
    name: model.name,
    context_length: model.context_length,
    prompt_price: model.prompt_price,
    completion_price: model.completion_price,
  }
}

///|
fn model_allowed(model : String, allowed_models : Array[String]) -> Bool {
  let normalized = normalize_openrouter_model(model)
  for allowed in allowed_models {
    if normalize_openrouter_model(allowed) == normalized {
      return true
    }
  }
  false
}

///|
fn public_ai_model_list(
  response : @sdk.AdminListAiModelsResponse,
  config : @sdk.AdminAiConfigResponse,
) -> Array[@sdk.AiModelSummary] {
  let items : Array[@sdk.AiModelSummary] = []
  for model in response.items {
    if model_allowed(model.id, config.allowed_models) {
      items.push(ai_model_summary_from_admin(model))
    }
  }
  items
}

///|
fn openrouter_catalog_contains(
  items : Array[@sdk.AdminAiModelSummary],
  model : String,
) -> Bool {
  let normalized = normalize_openrouter_model(model)
  for item in items {
    if normalize_openrouter_model(item.id) == normalized {
      return true
    }
  }
  false
}

///|
fn normalized_config_models(
  default_model : String,
  allowed_models : Array[String],
) -> Array[String] {
  let normalized_default = normalize_openrouter_model(default_model)
  let normalized_allowed = normalize_allowed_models(allowed_models)
  if normalized_allowed.length() == 0 {
    [normalized_default]
  } else if normalized_allowed.contains(normalized_default) {
    normalized_allowed
  } else {
    let next = [normalized_default]
    for model in normalized_allowed {
      next.push(model)
    }
    next
  }
}

///|
async fn selected_project_runtime(
  store : Store,
  runtime_id : String?,
) -> Result[@sdk.RuntimeDetail, String] noraise {
  let selected_id = match runtime_id {
    Some(value) if value.trim() != "" => value.trim().to_owned()
    _ =>
      match store.get_default_runtime_id() {
        Ok(id) => id
        Err(message) => return Err(message)
      }
  }
  match store.get_runtime_detail(selected_id) {
    Ok(Some(runtime)) =>
      if runtime.enabled {
        Ok(runtime)
      } else {
        Err("That Runtime is not available in this workspace.")
      }
    Ok(None) => Err("That Runtime is not available in this workspace.")
    Err(message) => Err(message)
  }
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
fn unauthorized_response() -> @mocket.HttpResponse {
  api_error_response(Unauthorized, Unauthorized, "Sign in to continue.")
}

///|
let admin_session_cookie_name = "mooncraft_admin_session"

///|
let admin_session_max_age_seconds : Int = 60 * 60 * 12

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
fn admin_session_cookie_hash(event : @mocket.MocketEvent) -> String? {
  match event.req.get_cookie(admin_session_cookie_name) {
    Some(cookie) if cookie.value != "" => Some(cookie.value)
    _ => None
  }
}

///|
fn admin_token_hash(token : String) -> String {
  session_token_hash(token)
}

///|
fn request_has_valid_admin_session(
  event : @mocket.MocketEvent,
  expected_token : String,
) -> Bool {
  match admin_session_cookie_hash(event) {
    Some(value) => value == admin_token_hash(expected_token)
    None => false
  }
}

///|
fn request_has_valid_admin_token(
  event : @mocket.MocketEvent,
  expected_token : String,
) -> Bool {
  match request_admin_token(event) {
    Some(value) => value == expected_token
    None => false
  }
}

///|
fn request_is_admin(
  event : @mocket.MocketEvent,
  expected_token : String,
) -> Bool {
  request_has_valid_admin_token(event, expected_token) ||
  request_has_valid_admin_session(event, expected_token)
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
          "Admin access is temporarily unavailable.",
        ),
      )
  }
  if request_is_admin(event, expected) {
    Ok(())
  } else {
    Err(
      api_error_response(
        Unauthorized,
        Unauthorized,
        "A valid admin session or token is required.",
      ),
    )
  }
}

///|
fn admin_page_authorized(event : @mocket.MocketEvent) -> Bool {
  match admin_token() {
    Some(expected) => request_has_valid_admin_session(event, expected)
    None => false
  }
}

///|
fn set_admin_session_cookie(
  response : @mocket.HttpResponse,
  token : String,
) -> Unit {
  response.set_cookie(
    admin_session_cookie_name,
    admin_token_hash(token),
    max_age=admin_session_max_age_seconds,
    path="/",
    http_only=true,
    same_site=Lax,
  )
}

///|
fn clear_admin_session_cookie(response : @mocket.HttpResponse) -> Unit {
  response.set_cookie(
    admin_session_cookie_name,
    "",
    max_age=0,
    path="/",
    http_only=true,
    same_site=Lax,
  )
}

///|
struct AdminLoginRequest {
  token : String
} derive(Debug, @json.FromJson)

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
async fn read_admin_log_file(
  label : String,
  path : String?,
) -> @sdk.AdminRunLogFile noraise {
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
    Some(path) => {
      let exists = @async_fs.exists(path) catch {
        _ =>
          return {
            label,
            path: Some(path),
            exists: false,
            truncated: false,
            content: None,
            error: Some("The log file could not be checked on this node."),
          }
      }
      if !exists {
        {
          label,
          path: Some(path),
          exists: false,
          truncated: false,
          content: None,
          error: Some("The log file does not exist on this node."),
        }
      } else {
        let content = @async_fs.read_file(path).text() catch {
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
      debug.bind(fn(debug) { debug.runtime_log_path }),
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
  project : @sdk.AdminProjectSummary,
) -> @sdk.AdminProjectDiagnosticsResponse noraise {
  {
    project,
    messages: ctx.store.list_messages(project.project.id),
    runs: ctx.store.list_project_runs(project.project.id, 50),
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
  if event.req.headers.get("Content-Type") is Some(value) {
    headers["Content-Type"] = value.to_owned()
  } else if event.req.headers.get("content-type") is Some(value) {
    headers["Content-Type"] = value.to_owned()
  }
  if event.req.headers.get("Accept") is Some(value) {
    headers["Accept"] = value.to_owned()
  } else if event.req.headers.get("accept") is Some(value) {
    headers["Accept"] = value.to_owned()
  }
  headers
}

///|
fn proxy_response_headers(
  response : @mocket.HttpResponse,
) -> Map[StringView, StringView] {
  let headers : Map[StringView, StringView] = {}
  if response.headers.get("Content-Type") is Some(value) {
    headers["Content-Type"] = value
  } else if response.headers.get("content-type") is Some(value) {
    headers["Content-Type"] = value
  }
  if response.headers.get("Location") is Some(value) {
    headers["Location"] = value
  } else if response.headers.get("location") is Some(value) {
    headers["Location"] = value
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
    "/\{remainder}"
  }
}

///|
async fn proxy_preview_response(
  event : @mocket.MocketEvent,
  preview : @sdk.PreviewTarget,
  remainder : String,
) -> Result[@mocket.HttpResponse, String] noraise {
  let target_path = preview_target_path(remainder)
  let target_url = "http://127.0.0.1:\{preview.port}\{target_path}"
  let headers = proxy_request_headers(event)
  let upstream = try {
    if event.req.raw_body.length() == 0 {
      @mocket.fetch(target_url, proxy_method(event.req.http_method), headers~)
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
    _ => return Err("The preview process is not reachable.")
  } noraise {
    response => response
  }
  Ok(
    @mocket.HttpResponse::new(
      upstream.status_code,
      headers=proxy_response_headers(upstream),
      raw_body=proxy_response_body(upstream),
    ),
  )
}

///|
fn request_url_path(url : String) -> String {
  let without_scheme = match url.find("://") {
    Some(index) => {
      let rest = url[index + 3:].to_owned()
      match rest.find("/") {
        Some(path_index) => rest[path_index:].to_owned()
        None => "/"
      }
    }
    None => url
  }
  let without_query = match without_scheme.find("?") {
    Some(index) => without_scheme[:index].to_owned()
    None => without_scheme
  }
  if without_query == "" {
    "/"
  } else {
    without_query
  }
}

///|
async fn project_preview_proxy_response(
  ctx : AppContext,
  event : @mocket.MocketEvent,
  preview_public_id : String,
  remainder : String,
) -> @mocket.HttpResponse noraise {
  let project = match
    ctx.store.get_project_detail_by_preview_public_id(preview_public_id) {
    Some(project) => project
    None => return text_response(NotFound, "Project not found.")
  }
  match project.preview {
    Some(preview) =>
      match proxy_preview_response(event, preview, remainder) {
        Ok(response) => response
        Err(_) => {
          let _ = ctx.store.mark_project_preview_unreachable(
            project.id,
            "Preview is not reachable.",
          )
          text_response(
            BadGateway,
            "The preview is not reachable right now. Rerun the project to start a fresh preview.",
          )
        }
      }
    None =>
      text_response(NotFound, "No preview is available for this project yet.")
  }
}

///|
async fn preview_origin_proxy_response(
  ctx : AppContext,
  event : @mocket.MocketEvent,
) -> @mocket.HttpResponse? noraise {
  let host = match request_header(event, "Host") {
    Some(value) => value
    None => return None
  }
  let preview_public_id = match preview_public_id_from_host(host) {
    Some(value) => value
    None => return None
  }
  Some(
    project_preview_proxy_response(
      ctx,
      event,
      preview_public_id,
      request_url_path(event.req.url),
    ),
  )
}

///|
async fn preview_asset_response(
  path : String,
  content_type : String,
) -> @mocket.HttpResponse noraise {
  let exists = @async_fs.exists(path) catch { _ => false }
  if !exists {
    return text_response(NotFound, "Not Found")
  }
  let content = @async_fs.read_file(path).binary() catch {
    _ => return text_response(NotFound, "Not Found")
  }
  asset_response_bytes(content_type, content)
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
async fn static_preview_response(
  static_dir : String,
  target_path : String,
) -> @mocket.HttpResponse noraise {
  if target_path == "/__health" || target_path == "/api/health" {
    return json_ok(@sdk.HealthResponse::{ ok: true })
  }
  match static_preview_relative_path(target_path) {
    Some(relative_path) =>
      preview_asset_response(
        "\{static_dir}/\{relative_path}",
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
  app.get("/", async fn(_) noraise { static_preview_response(static_dir, "/") })
  app.get("/**", async fn(event) noraise {
    let remainder = event.params
      .get("_")
      .map(fn(value) { value.to_owned() })
      .unwrap_or("")
    static_preview_response(static_dir, preview_target_path(remainder))
  })
  @async.run_async_main(() => app.listen("0.0.0.0:\{port}"))
}

///|
async fn workspace_page_html(root : String) -> String noraise {
  web_public_string(root, "control-plane-assets/platform/index.html", "")
}

///|
async fn admin_page_html(root : String) -> String noraise {
  web_public_string(root, "control-plane-assets/admin/index.html", "")
}

///|
async fn admin_login_page_html(root : String) -> String noraise {
  web_public_string(root, "control-plane-assets/admin-login/index.html", "")
}

///|
async fn AppContext::serve_platform_bundle(
  self : AppContext,
) -> @mocket.HttpResponse noraise {
  let bundle_path = platform_web_build_output_path(
    self.root,
    self.build_profile,
  )
  let bundle = @async_fs.read_file(bundle_path).binary() catch { _ => b"" }
  if bundle.length() == 0 {
    return text_response(
      ServiceUnavailable,
      "The MoonCraft interface is temporarily unavailable.",
    )
  }
  javascript_response(bundle)
}

///|
async fn AppContext::serve_admin_bundle(
  self : AppContext,
) -> @mocket.HttpResponse noraise {
  let bundle_path = admin_web_build_output_path(self.root, self.build_profile)
  let bundle = @async_fs.read_file(bundle_path).binary() catch { _ => b"" }
  if bundle.length() == 0 {
    return text_response(
      ServiceUnavailable,
      "The MoonCraft admin interface is temporarily unavailable.",
    )
  }
  javascript_response(bundle)
}

///|
async fn AppContext::serve_platform_logo(
  self : AppContext,
) -> @mocket.HttpResponse noraise {
  asset_response_bytes(
    "image/svg+xml; charset=utf-8",
    @async_fs.read_file(web_public_path(self.root, "assets/logo.svg")).binary() catch {
      _ => b""
    },
  )
}

///|
async fn AppContext::serve_platform_asset(
  self : AppContext,
  event : @mocket.MocketEvent,
) -> @mocket.HttpResponse noraise {
  match event.params.get("_") {
    Some(value) if value.to_owned() == "logo.svg" => self.serve_platform_logo()
    Some(value) =>
      match safe_web_public_relative_path(value.to_owned()) {
        Some(relative) => {
          let asset_path = web_public_path(self.root, "assets/\{relative}")
          let asset_exists = fs_is_file(asset_path) catch { _ => false }
          if !asset_exists {
            return text_response(NotFound, "Not found")
          }
          asset_response_bytes(
            static_preview_content_type(relative),
            @async_fs.read_file(asset_path).binary() catch {
              _ => return text_response(NotFound, "Not found")
            },
          )
        }
        None => text_response(NotFound, "Not found")
      }
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
  if args.length() > 5 && args[1] == "run-worker" {
    let attempt = @string.parse_int(args[5]) catch { _ => 0 }
    @async.run_async_main(() => {
      run_worker_mode(root, args[2], args[3], args[4], attempt)
    })
    return
  }
  let port = control_plane_port()
  let ctx = match AppContext::try_new(root) {
    Ok(ctx) => ctx
    Err(message) => abort("MoonCraft cannot start: \{message}")
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
  let app = @mocket.new()

  app.get("/", async fn(event) noraise {
    match session_user_from_event(ctx, event) {
      Some(_) => html_response(workspace_page_html(ctx.root))
      None => redirect_response(@sdk.login_path())
    }
  })
  app.get(@sdk.login_path(), async fn(_) noraise {
    html_response(workspace_page_html(ctx.root))
  })
  app.get("/admin", async fn(event) noraise {
    if admin_page_authorized(event) {
      html_response(admin_page_html(ctx.root))
    } else {
      redirect_response("/admin/login")
    }
  })
  app.get("/admin/", async fn(event) noraise {
    if admin_page_authorized(event) {
      html_response(admin_page_html(ctx.root))
    } else {
      redirect_response("/admin/login")
    }
  })
  app.get("/admin/login", async fn(event) noraise {
    if admin_page_authorized(event) {
      redirect_response("/admin")
    } else {
      html_response(admin_login_page_html(ctx.root))
    }
  })
  app.get("/admin/login/", async fn(event) noraise {
    if admin_page_authorized(event) {
      redirect_response("/admin")
    } else {
      html_response(admin_login_page_html(ctx.root))
    }
  })
  app.get("/control-plane-assets/**", async fn(event) noraise {
    let remainder = event.params
      .get("_")
      .map(fn(value) { value.to_owned() })
      .unwrap_or("")
    web_public_response(ctx.root, "control-plane-assets/\{remainder}")
  })
  app.get("/app", async fn(_) noraise { ctx.serve_platform_bundle() })
  app.get("/admin/app", async fn(event) noraise {
    if admin_page_authorized(event) {
      ctx.serve_admin_bundle()
    } else {
      unauthorized_response()
    }
  })
  app.get("/assets/**", async fn(event) noraise {
    ctx.serve_platform_asset(event)
  })
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
  app.post("/api/admin/session", fn(event) noraise {
    let request : AdminLoginRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    let expected = match admin_token() {
      Some(value) => value
      None =>
        return api_error_response(
          ServiceUnavailable,
          ServiceUnavailable,
          "Admin login is temporarily unavailable.",
        )
    }
    if request.token.trim() == expected {
      set_admin_session_cookie(event.res, expected)
      json_no_content()
    } else {
      api_error_response(
        Unauthorized,
        InvalidCredentials,
        "The admin token is invalid.",
      )
    }
  })
  app.post("/api/admin/logout", fn(event) noraise {
    clear_admin_session_cookie(event.res)
    json_no_content()
  })
  app.get(@sdk.session_path(), async fn(event) noraise {
    json_ok(session_status_response(ctx, event))
  })
  app.get(@sdk.admin_run_logs_route().path_pattern, async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
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
    if require_admin_token(event) is Err(response) {
      return response
    }
    json_ok(@sdk.AdminListRunsResponse::{
      items: ctx.store.list_recent_runs(admin_limit_param(event)),
    })
  })
  app.get(@sdk.admin_run_route().path_pattern, event => {
    if require_admin_token(event) is Err(response) {
      return response
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
    if require_admin_token(event) is Err(response) {
      return response
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
    if require_admin_token(event) is Err(response) {
      return response
    }
    json_ok(@sdk.AdminListProjectsResponse::{
      items: ctx.store.list_recent_admin_project_summaries(
        admin_limit_param(event),
      ),
    })
  })
  app.get(@sdk.admin_users_route().path_pattern, event => {
    if require_admin_token(event) is Err(response) {
      return response
    }
    json_ok(@sdk.AdminListUsersResponse::{
      items: ctx.store.list_admin_users(admin_limit_param(event)),
    })
  })
  app.get(@sdk.admin_user_route().path_pattern, event => {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let user_id = match path_param(event, "user_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_admin_user_detail(user_id) {
      Some(user) =>
        json_ok(@sdk.AdminUserDetailResponse::{
          user,
          projects: ctx.store.list_admin_project_summaries_for_user(
            user.user.id,
          ),
        })
      None => api_error_response(NotFound, NotFound, "User not found.")
    }
  })
  app.get(@sdk.admin_user_projects_route().path_pattern, event => {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let user_id = match path_param(event, "user_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_user_by_id(user_id) {
      Some(user) =>
        json_ok(@sdk.AdminUserProjectsResponse::{
          user,
          projects: ctx.store.list_admin_project_summaries_for_user(user.id),
        })
      None => api_error_response(NotFound, NotFound, "User not found.")
    }
  })
  app.get(@sdk.admin_project_route().path_pattern, async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let project_id = match path_param(event, "project_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_admin_project_summary(project_id) {
      Some(project) => json_ok(admin_project_diagnostics_response(ctx, project))
      None => api_error_response(NotFound, NotFound, "Project not found.")
    }
  })
  app.get(@sdk.admin_project_messages_route().path_pattern, async fn(
    event,
  ) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let project_id = match path_param(event, "project_id") {
      Ok(value) => value
      Err(response) => return response
    }
    match ctx.store.get_admin_project_summary(project_id) {
      Some(project) =>
        json_ok(@sdk.AdminProjectMessagesResponse::{
          messages: ctx.store.list_messages(project.project.id),
          project,
        })
      None => api_error_response(NotFound, NotFound, "Project not found.")
    }
  })
  app.delete(@sdk.delete_admin_project_route().path_pattern, async fn(
    event,
  ) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let project_id = match path_param(event, "project_id") {
      Ok(value) => value
      Err(response) => return response
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
  app.post(@sdk.logout_path(), async fn(event) noraise {
    if event.req.get_cookie(session_cookie_name) is Some(cookie) {
      if cookie.value != "" {
        ctx.store.delete_session(session_token_hash(cookie.value))
      }
    }
    clear_session_cookie(event.res)
    json_no_content()
  })
  app.post("/api/dev/auth/session", async fn(event) noraise {
    let request : DevAuthRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match dev_authenticated_response(ctx, event, request) {
      Ok(response) => response
      Err(message) => api_error_response(NotFound, NotFound, message)
    }
  })
  app.get(@sdk.admin_secrets_path(), event => {
    match require_admin_token(event) {
      Ok(_) => {
        let response : @sdk.AdminListSecretsResponse = {
          items: ctx.store.list_admin_secrets(),
        }
        json_ok(response)
      }
      Err(response) => response
    }
  })
  app.post(@sdk.admin_secrets_path(), async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let request : @sdk.CreateAdminSecretRequest = match
      decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match ctx.store.create_admin_secret(request.name, request.value) {
      Ok(secret) => json_created(secret)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.patch(@sdk.admin_secret_route().path_pattern, async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let id = match path_param(event, "id") {
      Ok(id) => id
      Err(response) => return response
    }
    let request : @sdk.UpdateAdminSecretRequest = match
      decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match ctx.store.update_admin_secret(id, request.name, request.value) {
      Ok(secret) => json_ok(secret)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.delete(@sdk.admin_secret_route().path_pattern, async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let id = match path_param(event, "id") {
      Ok(id) => id
      Err(response) => return response
    }
    match ctx.store.delete_admin_secret(id) {
      Ok(_) => json_no_content()
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.get(@sdk.admin_ai_config_path(), event => {
    match require_admin_token(event) {
      Ok(_) => json_ok(ctx.store.get_admin_ai_config())
      Err(response) => response
    }
  })
  app.get(@sdk.admin_ai_models_path(), async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    match ctx.fetch_openrouter_models() {
      Ok(response) => json_ok(response)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.get(@sdk.ai_models_path(), async fn(event) noraise {
    if require_session_user(ctx, event) is Err(response) {
      return response
    }
    let config = ctx.store.get_admin_ai_config()
    match ctx.fetch_openrouter_models() {
      Ok(response) => {
        let items = public_ai_model_list(response, config)
        json_ok(@sdk.ListAiModelsResponse::{
          default_agent_cli: "",
          default_model: config.default_model,
          items,
          fetched_at: response.fetched_at,
        })
      }
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.get(@sdk.runtimes_path(), async fn(event) noraise {
    if require_session_user(ctx, event) is Err(response) {
      return response
    }
    let default_runtime_id = match ctx.store.get_default_runtime_id() {
      Ok(id) => id
      Err(_) => ""
    }
    let items = match ctx.store.list_enabled_runtimes() {
      Ok(items) => items
      Err(message) =>
        return api_error_response(
          UnprocessableEntity,
          ValidationFailed,
          message,
        )
    }
    json_ok(@sdk.ListRuntimesResponse::{ default_runtime_id, items })
  })
  app.get(@sdk.admin_runtimes_path(), async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let default_runtime_id = match ctx.store.get_default_runtime_id() {
      Ok(id) => id
      Err(_) => ""
    }
    let items = match ctx.store.list_admin_runtimes() {
      Ok(items) => items
      Err(message) =>
        return api_error_response(
          UnprocessableEntity,
          ValidationFailed,
          message,
        )
    }
    json_ok(@sdk.AdminListRuntimesResponse::{ default_runtime_id, items })
  })
  app.post(@sdk.admin_runtimes_path(), async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let request : @sdk.CreateAdminRuntimeRequest = match
      decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    let runtime_id = next_id("agent-runtime")
    match
      ctx.store.save_admin_runtime(
        runtime_id,
        request.name,
        request.spec_json,
        request.enabled,
        request.is_default,
      ) {
      Ok(runtime) => json_created(runtime)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.put(@sdk.admin_runtime_route().path_pattern, async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let runtime_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    let request : @sdk.UpdateAdminRuntimeRequest = match
      decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match
      ctx.store.save_admin_runtime(
        runtime_id,
        request.name,
        request.spec_json,
        request.enabled,
        request.is_default,
      ) {
      Ok(runtime) => json_ok(runtime)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.put(@sdk.admin_ai_config_path(), async fn(event) noraise {
    if require_admin_token(event) is Err(response) {
      return response
    }
    let request : @sdk.UpdateAdminAiConfigRequest = match
      decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    let catalog = match ctx.fetch_openrouter_models() {
      Ok(response) => response.items
      Err(message) =>
        return api_error_response(
          UnprocessableEntity,
          ValidationFailed,
          message,
        )
    }
    for
      model in normalized_config_models(
        request.default_model,
        request.allowed_models,
      ) {
      if !openrouter_catalog_contains(catalog, model) {
        return api_error_response(
          UnprocessableEntity,
          ValidationFailed,
          "Model must be available from OpenRouter.",
        )
      }
    }
    match
      ctx.store.update_admin_ai_config(
        request.default_model,
        request.allowed_models,
      ) {
      Ok(config) => json_ok(config)
      Err(message) =>
        api_error_response(UnprocessableEntity, ValidationFailed, message)
    }
  })
  app.get(@sdk.github_login_path(), async fn(_) noraise {
    github_authorization_response(ctx)
  })
  app.get("/auth/github/start", _ => redirect_response(@sdk.github_login_path()))
  app.get("/auth/github/callback", async fn(_) noraise {
    html_response(github_callback_page_html(ctx.root))
  })
  app.post("/api/auth/github/callback", async fn(event) noraise {
    let payload : GitHubCallbackPayload = match decode_json_body(event) {
      Ok(payload) => {
        println("info: GitHub OAuth callback payload accepted")
        payload
      }
      Err(response) => {
        log_github_callback_failure("invalid callback JSON payload")
        return response
      }
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
    let display_name = match
      validated_project_display_name(request.display_name) {
      Ok(name) => name
      Err(message) =>
        return api_error_response(
          UnprocessableEntity,
          ValidationFailed,
          message,
        )
    }
    let runtime = match
      selected_project_runtime(ctx.store, request.runtime_id) {
      Ok(runtime) => runtime
      Err(message) =>
        return api_error_response(
          UnprocessableEntity,
          ValidationFailed,
          message,
        )
    }
    let agent_cli = ""
    let selected_model = ""
    let project_id = next_id("project")
    let agent_session_id = next_id("agent-session")
    let workspace_path = project_workspace(ctx.root, project_id)
    let project = ctx.store.create_project_for_user(
      user.id,
      project_id,
      display_name,
      runtime.id,
      runtime.name,
      runtime_snapshot_json(runtime),
      agent_session_id,
      agent_cli,
      selected_model,
      workspace_path,
    )
    match ctx.materialize_project_workspace(project) {
      Ok(_) => json_created(@sdk.CreateProjectResponse::{ project, })
      Err(message) => {
        fs_remove_tree(project_root(ctx.root, project_id)) catch {
          _ => ()
        }
        ignore(ctx.store.delete_project(project_id))
        api_error_response(ServiceUnavailable, ServiceUnavailable, message)
      }
    }
  })
  app.put(@sdk.update_project_route().path_pattern, async fn(event) noraise {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    let request : @sdk.UpdateProjectRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    let display_name = match request.display_name {
      Some(value) =>
        match validated_project_display_name(value) {
          Ok(name) => Some(name)
          Err(message) =>
            return api_error_response(
              UnprocessableEntity,
              ValidationFailed,
              message,
            )
        }
      None => None
    }
    let selected_model = match request.model {
      Some(_) =>
        return api_error_response(
          UnprocessableEntity,
          ValidationFailed,
          "Project Runtime cannot be changed after creation.",
        )
      None => None
    }
    if display_name is None && selected_model is None {
      return api_error_response(
        UnprocessableEntity,
        ValidationFailed,
        "No project settings were provided.",
      )
    }
    match
      ctx.store.update_project_settings_for_user(
        user.id,
        project_id,
        display_name,
        selected_model,
      ) {
      Some(project) => json_ok(@sdk.UpdateProjectResponse::{ project, })
      None => api_error_response(NotFound, NotFound, "Project not found.")
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
    let worker = ctx.store.next_run_worker_registration(project_id, run.run_id)
    match
      ctx.spawn_project_turn_worker(
        project_id,
        run.run_id,
        worker.worker_id,
        worker.attempt,
      ) {
      Ok(worker_pid) =>
        match
          ctx.store.register_run_worker(
            project_id,
            run.run_id,
            worker.worker_id,
            worker.attempt,
            worker_pid,
          ) {
          Ok(_) =>
            json_created(@sdk.CreateRunResponse::{
              run: public_run_status(run),
              poll_after_ms: Some(1000),
            })
          Err(message) => {
            ignore(
              run_process_quiet("docker", [
                "rm",
                "-f",
                agent_runtime_container_name(project_id, run.run_id),
              ]),
            )
            terminate_process_tree(worker_pid)
            ctx.store.finish_run_failure(
              project_id,
              run.run_id,
              "The background worker could not be registered for that update.",
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
  app.post(@sdk.cancel_run_route().path_pattern, async fn(event) noraise {
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
    let run = match ctx.store.get_run_for_user(user.id, project_id, run_id) {
      Some(run) => run
      None => return api_error_response(NotFound, NotFound, "Run not found.")
    }
    if !(run.state is Running) {
      return api_error_response(
        Conflict,
        Conflict,
        "That run has already finished.",
      )
    }
    let worker = match ctx.store.get_running_run_worker(project_id, run_id) {
      Some(worker) => worker
      None =>
        return api_error_response(
          Conflict,
          Conflict,
          "That run is no longer active.",
        )
    }
    match ctx.cancel_project_run(project_id, run_id, worker) {
      Some(run) =>
        json_ok(@sdk.CancelRunResponse::{ run: public_run_status(run) })
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
    project_preview_proxy_response(ctx, event, preview_public_id, remainder)
  })
  app.all("/**", async fn(event) noraise {
    match preview_origin_proxy_response(ctx, event) {
      Some(response) => response
      None => text_response(NotFound, "Not Found")
    }
  })

  println("MoonCraft running at http://localhost:\{port}")
  @async.run_async_main(() => {
    @async.with_task_group(group => {
      group.spawn_bg(() => ctx.run_worker_reconciler_loop())
      group.spawn_bg(() => ctx.run_runtime_service_ttl_loop())
      serve_mocket_async(app, port)
    })
  })
}
