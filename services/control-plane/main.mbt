///|
fn ok_json(value : &ToJson) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(OK).json(value)
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
fn redirect_response(destination : String) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(Found, headers={ "Location": destination }).body("")
}

///|
fn[T : FromJson] decode_json_body(
  event : @mocket.MocketEvent,
) -> Result[T, String] {
  let body : Json = event.req.body() catch {
    _ => return Err("The request body must be valid JSON.")
  }
  Ok(
    @json.from_json(body) catch {
      _ => return Err("The JSON body does not match the expected shape.")
    },
  )
}

///|
fn path_param(
  event : @mocket.MocketEvent,
  name : String,
) -> Result[String, String] {
  match event.params.get(name) {
    Some(value) => Ok(value.to_string())
    None => Err("Missing route parameter: \{name}.")
  }
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
    #|    <style>
    #|      :root {
    #|        color-scheme: light;
    #|        font-family: "Inter", "Helvetica Neue", sans-serif;
    #|        background:
    #|          radial-gradient(circle at top left, rgba(224, 253, 236, 0.92), transparent 34%),
    #|          radial-gradient(circle at bottom right, rgba(223, 234, 255, 0.95), transparent 36%),
    #|          #f7f9fc;
    #|        color: #15263a;
    #|      }
    #|
    #|      * {
    #|        box-sizing: border-box;
    #|      }
    #|
    #|      body {
    #|        margin: 0;
    #|        min-height: 100vh;
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
    "cd '\{self.root}' && moon build apps/web --target js --manifest-path '\{self.root}/moon.work' >/dev/null 2>&1",
  )
  if code != 0 {
    println("warning: failed to build apps/web bundle")
    return
  }
  let source = platform_web_build_output_path(self.root)
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
fn main {
  let root = @env.current_dir().unwrap_or(".")
  let ctx = AppContext::new(root)
  ctx.ensure_platform_web_bundle()

  let app = @mocket.new()

  app.get("/", _ => html_response(workspace_page_html()))
  app.get("/app", _ => ctx.serve_platform_bundle())

  app.get("/api/projects", _ => ok_json(ctx.store.list_projects()))
  app.post("/api/projects", event => {
    let request : @sdk.CreateProjectRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(message) => return text_response(BadRequest, message)
    }
    let project_id = next_id("project")
    let workspace_path = project_workspace(ctx.root, project_id)
    let project = ctx.store.create_project(
      project_id,
      request.display_name,
      workspace_path,
    )
    ctx.create_project_workspace(project)
    ok_json(@sdk.CreateProjectResponse::{ project, })
  })
  app.delete("/api/projects/:id", event => {
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(message) => return text_response(BadRequest, message)
    }
    match ctx.delete_project(project_id) {
      Ok(_) => @mocket.HttpResponse::new(OK).body("")
      Err(message) =>
        if message == "Project not found." {
          text_response(NotFound, message)
        } else {
          text_response(Conflict, message)
        }
    }
  })
  app.get("/api/projects/:id", event => {
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(message) => return text_response(BadRequest, message)
    }
    match ctx.store.get_project_detail(project_id) {
      Some(project) => ok_json(project)
      None => text_response(NotFound, "Project not found.")
    }
  })
  app.get("/api/projects/:id/messages", event => {
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(message) => return text_response(BadRequest, message)
    }
    if ctx.store.get_project_detail(project_id) is None {
      return text_response(NotFound, "Project not found.")
    }
    ok_json(ctx.store.list_messages(project_id))
  })
  app.post("/api/projects/:id/messages", event => {
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(message) => return text_response(BadRequest, message)
    }
    let request : @sdk.SendMessageRequest = match decode_json_body(event) {
      Ok(request) => request
      Err(message) => return text_response(BadRequest, message)
    }
    if request.content == "" {
      return text_response(BadRequest, "Message content cannot be empty.")
    }
    let run = match ctx.store.start_run(project_id, request.content) {
      Ok(run) => run
      Err(message) => return text_response(Conflict, message)
    }
    ctx.run_project_turn(project_id, run.run_id, request.content)
    let latest_run = ctx.store.get_run(project_id, run.run_id).unwrap_or(run)
    ok_json(@sdk.SendMessageResponse::{ run: latest_run })
  })
  app.get("/api/projects/:id/runs/:run_id", event => {
    let project_id = match path_param(event, "id") {
      Ok(value) => value
      Err(message) => return text_response(BadRequest, message)
    }
    let run_id = match path_param(event, "run_id") {
      Ok(value) => value
      Err(message) => return text_response(BadRequest, message)
    }
    match ctx.store.get_run(project_id, run_id) {
      Some(run) => ok_json(run)
      None => text_response(NotFound, "Run not found.")
    }
  })
  app.get("/preview/:project_id/**", event => {
    let project_id = match path_param(event, "project_id") {
      Ok(value) => value
      Err(message) => return text_response(BadRequest, message)
    }
    let remainder = event.params
      .get("_")
      .map(fn(value) { value.to_string() })
      .unwrap_or("")
    let project = match ctx.store.get_project_detail(project_id) {
      Some(project) => project
      None => return text_response(NotFound, "Project not found.")
    }
    match project.preview {
      Some(preview) => {
        let suffix = if remainder == "" { "" } else { remainder }
        let destination = if suffix == "" {
          preview.url
        } else if preview.url.has_suffix("/") {
          preview.url + suffix
        } else {
          preview.url + "/" + suffix
        }
        redirect_response(destination)
      }
      None =>
        text_response(NotFound, "No preview is available for this project yet.")
    }
  })

  println("MoonBit Cloud running at http://localhost:8080")
  app.serve(port=8080)
}
