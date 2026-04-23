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
  json_response(status, @sdk.ApiErrorResponse::{
    error: @sdk.ApiError::{ code, message },
  })
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
fn unauthorized_response() -> @mocket.HttpResponse {
  api_error_response(Unauthorized, @sdk.Unauthorized, "Sign in to continue.")
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
          @sdk.InvalidJson,
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
            @sdk.InvalidJson,
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
    Some(value) => Ok(value.to_string())
    None =>
      Err(
        api_error_response(
          BadRequest,
          @sdk.ValidationFailed,
          "Missing route parameter: \{name}.",
        ),
      )
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
    Some(value) => headers["Content-Type"] = value.to_string()
    None =>
      match event.req.headers.get("content-type") {
        Some(value) => headers["Content-Type"] = value.to_string()
        None => ignore(())
      }
  }
  match event.req.headers.get("Accept") {
    Some(value) => headers["Accept"] = value.to_string()
    None =>
      match event.req.headers.get("accept") {
        Some(value) => headers["Accept"] = value.to_string()
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
  @mocket.HttpResponse::new(OK, headers={ "Content-Type": content_type }).body(
    safe_read_string_or(path, ""),
  )
}

///|
fn static_preview_response(
  static_dir : String,
  target_path : String,
) -> @mocket.HttpResponse {
  match target_path {
    "/" =>
      preview_asset_response(
        static_dir + "/index.html",
        "text/html; charset=utf-8",
      )
    "/app" =>
      preview_asset_response(
        static_dir + "/app.js",
        "text/javascript; charset=utf-8",
      )
    "/styles" =>
      preview_asset_response(
        static_dir + "/styles.css",
        "text/css; charset=utf-8",
      )
    "/__health" | "/api/health" => json_ok(@sdk.HealthResponse::{ ok: true })
    _ => text_response(NotFound, "Not Found")
  }
}

///|
fn run_static_preview_mode(port : Int, static_dir : String) -> Unit {
  let app = @mocket.new()
  app.get("/__health", _ => json_ok(@sdk.HealthResponse::{ ok: true }))
  app.get("/api/health", _ => json_ok(@sdk.HealthResponse::{ ok: true }))
  app.get("/", _ => static_preview_response(static_dir, "/"))
  app.get("/app", _ => static_preview_response(static_dir, "/app"))
  app.get("/styles", _ => static_preview_response(static_dir, "/styles"))
  app.serve(port~)
}

///|
fn workspace_page_html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8" />
    #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
    #|    <title>MoonBit Cloud</title>
    #|    <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%2305080c'/%3E%3Cpath d='M14 18h14v28H14zm22 0h14v28H36z' fill='%2338efb7'/%3E%3C/svg%3E" />
    #|    <style>
    #|      :root {
    #|        color-scheme: dark;
    #|        font-family: "IBM Plex Sans", "Helvetica Neue", sans-serif;
    #|        background:
    #|          radial-gradient(circle at top left, rgba(24, 255, 176, 0.12), transparent 28%),
    #|          radial-gradient(circle at top right, rgba(45, 125, 255, 0.14), transparent 24%),
    #|          linear-gradient(180deg, #091119, #05080c);
    #|        color: #eff7ff;
    #|      }
    #|
    #|      * {
    #|        box-sizing: border-box;
    #|      }
    #|
    #|      body {
    #|        margin: 0;
    #|        min-height: 100vh;
    #|        background: #05080c;
    #|      }
    #|
    #|      #app {
    #|        min-height: 100vh;
    #|      }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <div id="app"></div>
    #|    <script type="module" src="/app"></script>
    #|  </body>
    #|</html>
  )
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
fn control_plane_port() -> Int {
  match @env.get_env_var("MOONBITCLOUD_PORT") {
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
  let ctx = AppContext::new(root)
  ctx.ensure_platform_web_bundle()

  let app = @mocket.new()

  app.get("/", _ => html_response(workspace_page_html()))
  app.get("/app", _ => ctx.serve_platform_bundle())
  app.get(@sdk.health_path(), _ => json_ok(@sdk.HealthResponse::{ ok: true }))
  app.get(@sdk.session_path(), event => {
    json_ok(session_status_response(ctx, event))
  })
  app.post(@sdk.signup_path(), event => {
    let request : @sdk.SignupRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match signup_user(ctx, request) {
      Ok(user) => authenticated_response(ctx, event, user, status=Created)
      Err(message) =>
        api_error_response(UnprocessableEntity, @sdk.ValidationFailed, message)
    }
  })
  app.post(@sdk.login_path(), event => {
    let request : @sdk.LoginRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    match login_user(ctx, request) {
      Ok(user) => authenticated_response(ctx, event, user)
      Err(message) =>
        api_error_response(Unauthorized, @sdk.InvalidCredentials, message)
    }
  })
  app.post(@sdk.logout_path(), event => {
    match event.req.get_cookie(session_cookie_name) {
      Some(cookie) if cookie.value != "" =>
        ctx.store.delete_session(session_token_hash(cookie.value))
      _ => ignore(())
    }
    clear_session_cookie(event.res)
    json_no_content()
  })
  app.get("/auth/github/start", _ => github_authorization_response(ctx))
  app.get("/auth/github/callback", _ => {
    html_response(github_callback_page_html())
  })
  app.post("/api/auth/github/callback", async fn(event) noraise {
    let payload : GitHubCallbackPayload = match decode_json_body(event) {
      Ok(payload) => payload
      Err(response) => return response
    }
    match ctx.complete_github_sign_in(payload) {
      Ok(user) => authenticated_response(ctx, event, user)
      Err(message) =>
        api_error_response(BadRequest, @sdk.ValidationFailed, message)
    }
  })

  app.get(@sdk.projects_path(), event => {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    json_ok(@sdk.ListProjectsResponse::{
      items: ctx.store.list_projects_for_user(user.id),
    })
  })
  app.post(@sdk.projects_path(), event => {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let request : @sdk.CreateProjectRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(response) => return response
    }
    let template = match ctx.resolve_template(request.template_id) {
      Ok(template) => template
      Err(message) =>
        return if message.has_prefix("Unknown template") {
          api_error_response(
            UnprocessableEntity,
            @sdk.ValidationFailed,
            message,
          )
        } else {
          api_error_response(
            ServiceUnavailable,
            @sdk.ServiceUnavailable,
            message,
          )
        }
    }
    let project_id = next_id("project")
    let workspace_path = project_workspace(ctx.root, project_id)
    let project = ctx.store.create_project_for_user(
      user.id,
      project_id,
      request.display_name,
      workspace_path,
      template.id,
      template.version,
    )
    match ctx.materialize_project_template(project) {
      Ok(_) => json_created(@sdk.CreateProjectResponse::{ project, })
      Err(message) => {
        safe_remove_tree(project_root(ctx.root, project_id))
        ignore(ctx.store.delete_project(project_id))
        api_error_response(ServiceUnavailable, @sdk.ServiceUnavailable, message)
      }
    }
  })
  app.delete(@sdk.delete_project_route().path_pattern, event => {
    let user = match require_session_user(ctx, event) {
      Ok(user) => user
      Err(response) => return response
    }
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(response) => return response
    }
    if ctx.store.get_project_detail_for_user(project_id, user.id) is None {
      return api_error_response(NotFound, @sdk.NotFound, "Project not found.")
    }
    match ctx.delete_project(project_id) {
      Ok(_) => json_no_content()
      Err(message) =>
        if message == "Project not found." {
          api_error_response(NotFound, @sdk.NotFound, message)
        } else {
          api_error_response(Conflict, @sdk.Conflict, message)
        }
    }
  })
  app.get(@sdk.project_route().path_pattern, event => {
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
      None => api_error_response(NotFound, @sdk.NotFound, "Project not found.")
    }
  })
  app.get(@sdk.list_messages_route().path_pattern, event => {
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
      None => api_error_response(NotFound, @sdk.NotFound, "Project not found.")
    }
  })
  app.post(@sdk.create_run_route().path_pattern, fn(event) noraise {
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
        @sdk.ValidationFailed,
        "Message content cannot be empty.",
      )
    }
    let run = match
      ctx.store.start_run_for_user(user.id, project_id, request.content) {
      Ok(run) => run
      Err(message) =>
        return api_error_response(Conflict, @sdk.Conflict, message)
    }
    match ctx.spawn_project_turn_worker(project_id, run.run_id) {
      Ok(worker_pid) => {
        ctx.store.set_run_worker_pid(project_id, run.run_id, worker_pid)
        json_created(@sdk.CreateRunResponse::{ run, poll_after_ms: Some(1000) })
      }
      Err(message) => {
        ctx.store.finish_run_failure(
          project_id,
          run.run_id,
          "I couldn't start the background worker for that update.",
          message,
          None,
        )
        let latest_run = ctx.store
          .get_run(project_id, run.run_id)
          .unwrap_or(run)
        json_created(@sdk.CreateRunResponse::{
          run: latest_run,
          poll_after_ms: None,
        })
      }
    }
  })
  app.get(@sdk.get_run_route().path_pattern, event => {
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
      Some(run) => json_ok(run)
      None => api_error_response(NotFound, @sdk.NotFound, "Run not found.")
    }
  })
  app.all(@sdk.preview_route_pattern(), async fn(event) noraise {
    let preview_public_id = match path_param(event, "preview_public_id") {
      Ok(value) => value
      Err(response) => return response
    }
    let remainder = event.params
      .get("_")
      .map(fn(value) { value.to_string() })
      .unwrap_or("")
    let project = match
      ctx.store.get_project_detail_by_preview_public_id(preview_public_id) {
      Some(project) => project
      None => return text_response(NotFound, "Project not found.")
    }
    match project.preview {
      Some(preview) => {
        let target_path = preview_target_path(remainder)
        let manifest = match ctx.load_project_template(project) {
          Ok(manifest) => manifest
          Err(message) => return text_response(ServiceUnavailable, message)
        }
        if template_preview_kind(manifest) == "static" {
          return static_preview_response(
            preview_dist_dir(project.workspace_path),
            target_path,
          )
        }
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

  println("MoonBit Cloud running at http://localhost:\{port}")
  app.serve(port~)
}
