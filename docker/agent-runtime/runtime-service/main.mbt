///|
let workspace : String = "/workspace"

///|
let service_address : String = "0.0.0.0:8080"

///|
let preview_port : Int = 4792

///|
let preview_log_path : String = "/artifacts/preview.log"

///|
let system_prompt_path : String = "/opt/mooncraft/mooncraft-agent-system.md"

///|
let default_model : String = "gpt-5.4-mini"

///|
struct RuntimeSourceState {
  repository : @runtime_protocol.RuntimeServiceSourceRepository
  credential : @runtime_protocol.RuntimeServiceSourceCredential
  authenticated_url : String
}

///|
struct RuntimeRun {
  run_id : String
  prompt : String
  mut status : String
  mut message : String
  mut ready_commit_sha : String?
  events : Array[@runtime_protocol.RuntimeServiceEvent]
  mut next_event_id : Int
}

///|
priv enum RuntimeAuth {
  CodexAuthJson(String)
  CodexApiKey(String)
  OpenAIApiKey(String)
  OpenRouterApiKey(String)
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
let preview_process : Ref[@process.Process?] = Ref(None)

///|
let initialized : Ref[Bool] = Ref(false)

///|
let runtime_secrets : Map[String, String] = {}

///|
let runtime_source : Ref[RuntimeSourceState?] = Ref(None)

///|
struct HttpReply {
  code : Int
  reason : String
  content_type : String
  body : Bytes
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
fn official_auth_secret_names() -> Array[String] {
  ["CODEX_AUTH_JSON", "CODEX_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY"]
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
fn resolved_runtime_auth() -> Result[RuntimeAuth, String] {
  let found_names : Array[String] = []
  let found_values : Array[String] = []
  for name in official_auth_secret_names() {
    if runtime_secret_value(name) is Some(value) {
      found_names.push(name)
      found_values.push(value)
    }
  }
  if found_names.length() == 0 {
    return Err(
      "Official Codex Runtime requires exactly one authentication secret: CODEX_AUTH_JSON, CODEX_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY.",
    )
  }
  if found_names.length() > 1 {
    return Err(
      "Official Codex Runtime received multiple authentication secrets. Configure exactly one of CODEX_AUTH_JSON, CODEX_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY.",
    )
  }
  let name = found_names[0]
  let value = found_values[0]
  match (name, current_base_url()) {
    ("CODEX_AUTH_JSON", Some(_)) =>
      Err("CODEX_AUTH_JSON cannot be combined with env.OPENAI_BASE_URL.")
    ("CODEX_AUTH_JSON", None) => Ok(CodexAuthJson(value))
    ("CODEX_API_KEY", Some(_)) =>
      Err(
        "CODEX_API_KEY cannot be combined with env.OPENAI_BASE_URL. Use OPENAI_API_KEY with OPENAI_BASE_URL for OpenAI-compatible providers.",
      )
    ("CODEX_API_KEY", None) => Ok(CodexApiKey(value))
    ("OPENAI_API_KEY", _) => Ok(OpenAIApiKey(value))
    ("OPENROUTER_API_KEY", Some(_)) =>
      Err(
        "OPENROUTER_API_KEY always uses https://openrouter.ai/api/v1; remove env.OPENAI_BASE_URL.",
      )
    ("OPENROUTER_API_KEY", None) => Ok(OpenRouterApiKey(value))
    _ => Err("Unsupported authentication secret: \{name}.")
  }
}

///|
async fn remove_file_if_exists(path : String) -> Result[Unit, String] noraise {
  let exists = @fs.exists(path) catch {
    err => return Err("file could not be checked: \{err}")
  }
  if exists {
    @fs.remove(path) catch {
      err => return Err("file could not be removed: \{err}")
    }
  }
  Ok(())
}

///|
async fn write_codex_auth_json(
  auth_json : String,
) -> Result[Unit, String] noraise {
  ignore(
    @json.parse(auth_json) catch {
      _ => return Err("CODEX_AUTH_JSON is not valid JSON.")
    },
  )
  let home = codex_home()
  if ensure_directory(home, "Codex home", permission=0o700) is Err(message) {
    return Err(message)
  }
  if remove_file_if_exists("\{home}/config.toml") is Err(message) {
    return Err("Codex provider config could not be removed: \{message}")
  }
  @fs.write_file("\{home}/auth.json", auth_json, create=0o600, truncate=true) catch {
    err => return Err("Codex auth.json could not be written: \{err}")
  }
  Ok(())
}

///|
async fn write_codex_provider_config(
  base_url : String,
) -> Result[Unit, String] noraise {
  let home = codex_home()
  if ensure_directory(home, "Codex home", permission=0o700) is Err(message) {
    return Err(message)
  }
  if remove_file_if_exists("\{home}/auth.json") is Err(message) {
    return Err("Codex auth.json could not be removed: \{message}")
  }
  let config = StringBuilder()
  config <+
    $|model_provider = "mooncraft"
    $|
    $|[model_providers.mooncraft]
    $|name = "MoonCraft Runtime Provider"
    $|base_url = \{toml_string(base_url)}
    $|env_key = "CODEX_API_KEY"
    $|wire_api = "responses"
    $|requires_openai_auth = false
    $|supports_websockets = false
    $|
  @fs.write_file(
    "\{home}/config.toml",
    config.to_string(),
    create=0o600,
    truncate=true,
  ) catch {
    err => return Err("Codex config could not be written: \{err}")
  }
  Ok(())
}

///|
async fn configure_codex_credentials() -> Result[Unit, String] noraise {
  match resolved_runtime_auth() {
    Ok(CodexAuthJson(auth_json)) => write_codex_auth_json(auth_json)
    Ok(CodexApiKey(_)) | Ok(OpenAIApiKey(_)) => {
      let home = codex_home()
      if ensure_directory(home, "Codex home", permission=0o700) is Err(message) {
        return Err(message)
      }
      if remove_file_if_exists("\{home}/auth.json") is Err(message) {
        return Err("Codex auth.json could not be removed: \{message}")
      }
      if remove_file_if_exists("\{home}/config.toml") is Err(message) {
        return Err("Codex provider config could not be removed: \{message}")
      }
      if current_base_url() is Some(base_url) {
        write_codex_provider_config(base_url)
      } else {
        Ok(())
      }
    }
    Ok(OpenRouterApiKey(_)) =>
      write_codex_provider_config("https://openrouter.ai/api/v1")
    Err(message) => Err(message)
  }
}

///|
fn codex_process_env() -> Map[String, String] {
  let out = @env.get_env_vars()
  for
    name in [
      "CODEX_AUTH_JSON", "CODEX_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY",
      "OPENAI_BASE_URL",
    ] {
    out.remove(name)
  }
  out
}

///|
fn new_codex_client() -> Result[@codex.Codex, String] {
  let env = codex_process_env()
  match resolved_runtime_auth() {
    Ok(CodexAuthJson(_)) =>
      Ok(@codex.Codex::new(options=@codex.CodexOptions::new(env~)))
    Ok(CodexApiKey(api_key)) =>
      Ok(@codex.Codex::new(options=@codex.CodexOptions::new(api_key~, env~)))
    Ok(OpenAIApiKey(api_key)) =>
      match current_base_url() {
        Some(base_url) =>
          Ok(
            @codex.Codex::new(
              options=@codex.CodexOptions::new(base_url~, api_key~, env~),
            ),
          )
        None =>
          Ok(
            @codex.Codex::new(options=@codex.CodexOptions::new(api_key~, env~)),
          )
      }
    Ok(OpenRouterApiKey(api_key)) =>
      Ok(
        @codex.Codex::new(
          options=@codex.CodexOptions::new(
            base_url="https://openrouter.ai/api/v1",
            api_key~,
            env~,
          ),
        ),
      )
    Err(message) => Err(message)
  }
}

///|
fn json_reply(code : Int, reason : String, value : &ToJson) -> HttpReply {
  {
    code,
    reason,
    content_type: "application/json; charset=utf-8",
    body: string_body(value.to_json().stringify()),
  }
}

///|
fn runtime_error(code : Int, reason : String, message : String) -> HttpReply {
  json_reply(code, reason, @runtime_protocol.RuntimeServiceError::{ message, })
}

///|
fn string_body(text : String) -> Bytes {
  @utf8.encode(text)
}

///|
fn hex_digit(value : Int) -> Char {
  "0123456789ABCDEF"[value & 0xf].unsafe_to_char()
}

///|
fn url_component_encode(text : String) -> String {
  let out = StringBuilder()
  for byte in @utf8.encode(text) {
    let code = byte.to_int()
    if (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      code == 45 ||
      code == 46 ||
      code == 95 ||
      code == 126 {
      out.write_char(code.unsafe_to_char())
    } else {
      out.write_char('%')
      out.write_char(hex_digit(code >> 4))
      out.write_char(hex_digit(code))
    }
  }
  out.to_string()
}

///|
fn source_authenticated_url(
  request : @runtime_protocol.RuntimeServiceInitRequest,
) -> Result[String, String] {
  let url = request.source_repository.url.trim().to_owned()
  if !url.has_prefix("https://") {
    return Err("source_repository.url must be an HTTPS git URL.")
  }
  let username = url_component_encode(request.source_credential.username)
  let password = url_component_encode(request.source_credential.password)
  Ok("https://\{username}:\{password}@\{url["https://".length():]}")
}

///|
fn redact_secret(text : String, secret : String) -> String {
  if secret == "" {
    text
  } else {
    text.replace_all(old=secret, new="<redacted>")
  }
}

///|
fn health_reply() -> HttpReply {
  if initialized.val {
    if active_run_id.val is Some(_) {
      return json_reply(200, "OK", @runtime_protocol.RuntimeServiceHealthResponse::{
        status: @runtime_protocol.runtime_service_health_status_running(),
        message: "Runtime is running.",
      })
    }
    json_reply(200, "OK", @runtime_protocol.RuntimeServiceHealthResponse::{
      status: @runtime_protocol.runtime_service_health_status_ready(),
      message: "Runtime initialized.",
    })
  } else {
    json_reply(200, "OK", @runtime_protocol.RuntimeServiceHealthResponse::{
      status: @runtime_protocol.runtime_service_health_status_not_initialized(),
      message: "Runtime is waiting for /init.",
    })
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
        @runtime_protocol.runtime_service_not_initialized_message(),
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
  if reply.body.length() > 0 {
    conn.write(reply.body)
  }
  conn.end_response()
}

///|
fn now_string() -> String {
  @env.now().to_string()
}

///|
fn run_response(run : RuntimeRun) -> @runtime_protocol.RuntimeServiceRun {
  {
    run_id: run.run_id,
    status: run.status,
    message: run.message,
    ready_commit_sha: run.ready_commit_sha,
  }
}

///|
fn init_response(
  current_commit_sha : String?,
) -> @runtime_protocol.RuntimeServiceInitResponse {
  {
    status: @runtime_protocol.runtime_service_health_status_ready(),
    current_commit_sha,
    message: Some("Runtime initialized."),
  }
}

///|
fn git_env() -> Map[String, String] {
  { "GIT_TERMINAL_PROMPT": "0" }
}

///|
async fn run_git(
  args : Array[String],
  cwd? : String = workspace,
  redacted? : String = "",
) -> Result[String, String] noraise {
  let (status, output) = @process.collect_output_merged(
    "git",
    args,
    cwd~,
    extra_env=git_env(),
  ) catch {
    err => return Err("git command failed to start: \{err}")
  }
  let text = output.text() catch { _ => "" }
  if status == 0 {
    Ok(text.trim().to_owned())
  } else {
    Err(redact_secret(text.trim().to_owned(), redacted))
  }
}

///|
async fn clean_workspace_contents() -> Result[Unit, String] noraise {
  if ensure_directory(workspace, "workspace") is Err(message) {
    return Err(message)
  }
  let (status, output) = @process.collect_output_merged(
    "sh",
    ["-c", "find . -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +"],
    cwd=workspace,
  ) catch {
    err => return Err("workspace cleanup could not start: \{err}")
  }
  if status == 0 {
    Ok(())
  } else {
    Err("workspace cleanup failed: \{output.text() catch { _ => "" }}")
  }
}

///|
async fn ensure_directory(
  path : String,
  label : String,
  permission? : Int = 0o755,
) -> Result[Unit, String] noraise {
  let exists = @fs.exists(path) catch {
    err => return Err("\{label} could not be checked: \{err}")
  }
  if exists {
    let kind = @fs.kind(path, follow_symlink=false) catch {
      err => return Err("\{label} kind could not be checked: \{err}")
    }
    if kind is Directory {
      return Ok(())
    }
    return Err("\{label} exists but is not a directory: \{path}")
  }
  @fs.mkdir(path, permission~, recursive=true) catch {
    err => return Err("\{label} could not be created: \{err}")
  }
  Ok(())
}

///|
async fn git_remote_branch_exists(branch : String) -> Bool noraise {
  match run_git(["ls-remote", "--heads", "origin", branch]) {
    Ok(output) => output.trim() != ""
    Err(_) => false
  }
}

///|
async fn git_head_commit() -> String? noraise {
  match run_git(["rev-parse", "HEAD"]) {
    Ok(commit) if commit.trim() != "" => Some(commit.trim().to_owned())
    _ => None
  }
}

///|
async fn checkout_source_branch(
  repository : @runtime_protocol.RuntimeServiceSourceRepository,
) -> Result[Unit, String] noraise {
  let branch = repository.default_branch.trim().to_owned()
  match repository.current_commit_sha {
    Some(commit) if commit.trim() != "" =>
      match run_git(["checkout", "-B", branch, commit.trim().to_owned()]) {
        Ok(_) => Ok(())
        Err(message) =>
          Err("source commit could not be checked out: \{message}")
      }
    _ =>
      if git_remote_branch_exists(branch) {
        match run_git(["fetch", "origin", branch]) {
          Ok(_) => ()
          Err(message) =>
            return Err("source branch could not be fetched: \{message}")
        }
        match run_git(["checkout", "-B", branch, "origin/\{branch}"]) {
          Ok(_) => Ok(())
          Err(message) =>
            Err("source branch could not be checked out: \{message}")
        }
      } else {
        match run_git(["checkout", "--orphan", branch]) {
          Ok(_) => Ok(())
          Err(_) =>
            match run_git(["checkout", "-B", branch]) {
              Ok(_) => Ok(())
              Err(message) =>
                Err("empty source branch could not be created: \{message}")
            }
        }
      }
  }
}

///|
async fn configure_source_repository(
  state : RuntimeSourceState,
) -> Result[String?, String] noraise {
  let redacted = state.credential.password
  let has_git = @fs.exists("\{workspace}/.git") catch { _ => false }
  if has_git {
    match
      run_git(
        ["remote", "set-url", "origin", state.authenticated_url],
        redacted~,
      ) {
      Ok(_) => ()
      Err(message) =>
        return Err("source repository remote could not be set: \{message}")
    }
    match run_git(["fetch", "origin"], redacted~) {
      Ok(_) => ()
      Err(message) =>
        return Err("source repository could not be fetched: \{message}")
    }
  } else {
    match clean_workspace_contents() {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    match
      run_git(["clone", state.authenticated_url, workspace], cwd="/", redacted~) {
      Ok(_) => ()
      Err(message) =>
        return Err("source repository could not be cloned: \{message}")
    }
  }
  match checkout_source_branch(state.repository) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  ignore(run_git(["config", "user.name", "MoonCraft"], redacted~))
  ignore(
    run_git(["config", "user.email", "mooncraft@moonbitlang.com"], redacted~),
  )
  Ok(git_head_commit())
}

///|
async fn commit_and_push_source(
  run_id : String,
) -> Result[String, String] noraise {
  let state = match runtime_source.val {
    Some(state) => state
    None => return Err("Runtime source repository is not initialized.")
  }
  let branch = state.repository.default_branch.trim().to_owned()
  let redacted = state.credential.password
  match run_git(["add", "-A"], redacted~) {
    Ok(_) => ()
    Err(message) => return Err("source changes could not be staged: \{message}")
  }
  let changed = match run_git(["status", "--porcelain"], redacted~) {
    Ok(output) => output.trim() != ""
    Err(message) => return Err("source status could not be read: \{message}")
  }
  if changed {
    match run_git(["commit", "-m", "MoonCraft run \{run_id}"], redacted~) {
      Ok(_) => ()
      Err(message) =>
        return Err("source changes could not be committed: \{message}")
    }
  }
  if git_remote_branch_exists(branch) {
    match run_git(["pull", "--rebase", "origin", branch], redacted~) {
      Ok(_) => ()
      Err(message) =>
        return Err(
          "source changes could not be rebased before push: \{message}",
        )
    }
  }
  match run_git(["push", "origin", "HEAD:\{branch}"], redacted~) {
    Ok(_) => ()
    Err(message) => return Err("source changes could not be pushed: \{message}")
  }
  match git_head_commit() {
    Some(commit) => Ok(commit)
    None => Err("ready source commit could not be determined.")
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
  ready_commit_sha? : String? = None,
) -> Unit {
  if run.status == @runtime_protocol.runtime_service_run_status_running() {
    run.status = status
    run.message = message
    run.ready_commit_sha = ready_commit_sha
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
    ThreadStarted(..) =>
      Some(
        (
          @runtime_protocol.runtime_service_event_level_info(),
          "Builder session started.",
        ),
      )
    TurnStarted =>
      Some(
        (
          @runtime_protocol.runtime_service_event_level_info(),
          "Planning the change.",
        ),
      )
    TurnCompleted(_) =>
      Some(
        (
          @runtime_protocol.runtime_service_event_level_info(),
          "Builder session ended.",
        ),
      )
    TurnFailed(_) =>
      Some(
        (
          @runtime_protocol.runtime_service_event_level_error(),
          "Builder session failed.",
        ),
      )
    ThreadErrorEvent(_) =>
      Some(
        (
          @runtime_protocol.runtime_service_event_level_error(),
          "Builder session failed.",
        ),
      )
    ItemStarted(item) =>
      match item {
        CommandExecutionItem(..) =>
          Some(
            (@runtime_protocol.runtime_service_event_level_info(), "Working."),
          )
        WebSearchItem(..) =>
          Some(
            (
              @runtime_protocol.runtime_service_event_level_info(),
              "Searching the web.",
            ),
          )
        _ => None
      }
    ItemUpdated(_) => None
    ItemCompleted(item) =>
      match item {
        AgentMessageItem(..) => None
        ReasoningItem(..) => None
        CommandExecutionItem(exit_code~, ..) =>
          match exit_code {
            Some(code) if code != 0 =>
              Some(
                (
                  @runtime_protocol.runtime_service_event_level_error(),
                  "A command failed.",
                ),
              )
            _ => None
          }
        FileChangeItem(..) =>
          Some(
            (
              @runtime_protocol.runtime_service_event_level_info(),
              "Updating files.",
            ),
          )
        TodoListItem(..) => None
        ErrorItem(..) =>
          Some(
            (
              @runtime_protocol.runtime_service_event_level_error(),
              "Builder session failed.",
            ),
          )
        _ => None
      }
  }
}

///|
async fn run_codex(run : RuntimeRun, prompt : String) -> Unit noraise {
  try {
    let full_prompt = build_prompt(prompt)
    let codex = match new_codex_client() {
      Ok(codex) => codex
      Err(message) => {
        finish_run(
          run,
          @runtime_protocol.runtime_service_run_status_failed(),
          "Builder session failed: \{message}",
          @runtime_protocol.runtime_service_event_level_error(),
          ready_commit_sha=None,
        )
        return
      }
    }
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
    add_event(
      run,
      @runtime_protocol.runtime_service_event_level_info(),
      "Committing and pushing source changes.",
    )
    let ready_commit_sha = match commit_and_push_source(run.run_id) {
      Ok(commit) => commit
      Err(message) => {
        finish_run(
          run,
          @runtime_protocol.runtime_service_run_status_failed(),
          "Builder finished, but source changes could not be published: \{message}",
          @runtime_protocol.runtime_service_event_level_error(),
          ready_commit_sha=None,
        )
        return
      }
    }
    finish_run(
      run,
      @runtime_protocol.runtime_service_run_status_succeeded(),
      summary,
      @runtime_protocol.runtime_service_event_level_info(),
      ready_commit_sha=Some(ready_commit_sha),
    )
  } catch {
    _ =>
      finish_run(
        run,
        @runtime_protocol.runtime_service_run_status_failed(),
        "Builder session failed.",
        @runtime_protocol.runtime_service_event_level_error(),
        ready_commit_sha=None,
      )
  }
}

///|
fn parse_exec_request(
  body : String,
) -> Result[@runtime_protocol.RuntimeServiceExecRequest, String] {
  @runtime_protocol.runtime_service_exec_request_from_json_text(body)
}

///|
fn parse_init_request(
  body : String,
) -> Result[@runtime_protocol.RuntimeServiceInitRequest, String] {
  @runtime_protocol.runtime_service_init_request_from_json_text(body)
}

///|
async fn handle_init(body : String) -> HttpReply noraise {
  if active_run_id.val is Some(_) {
    return runtime_error(
      409, "Conflict", "Runtime Service cannot be initialized while a run is active.",
    )
  }
  let request = match parse_init_request(body) {
    Ok(request) => request
    Err(message) => return runtime_error(400, "BadRequest", message)
  }
  let authenticated_url = match source_authenticated_url(request) {
    Ok(url) => url
    Err(message) => return runtime_error(400, "BadRequest", message)
  }
  runtime_secrets.clear()
  for secret in request.secrets {
    runtime_secrets[secret.name.trim().to_owned()] = secret.value
  }
  match configure_codex_credentials() {
    Ok(_) => ()
    Err(message) => return runtime_error(400, "BadRequest", message)
  }
  let state : RuntimeSourceState = {
    repository: request.source_repository,
    credential: request.source_credential,
    authenticated_url,
  }
  let current_commit = match configure_source_repository(state) {
    Ok(commit) => commit
    Err(message) => return runtime_error(503, "ServiceUnavailable", message)
  }
  runtime_source.val = Some(state)
  initialized.val = true
  json_reply(200, "OK", init_response(current_commit))
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
      if existing.status ==
        @runtime_protocol.runtime_service_run_status_running() {
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
    status: @runtime_protocol.runtime_service_run_status_running(),
    message: "Builder session is running.",
    ready_commit_sha: None,
    events: [],
    next_event_id: 0,
  }
  runs[run.run_id] = run
  active_run_id.val = Some(run.run_id)
  add_event(
    run,
    @runtime_protocol.runtime_service_event_level_info(),
    "Builder session accepted.",
  )
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
  let events : Array[@runtime_protocol.RuntimeServiceEvent] = []
  for item in run.events {
    if item.id > after {
      events.push(item)
    }
  }
  json_reply(200, "OK", @runtime_protocol.RuntimeServiceEventsResponse::{
    events,
  })
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
async fn preview_log_tail(limit : Int) -> String noraise {
  let exists = @fs.exists(preview_log_path) catch { _ => false }
  if !exists {
    return ""
  }
  let data = @fs.read_file(preview_log_path) catch { _ => return "" }
  let text = data.text() catch { _ => return "" }
  let trimmed = text.trim(chars="\n\r ").to_owned()
  if trimmed.length() <= limit {
    trimmed
  } else {
    trimmed[trimmed.length() - limit:].to_owned()
  }
}

///|
async fn preview_failure_message(message : String) -> String noraise {
  let log = preview_log_tail(1200)
  if log == "" {
    message
  } else {
    "\{message}\n\nPreview log:\n\{log}"
  }
}

///|
async fn stop_preview_process() -> Unit noraise {
  match preview_process.val {
    Some(process) => {
      process.cancel()
      let _ = try process.wait() catch {
        _ => -1
      } noraise {
        code => code
      }
      preview_process.val = None
      preview_pid.val = None
    }
    None =>
      if preview_pid.val is Some(pid) {
        ignore(
          @process.run("kill", ["-TERM", pid.to_string()]) catch {
            _ => -1
          },
        )
        preview_pid.val = None
      }
  }
}

///|
async fn[X] start_preview_process(
  group : @async.TaskGroup[X],
  script : String,
) -> Result[@process.Process, String] noraise {
  if ensure_directory("/artifacts", "artifacts") is Err(message) {
    return Err(message)
  }
  let stdout = try
    @process.redirect_to_file(preview_log_path, create=0o644, truncate=true)
  catch {
    err => return Err("Preview log could not be opened: \{err}")
  } noraise {
    output => output
  }
  let stderr = try
    @process.redirect_to_file(preview_log_path, append=true, create=0o644)
  catch {
    err => return Err("Preview log could not be opened: \{err}")
  } noraise {
    output => output
  }
  let process = try
    @process.spawn(
      group,
      "mooncraft-preview-run",
      [script, preview_port.to_string()],
      extra_env={ "PORT": preview_port.to_string() },
      stdout~,
      stderr~,
      cwd=workspace,
      no_wait=true,
    )
  catch {
    error => return Err("Preview script could not be started: \{error}")
  } noraise {
    process => process
  }
  Ok(process)
}

///|
async fn wait_preview_ready(
  process : @process.Process,
) -> Result[Unit, String] noraise {
  for _ in 0..<30 {
    if preview_ready() {
      return Ok(())
    }
    let status = try process.try_wait() catch {
      _ => None
    } noraise {
      status => status
    }
    match status {
      Some(code) =>
        return Err(
          preview_failure_message(
            "Preview is not ready: preview process exited with status \{code}.",
          ),
        )
      None => ()
    }
    @async.sleep(1000) catch {
      _ => return Err("Preview readiness wait was cancelled.")
    }
  }
  Err(
    preview_failure_message(
      "Preview is not ready: preview process did not become reachable.",
    ),
  )
}

///|
async fn[X] ensure_preview(
  group : @async.TaskGroup[X],
) -> Result[Unit, String] noraise {
  if preview_ready() {
    return Ok(())
  }
  let script = "\{workspace}/mooncraft-preview.sh"
  if !(@fs.exists(script) catch { _ => false }) {
    return Err("Preview is not ready: mooncraft-preview.sh was not found.")
  }
  stop_preview_process()
  @fs.chmod(script, 0o755) catch {
    error => return Err("Preview script could not be made executable: \{error}")
  }
  let process = match start_preview_process(group, script) {
    Ok(process) => process
    Err(message) => return Err(message)
  }
  preview_process.val = Some(process)
  preview_pid.val = Some(process.pid)
  wait_preview_ready(process)
}

///|

///|
fn preview_upstream_path(path : String) -> String {
  @runtime_protocol.runtime_service_preview_upstream_path(path)
}

///|
fn preview_response_content_type(headers : Map[String, String]) -> String {
  match headers.get("Content-Type") {
    Some(value) => value
    None =>
      match headers.get("content-type") {
        Some(value) => value
        None => "application/octet-stream"
      }
  }
}

///|
fn preview_response_reason(code : Int) -> String {
  match code {
    200 => "OK"
    404 => "NotFound"
    500 => "InternalServerError"
    503 => "ServiceUnavailable"
    _ => "Preview"
  }
}

///|
async fn[X] handle_preview(
  path : String,
  group : @async.TaskGroup[X],
) -> HttpReply noraise {
  if require_initialized() is Some(reply) {
    return reply
  }
  match ensure_preview(group) {
    Ok(_) => {
      let upstream_path = preview_upstream_path(path)
      let result = try
        @http.get("http://127.0.0.1:\{preview_port}\{upstream_path}")
      catch {
        _ =>
          return runtime_error(
            503, "ServiceUnavailable", "Runtime preview upstream is not reachable.",
          )
      } noraise {
        result => result
      }
      let (response, body) = result
      let preview_body = body.binary()
      {
        code: response.code,
        reason: preview_response_reason(response.code),
        content_type: preview_response_content_type(response.headers),
        body: preview_body,
      }
    }
    Err(message) => runtime_error(503, "ServiceUnavailable", message)
  }
}

///|
fn route_path(path : String) -> String {
  path.split("?").to_array()[0].to_owned()
}

///|
fn run_status_route(path : String) -> String? {
  @runtime_protocol.runtime_service_run_status_route(path)
}

///|
fn run_events_route(path : String) -> String? {
  @runtime_protocol.runtime_service_run_events_route(path)
}

///|
async fn handle_request(
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  group : @async.TaskGroup[Unit],
) -> Unit noraise {
  let path = route_path(request.path)
  let reply = match (request.meth, path) {
    (Get, path) if path == @runtime_protocol.runtime_service_health_path() =>
      health_reply()
    (Post, path) if path == @runtime_protocol.runtime_service_init_path() => {
      let raw_body = body.read_all().text() catch { _ => "" }
      handle_init(raw_body)
    }
    (Post, path) if path == @runtime_protocol.runtime_service_exec_path() => {
      let raw_body = body.read_all().text() catch { _ => "" }
      handle_exec(raw_body)
    }
    (Get, _) if @runtime_protocol.runtime_service_preview_path_matches(path) =>
      handle_preview(path, group)
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
  if ensure_directory(workspace, "workspace") is Err(message) {
    println("failed to prepare workspace: \{message}")
    return
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
      (request, body, conn) => handle_request(request, body, conn, group),
      allow_failure=true,
    )
  })
}
