///|
let workspace : String = "/workspace"

///|
let service_address : String = "0.0.0.0:8080"

///|
let preview_port : Int = 4792

///|
let system_prompt_path : String = "/opt/mooncraft/mooncraft-agent-system.md"

///|
let default_model : String = "gpt-5.4-mini"

///|
struct ExecRequest {
  run_id : String
  prompt : String
} derive(FromJson)

///|
struct InitProject {
  id : String
} derive(FromJson)

///|
struct InitSourceRepository {
  url : String
  default_branch : String
  current_commit_sha : String?
} derive(FromJson)

///|
struct InitSourceCredential {
  kind : String
  username : String
  password : String
} derive(FromJson)

///|
struct InitSecret {
  name : String
  value : String
} derive(FromJson)

///|
struct InitRequest {
  project : InitProject
  source_repository : InitSourceRepository
  source_credential : InitSourceCredential
  secrets : Array[InitSecret]
} derive(FromJson)

///|
struct HealthResponse {
  status : String
  message : String
} derive(ToJson)

///|
struct InitResponse {
  status : String
  current_commit_sha : String?
  message : String
} derive(ToJson)

///|
struct RuntimeRunEvent {
  id : Int
  time : String
  level : String
  message : String
} derive(ToJson)

///|
struct RunResponse {
  run_id : String
  status : String
  message : String
} derive(ToJson)

///|
struct RunEventsResponse {
  events : Array[RuntimeRunEvent]
} derive(ToJson)

///|
struct RuntimeErrorResponse {
  message : String
} derive(ToJson)

///|
struct RuntimeRun {
  run_id : String
  prompt : String
  mut status : String
  mut message : String
  events : Array[RuntimeRunEvent]
  mut next_event_id : Int
}

///|
let runs : Map[String, RuntimeRun] = {}

///|
let active_run_id : Ref[String?] = Ref(None)

///|
let pending_run : Ref[RuntimeRun?] = Ref(None)

///|
let run_available : @cond_var.Cond = @cond_var.Cond::new()

///|
let preview_pid : Ref[Int?] = Ref(None)

///|
let initialized : Ref[Bool] = Ref(false)

///|
let runtime_secrets : Map[String, String] = {}

///|
struct HttpReply {
  code : Int
  reason : String
  content_type : String
  body : String
}

///|
fn current_model() -> String {
  match @env.get_env_var("MODEL") {
    Some(value) if value.trim() != "" => value.trim().to_owned()
    _ => default_model
  }
}

///|
fn current_base_url() -> String? {
  match @env.get_env_var("OPENAI_BASE_URL") {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn runtime_secret_value(name : String) -> String? {
  match runtime_secrets.get(name) {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn current_api_key() -> String? {
  match runtime_secret_value("CODEX_API_KEY") {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ =>
      match runtime_secret_value("OPENROUTER_API_KEY") {
        Some(value) if value.trim() != "" => Some(value.trim().to_owned())
        _ =>
          match runtime_secret_value("OPENAI_API_KEY") {
            Some(value) if value.trim() != "" => Some(value.trim().to_owned())
            _ =>
              match @env.get_env_var("CODEX_API_KEY") {
                Some(value) if value.trim() != "" => Some(value.trim().to_owned())
                _ =>
                  match @env.get_env_var("OPENROUTER_API_KEY") {
                    Some(value) if value.trim() != "" =>
                      Some(value.trim().to_owned())
                    _ =>
                      match @env.get_env_var("OPENAI_API_KEY") {
                        Some(value) if value.trim() != "" =>
                          Some(value.trim().to_owned())
                        _ => None
                      }
                  }
              }
          }
      }
  }
}

///|
fn current_provider_env_key() -> String? {
  match runtime_secret_value("OPENROUTER_API_KEY") {
    Some(value) if value.trim() != "" => Some("OPENROUTER_API_KEY")
    _ =>
      match runtime_secret_value("CODEX_API_KEY") {
        Some(value) if value.trim() != "" => Some("CODEX_API_KEY")
        _ =>
          match runtime_secret_value("OPENAI_API_KEY") {
            Some(value) if value.trim() != "" => Some("OPENAI_API_KEY")
            _ =>
              match @env.get_env_var("OPENROUTER_API_KEY") {
                Some(value) if value.trim() != "" => Some("OPENROUTER_API_KEY")
                _ =>
                  match @env.get_env_var("CODEX_API_KEY") {
                    Some(value) if value.trim() != "" => Some("CODEX_API_KEY")
                    _ =>
                      match @env.get_env_var("OPENAI_API_KEY") {
                        Some(value) if value.trim() != "" =>
                          Some("OPENAI_API_KEY")
                        _ => None
                      }
                  }
              }
          }
      }
  }
}

///|
fn codex_home() -> String {
  match @env.get_env_var("CODEX_HOME") {
    Some(value) if value.trim() != "" => value.trim().to_owned()
    _ =>
      match @env.get_env_var("HOME") {
        Some(value) if value.trim() != "" => "\{value.trim()}/.codex"
        _ => "/home/mooncraft/.codex"
      }
  }
}

///|
fn toml_string(value : String) -> String {
  let escaped = value
    .replace_all(old="\\", new="\\\\")
    .replace_all(old="\"", new="\\\"")
  "\"\{escaped}\""
}

///|
async fn configure_codex_provider() -> Unit {
  if current_base_url() is Some(base_url) {
    if current_provider_env_key() is Some(env_key) {
      let home = codex_home()
      @fs.mkdir(home, permission=0o700, recursive=true) catch { _ => () }
      let config = StringBuilder()
      config <+
        $|model_provider = "mooncraft"
        $|
        $|[model_providers.mooncraft]
        $|name = "MoonCraft Runtime Provider"
        $|base_url = \{toml_string(base_url)}
        $|env_key = \{toml_string(env_key)}
        $|wire_api = "responses"
        $|requires_openai_auth = false
        $|supports_websockets = false
        $|
      @fs.write_file(
        "\{home}/config.toml",
        config.to_string(),
        create=0o600,
        truncate=true,
      )
    }
  }
}

///|
fn new_codex_client() -> @codex.Codex {
  match (current_base_url(), current_api_key()) {
    (Some(base_url), Some(api_key)) =>
      @codex.Codex::new(
        options=@codex.CodexOptions::new(base_url=base_url, api_key=api_key),
      )
    (Some(base_url), None) =>
      @codex.Codex::new(options=@codex.CodexOptions::new(base_url=base_url))
    (None, Some(api_key)) =>
      @codex.Codex::new(options=@codex.CodexOptions::new(api_key=api_key))
    (None, None) => @codex.Codex::new()
  }
}

///|
fn json_reply(code : Int, reason : String, value : &ToJson) -> HttpReply {
  {
    code,
    reason,
    content_type: "application/json; charset=utf-8",
    body: value.to_json().stringify(),
  }
}

///|
fn empty_reply(code : Int, reason : String) -> HttpReply {
  { code, reason, content_type: "text/plain; charset=utf-8", body: "" }
}

///|
fn runtime_error(code : Int, reason : String, message : String) -> HttpReply {
  json_reply(code, reason, RuntimeErrorResponse::{ message, })
}

///|
fn health_reply() -> HttpReply {
  if initialized.val {
    json_reply(
      200,
      "OK",
      HealthResponse::{ status: "ready", message: "Runtime initialized.", },
    )
  } else {
    json_reply(
      200,
      "OK",
      HealthResponse::{
        status: "not_initialized",
        message: "Runtime is waiting for /init.",
      },
    )
  }
}

///|
fn require_initialized() -> HttpReply? {
  if initialized.val {
    None
  } else {
    Some(
      runtime_error(
        409,
        "Conflict",
        "Runtime Service is not initialized. Call /init first.",
      ),
    )
  }
}

///|
async fn send_reply(conn : @http.ServerConnection, reply : HttpReply) -> Unit {
  conn.send_response(reply.code, reply.reason, extra_headers={
    "Content-Type": reply.content_type,
    "Cache-Control": "no-store",
  })
  if reply.body != "" {
    conn.write(reply.body)
  }
  conn.end_response()
}

///|
fn now_string() -> String {
  @env.now().to_string()
}

///|
fn run_response(run : RuntimeRun) -> RunResponse {
  { run_id: run.run_id, status: run.status, message: run.message }
}

///|
fn init_response(current_commit_sha : String?) -> InitResponse {
  {
    status: "ready",
    current_commit_sha,
    message: "Runtime initialized.",
  }
}

///|
fn add_event(run : RuntimeRun, level : String, message : String) -> Unit {
  let text = message.trim().to_owned()
  if text != "" {
    run.next_event_id = run.next_event_id + 1
    run.events.push({
      id: run.next_event_id,
      time: now_string(),
      level,
      message: if text.length() > 4000 {
        text[:4000].to_owned()
      } else {
        text
      },
    })
  }
}

///|
fn finish_run(
  run : RuntimeRun,
  status : String,
  message : String,
  level : String,
) -> Unit {
  if run.status == "running" {
    run.status = status
    run.message = message
    add_event(run, level, message)
    if active_run_id.val == Some(run.run_id) {
      active_run_id.val = None
    }
  }
}

///|
async fn build_prompt(user_prompt : String) -> String {
  let data = @fs.read_file(system_prompt_path) catch { _ => return user_prompt }
  let system_prompt = data.text().trim().to_owned()
  if system_prompt == "" {
    user_prompt
  } else {
    "\{system_prompt}\n\nUser request:\n\n\{user_prompt}"
  }
}

///|
fn codex_event_message(event : @codex.Event) -> (String, String)? {
  match event {
    ThreadStarted(..) => Some(("info", "Builder session started."))
    TurnStarted => Some(("info", "Turn started."))
    TurnCompleted(_) => Some(("info", "Turn completed."))
    TurnFailed(error) => Some(("error", error.message))
    ThreadErrorEvent(message) => Some(("error", message))
    ItemStarted(item) =>
      match item {
        CommandExecutionItem(command~, ..) =>
          Some(("info", "Command started: \{command}"))
        WebSearchItem(query~, ..) => Some(("info", "Web search: \{query}"))
        _ => None
      }
    ItemUpdated(item) =>
      match item {
        CommandExecutionItem(command~, aggregated_output~, ..) if aggregated_output !=
          "" =>
          Some(("info", "Command output: \{command}\n\{aggregated_output}"))
        _ => None
      }
    ItemCompleted(item) =>
      match item {
        AgentMessageItem(text~, ..) => Some(("info", text))
        ReasoningItem(text~, ..) if text != "" => Some(("info", text))
        CommandExecutionItem(
          command~,
          aggregated_output~,
          exit_code~,
          status~,
          ..
        ) => {
          let status_text = status.to_string()
          let code_text = match exit_code {
            Some(code) => " exit=\{code}"
            None => ""
          }
          let output_text = if aggregated_output == "" {
            ""
          } else {
            "\n\{aggregated_output}"
          }
          Some(
            (
              "info",
              "Command \{status_text}:\{code_text} \{command}\{output_text}",
            ),
          )
        }
        FileChangeItem(changes~, ..) => {
          let paths : Array[String] = []
          for change in changes {
            paths.push(change.path)
          }
          if paths.length() == 0 {
            None
          } else {
            let changed = paths.join(", ")
            Some(("info", "Files changed: \{changed}"))
          }
        }
        TodoListItem(items~, ..) => {
          let lines : Array[String] = []
          for item in items {
            let marker = if item.completed { "x" } else { " " }
            lines.push("[\{marker}] \{item.text}")
          }
          if lines.length() == 0 {
            None
          } else {
            Some(("info", lines.join("\n")))
          }
        }
        ErrorItem(message~, ..) => Some(("error", message))
        _ => None
      }
  }
}

///|
async fn run_codex(run : RuntimeRun, prompt : String) -> Unit noraise {
  try {
    configure_codex_provider()
    let full_prompt = build_prompt(prompt)
    let codex = new_codex_client()
    let thread = codex.start_thread(
      options=@codex.ThreadOptions::new(
        model=current_model(),
        sandbox_mode=DangerFullAccess,
        working_directory=workspace,
        skip_git_repo_check=true,
        network_access_enabled=true,
        approval_policy=Never,
      ),
    )
    let mut final_response = ""
    @async.with_task_group(group => {
      let streamed = thread.run_streamed(full_prompt, group)
      while streamed.events.next() is Some(event) {
        if event is ItemCompleted(AgentMessageItem(text~, ..)) {
          final_response = text
        }
        if codex_event_message(event) is Some((level, message)) {
          add_event(run, level, message)
        }
      }
    })
    let summary = if final_response.trim() == "" {
      "The app is updated and the preview is ready."
    } else {
      final_response.trim().to_owned()
    }
    finish_run(run, "succeeded", summary, "info")
  } catch {
    error =>
      finish_run(run, "failed", "Builder session failed: \{error}", "error")
  }
}

///|
fn parse_exec_request(body : String) -> Result[ExecRequest, String] {
  let json = @json.parse(body) catch {
    _ => return Err("Invalid JSON request body.")
  }
  let request : ExecRequest = @json.from_json(json) catch {
    _ => return Err("run_id and prompt are required.")
  }
  if request.run_id.trim() == "" || request.prompt.trim() == "" {
    Err("run_id and prompt are required.")
  } else {
    Ok({ run_id: request.run_id.trim().to_owned(), prompt: request.prompt })
  }
}

///|
fn parse_init_request(body : String) -> Result[InitRequest, String] {
  let json = @json.parse(body) catch {
    _ => return Err("Invalid JSON request body.")
  }
  let request : InitRequest = @json.from_json(json) catch {
    _ => return Err("Invalid init request.")
  }
  if request.project.id.trim() == "" {
    return Err("project.id is required.")
  }
  if request.source_repository.url.trim() == "" {
    return Err("source_repository.url is required.")
  }
  if request.source_repository.default_branch.trim() == "" {
    return Err("source_repository.default_branch is required.")
  }
  if request.source_credential.kind != "git_https_token" ||
    request.source_credential.username.trim() == "" ||
    request.source_credential.password.trim() == "" {
    return Err("source_credential must be a git_https_token credential.")
  }
  for secret in request.secrets {
    if secret.name.trim() == "" {
      return Err("secret.name is required.")
    }
  }
  Ok(request)
}

///|
fn handle_init(body : String) -> HttpReply {
  if active_run_id.val is Some(_) {
    return runtime_error(
      409,
      "Conflict",
      "Runtime Service cannot be initialized while a run is active.",
    )
  }
  let request = match parse_init_request(body) {
    Ok(request) => request
    Err(message) => return runtime_error(400, "BadRequest", message)
  }
  ignore(request.source_repository.url)
  ignore(request.source_repository.default_branch)
  ignore(request.source_credential.kind)
  ignore(request.source_credential.username)
  ignore(request.source_credential.password)
  runtime_secrets.clear()
  for secret in request.secrets {
    runtime_secrets[secret.name.trim().to_owned()] = secret.value
  }
  initialized.val = true
  json_reply(
    200,
    "OK",
    init_response(request.source_repository.current_commit_sha),
  )
}

///|
fn handle_exec(body : String) -> HttpReply {
  if require_initialized() is Some(reply) {
    return reply
  }
  let request = match parse_exec_request(body) {
    Ok(request) => request
    Err(message) => return runtime_error(400, "BadRequest", message)
  }
  if runs.get(request.run_id) is Some(existing) {
    if existing.prompt != request.prompt {
      return runtime_error(
        409, "Conflict", "Run id already exists with a different prompt.",
      )
    }
    return json_reply(
      if existing.status == "running" {
        202
      } else {
        200
      },
      "OK",
      run_response(existing),
    )
  }
  if active_run_id.val is Some(_) {
    return runtime_error(409, "Conflict", "Another run is already active.")
  }
  let run = {
    run_id: request.run_id,
    prompt: request.prompt,
    status: "running",
    message: "Builder session is running.",
    events: [],
    next_event_id: 0,
  }
  runs[run.run_id] = run
  active_run_id.val = Some(run.run_id)
  add_event(run, "info", "Builder session accepted.")
  pending_run.val = Some(run)
  run_available.signal()
  json_reply(202, "Accepted", run_response(run))
}

///|
async fn run_worker() -> Unit {
  for ;; {
    while pending_run.val is None {
      run_available.wait()
    }
    if pending_run.val is Some(run) {
      pending_run.val = None
      run_codex(run, run.prompt)
    }
  }
}

///|
fn handle_run(run_id : String) -> HttpReply {
  if require_initialized() is Some(reply) {
    return reply
  }
  match runs.get(run_id) {
    Some(run) => json_reply(200, "OK", run_response(run))
    None => runtime_error(404, "NotFound", "Run not found.")
  }
}

///|
fn after_cursor(url : String) -> Result[Int, String] {
  let marker = "after="
  match url.find(marker) {
    Some(index) => {
      let start = index + marker.length()
      let end = match url[start:].find("&") {
        Some(offset) => start + offset
        None => url.length()
      }
      let value = url[start:end]
      let parsed = @string.parse_int(value) catch {
        _ => return Err("after must be a non-negative integer.")
      }
      if parsed < 0 {
        Err("after must be a non-negative integer.")
      } else {
        Ok(parsed)
      }
    }
    None => Ok(0)
  }
}

///|
fn handle_run_events(run_id : String, path : String) -> HttpReply {
  if require_initialized() is Some(reply) {
    return reply
  }
  let run = match runs.get(run_id) {
    Some(run) => run
    None => return runtime_error(404, "NotFound", "Run not found.")
  }
  let after = match after_cursor(path) {
    Ok(value) => value
    Err(message) => return runtime_error(400, "BadRequest", message)
  }
  let events : Array[RuntimeRunEvent] = []
  for item in run.events {
    if item.id > after {
      events.push(item)
    }
  }
  json_reply(200, "OK", RunEventsResponse::{ events, })
}

///|
async fn preview_ready_path(path : String) -> Bool noraise {
  let result = try @http.get("http://127.0.0.1:\{preview_port}\{path}") catch {
    _ => return false
  } noraise {
    result => result
  }
  let (response, body) = result
  ignore(body)
  response.code >= 200 && response.code < 300
}

///|
async fn preview_ready() -> Bool noraise {
  if preview_ready_path("/api/health") {
    true
  } else {
    preview_ready_path("/")
  }
}

///|
async fn wait_preview_ready() -> Bool noraise {
  for _ in 0..<30 {
    if preview_ready() {
      return true
    }
    @async.sleep(1000) catch {
      _ => return false
    }
  }
  false
}

///|
async fn ensure_preview() -> Result[Unit, String] noraise {
  if preview_ready() {
    return Ok(())
  }
  let script = "\{workspace}/mooncraft-preview.sh"
  if !(@fs.exists(script) catch { _ => false }) {
    return Err("Preview is not ready: mooncraft-preview.sh was not found.")
  }
  if preview_pid.val is Some(pid) {
    ignore(@process.run("kill", ["-TERM", pid.to_string()]) catch { _ => -1 })
    preview_pid.val = None
  }
  @fs.chmod(script, 0o755) catch {
    error => return Err("Preview script could not be made executable: \{error}")
  }
  let pid = @process.spawn_orphan(
    script,
    [preview_port.to_string()],
    extra_env={ "PORT": preview_port.to_string() },
    cwd=workspace,
  ) catch {
    error => return Err("Preview script could not be started: \{error}")
  }
  preview_pid.val = Some(pid)
  if wait_preview_ready() {
    Ok(())
  } else {
    Err("Preview is not ready: preview process did not become reachable.")
  }
}

///|
async fn handle_preview() -> HttpReply noraise {
  if require_initialized() is Some(reply) {
    return reply
  }
  match ensure_preview() {
    Ok(_) => empty_reply(200, "OK")
    Err(message) => runtime_error(503, "ServiceUnavailable", message)
  }
}

///|
fn route_path(path : String) -> String {
  path.split("?").to_array()[0].to_owned()
}

///|
fn run_status_route(path : String) -> String? {
  let segments = path.split("/").to_array()
  if segments.length() == 3 &&
    segments[0] == "" &&
    segments[1] == "runs" &&
    segments[2] != "" {
    Some(segments[2].to_owned())
  } else {
    None
  }
}

///|
fn run_events_route(path : String) -> String? {
  let segments = path.split("/").to_array()
  if segments.length() == 4 &&
    segments[0] == "" &&
    segments[1] == "runs" &&
    segments[2] != "" &&
    segments[3] == "events" {
    Some(segments[2].to_owned())
  } else {
    None
  }
}

///|
async fn handle_request(
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit noraise {
  let path = route_path(request.path)
  let reply = match (request.meth, path) {
    (Get, "/health") => health_reply()
    (Post, "/init") => {
      let raw_body = body.read_all().text() catch { _ => "" }
      handle_init(raw_body)
    }
    (Post, "/exec") => {
      let raw_body = body.read_all().text() catch { _ => "" }
      handle_exec(raw_body)
    }
    (Get, "/preview") => handle_preview()
    (Get, _) =>
      match run_status_route(path) {
        Some(run_id) => handle_run(run_id)
        None =>
          match run_events_route(path) {
            Some(run_id) => handle_run_events(run_id, request.path)
            None =>
              runtime_error(404, "NotFound", "Runtime endpoint not found.")
          }
      }
    _ => runtime_error(404, "NotFound", "Runtime endpoint not found.")
  }
  send_reply(conn, reply) catch {
    _ => ()
  }
}

///|
async fn main {
  @fs.mkdir(workspace, permission=0o755, recursive=true) catch {
    _ => ()
  }
  let server = @http.Server::new(
    @socket.Addr::parse(service_address),
    reuse_addr=true,
  ) catch {
    err => {
      println("failed to start runtime service: \{err}")
      return
    }
  }
  @async.with_task_group(group => {
    group.spawn_bg(() => run_worker())
    server.run_forever(
      (request, body, conn) => handle_request(request, body, conn),
      allow_failure=true,
    )
  })
}
