///|
struct AgentTurnSuccess {
  summary : String
  thread_id : String?
}

///|
struct AgentTurnFailure {
  assistant_message : String
  error_message : String
  thread_id : String?
  failure_debug : @sdk.RunFailureDebug?
}

///|
struct CodexDockerConfig {
  image : String
  provider : String
  model : String
  api_key : String
  container_home : String
}

///|
let default_codex_docker_image = "docker.io/moonbitcloud/codex:codex-0.125.0-node24"

///|
let default_codex_model = "gpt-5.5"

///|
struct RunArtifacts {
  dir : String
  last_message_path : String
  codex_log_path : String
  validation_log_path : String
}

///|
struct CodexExecutionResult {
  summary : String
  thread_id : String
  artifacts : RunArtifacts
}

///|
fn smoke_codex_enabled() -> Bool {
  match @env.get_env_var("MOONBITCLOUD_CODEX_FAKE_MODE") {
    Some(value) => value.trim() == "smoke"
    None => false
  }
}

///|
fn RunArtifacts::new(
  root : String,
  project_id : String,
  run_id : String,
) -> RunArtifacts {
  let dir = run_artifacts_dir(root, project_id, run_id)
  ensure_dir(dir)
  {
    dir,
    last_message_path: dir + "/last_message.txt",
    codex_log_path: dir + "/codex.log",
    validation_log_path: dir + "/validation.log",
  }
}

///|
fn CodexDockerConfig::container_codex_home(self : CodexDockerConfig) -> String {
  self.container_home + "/.codex"
}

///|
fn codex_container_workspace_dir() -> String {
  "/workspace"
}

///|
fn codex_container_artifacts_dir() -> String {
  "/artifacts"
}

///|
fn CodexDockerConfig::load(
  settings : AiRuntimeSettings,
) -> Result[CodexDockerConfig, String] {
  let image = match @env.get_env_var("MOONBITCLOUD_CODEX_DOCKER_IMAGE") {
    Some(value) if value.trim() != "" => value.trim().to_string()
    _ => default_codex_docker_image
  }
  if @env.get_env_var("MOONBITCLOUD_CODEX_HOME_HOST") is Some(value) &&
    value.trim() != "" {
    return Err(
      "MOONBITCLOUD_CODEX_HOME_HOST is not supported. Configure AI keys in MoonBit Cloud account settings instead.",
    )
  }
  let container_home = match
    @env.get_env_var("MOONBITCLOUD_CODEX_CONTAINER_HOME") {
    Some(value) if value.trim() != "" => value
    _ => "/root"
  }
  Ok({
    image,
    provider: settings.provider,
    model: settings.model,
    api_key: settings.api_key,
    container_home,
  })
}

///|
fn bootstrap_prompt(user_message : String) -> String {
  (
    #|You are the software engineer for MoonBit Cloud. Build the user's app inside the current workspace.
    #|
    #|Working rules:
    #|- Default to MoonBit unless the user explicitly asks for another technology.
    #|- Complete the job in one turn without asking follow-up questions.
    #|- Use subagents only for concrete, bounded implementation tasks.
    #|- This workspace intentionally starts without an app scaffold. Do not assume `frontend/`, `backend/`, or `shared/` directories exist.
    #|- Use `moon new` to create the real MoonBit project, and choose the project structure that fits the user's app.
    #|- Keep root-level `moon fmt`, `moon check`, `moon test`, and `moon build` working. If `moon new` creates a child directory, add a root `moon.work` or otherwise make root-level commands valid.
    #|
  ) +
  reference_modules_prompt_rule() +
  (
    #|
    #|- Create or maintain `moonbitcloud-preview.sh` at the workspace root. It receives `<port> <build-profile>`, starts the generated app server, serves the user-facing app at `/`, and returns success from `/api/health`.
    #|- You may inspect, edit, create, and delete files anywhere in this workspace.
    #|- You may run shell commands as needed.
    #|- Before finishing, run `moon fmt`, `moon check`, `moon test`, and `moon build`.
    #|- Your final response must be brief: summarize what you built, mention validation status, and mention any blocking failure.
    #|
    #|User's requirement:
    #|
  ) +
  user_message +
  "\n"
}

///|
fn followup_prompt(user_message : String) -> String {
  (
    #|Continue building the same MoonBit Cloud app in the current workspace.
    #|
    #|Working rules:
    #|- Default to MoonBit unless the user explicitly asks for another technology.
    #|- Complete the job in one turn without asking follow-up questions.
    #|- Use subagents only for concrete, bounded implementation tasks.
    #|- Do not assume a fixed project layout. Preserve the existing app structure unless a change is needed.
    #|- Keep root-level `moon fmt`, `moon check`, `moon test`, and `moon build` working.
    #|
  ) +
  reference_modules_prompt_rule() +
  (
    #|
    #|- Maintain `moonbitcloud-preview.sh` at the workspace root. It receives `<port> <build-profile>`, starts the generated app server, serves the user-facing app at `/`, and returns success from `/api/health`.
    #|- You may inspect, edit, create, and delete files anywhere in this workspace.
    #|- You may run shell commands as needed.
    #|- Before finishing, run `moon fmt`, `moon check`, `moon test`, and `moon build`.
    #|- Your final response must be brief: summarize what you built, mention validation status, and mention any blocking failure.
    #|
    #|Latest user request:
    #|
  ) +
  user_message +
  "\n"
}

///|
fn recovery_prompt(
  initial_project_prompt : String,
  user_message : String,
) -> String {
  (
    #|Continue building the same MoonBit Cloud app inside the current workspace.
    #|
    #|Working rules:
    #|- Default to MoonBit unless the user explicitly asks for another technology.
    #|- Complete the job in one turn without asking follow-up questions.
    #|- Use subagents only for concrete, bounded implementation tasks.
    #|- The current workspace already contains the latest saved project state.
    #|- Do not assume a fixed project layout. Preserve the existing app structure unless a change is needed.
    #|- Keep root-level `moon fmt`, `moon check`, `moon test`, and `moon build` working.
    #|
  ) +
  reference_modules_prompt_rule() +
  (
    #|
    #|- Maintain `moonbitcloud-preview.sh` at the workspace root. It receives `<port> <build-profile>`, starts the generated app server, serves the user-facing app at `/`, and returns success from `/api/health`.
    #|- You may inspect, edit, create, and delete files anywhere in this workspace.
    #|- You may run shell commands as needed.
    #|- Before finishing, run `moon fmt`, `moon check`, `moon test`, and `moon build`.
    #|- Your final response must be brief: summarize what you built, mention validation status, and mention any blocking failure.
    #|
    #|Original project requirement:
    #|
  ) +
  initial_project_prompt +
  (
    #|
    #|
    #|Latest user request:
    #|
  ) +
  user_message +
  "\n"
}

///|
fn default_success_summary() -> String {
  "I updated the workspace and the app passed validation."
}

///|
fn default_failure_assistant_message() -> String {
  "I couldn't finish that update. The run failed before the preview could be refreshed."
}

///|
fn moonbit_registry_fetch_failed(output : String) -> Bool {
  let lower = output.to_lower()
  (lower.contains("download.mooncakes.io") || lower.contains("mooncakes")) &&
  (
    lower.contains("tls handshake") ||
    lower.contains("error sending request") ||
    lower.contains("client error") ||
    lower.contains("connection") ||
    lower.contains("timeout")
  )
}

///|
fn dependency_fetch_failure_assistant_message(
  output : String,
  fallback : String,
) -> String {
  if moonbit_registry_fetch_failed(output) {
    "I couldn't fetch MoonBit packages from Mooncakes, so the preview could not be validated or refreshed. This is usually a temporary network or package-registry issue. Please retry; if it keeps happening, the platform operator should refresh the Codex image cache and check Mooncakes connectivity."
  } else {
    fallback
  }
}

///|
fn trim_or_default(text : String, fallback : String) -> String {
  let normalized = text.trim(chars="\n\r ").to_string()
  if normalized == "" {
    fallback
  } else {
    normalized
  }
}

///|
fn tail_text(text : String, limit : Int) -> String {
  let normalized = text.trim(chars="\n\r ").to_string()
  if normalized.length() <= limit {
    normalized
  } else {
    normalized.unsafe_substring(
      start=normalized.length() - limit,
      end=normalized.length(),
    )
  }
}

///|
fn extract_json_string_field(line : String, field : String) -> String? {
  let prefix = "\"" + field + "\":\""
  match line.find(prefix) {
    Some(start) => {
      let value_start = start + prefix.length()
      let rest = line.unsafe_substring(start=value_start, end=line.length())
      match rest.find("\"") {
        Some(end) => Some(rest.unsafe_substring(start=0, end~))
        None => None
      }
    }
    None => None
  }
}

///|
fn extract_thread_id(events : String) -> String? {
  for raw_line in events.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_string()
    if line.contains("\"type\":\"thread.started\"") {
      return extract_json_string_field(line, "thread_id")
    }
  }
  None
}

///|
fn resume_session_missing(output : String) -> Bool {
  let lower = output.to_lower()
  lower.contains("thread/resume failed") &&
  (
    lower.contains("no rollout found") ||
    (lower.contains("thread id") && lower.contains("not found"))
  )
}

///|
fn codex_command_progress_message(line : String) -> String? {
  if line.contains("moon fmt") {
    Some("Formatting the workspace.")
  } else if line.contains("moon check") {
    Some("Checking the workspace.")
  } else if line.contains("moon test") {
    Some("Running tests.")
  } else if line.contains("moon fetch") {
    Some("Fetching MoonBit project dependencies.")
  } else if line.contains("moon update") {
    Some("Refreshing MoonBit registry metadata.")
  } else {
    None
  }
}

///|
fn codex_display_event(line : String) -> (String, String)? {
  let trimmed = line.trim().to_string()
  if trimmed == "" || !trimmed.has_prefix("{") {
    return None
  }
  if trimmed.contains("\"type\":\"thread.started\"") {
    Some(("status", "Started Codex session."))
  } else if trimmed.contains("\"type\":\"turn.started\"") {
    Some(("status", "Planning the change."))
  } else if trimmed.contains("\"type\":\"turn.completed\"") {
    Some(("status", "Codex finished the update."))
  } else if trimmed.contains("\"type\":\"turn.failed\"") {
    Some(("status", "Codex reported a failure."))
  } else if trimmed.contains("\"type\":\"agent_message\"") {
    match extract_json_string_field(trimmed, "text") {
      Some(text) if text.trim() != "" => Some(("progress", text))
      _ => None
    }
  } else if trimmed.contains("\"type\":\"file_change\"") {
    if trimmed.contains("\"status\":\"completed\"") {
      Some(("status", "Updated project files."))
    } else {
      Some(("status", "Editing project files."))
    }
  } else if trimmed.contains("\"type\":\"command_execution\"") {
    if trimmed.contains("\"status\":\"failed\"") {
      Some(("status", "A workspace command failed; Codex is handling it."))
    } else {
      match codex_command_progress_message(trimmed) {
        Some(message) => Some(("status", message))
        None => None
      }
    }
  } else {
    None
  }
}

///|
async fn append_codex_display_event(
  store : Store,
  project_id : String,
  run_id : String,
  line : String,
) -> Unit noraise {
  match codex_display_event(line) {
    Some((kind, content)) =>
      store.append_run_event(project_id, run_id, kind, content)
    None => ignore(())
  }
}

///|
fn append_command_log(
  path : String,
  label : String,
  command : Array[String],
  exit_code : Int,
  content : String,
) -> Unit {
  safe_append_string(
    path,
    "== \{label} ==\ncommand: " +
    command_display(command) +
    "\nexit_code: \{exit_code}\n\n" +
    trim_or_default(content, "(no output)") +
    "\n\n",
  )
}

///|
fn moonbit_string_literal(value : String) -> String {
  "\"" +
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n") +
  "\""
}

///|
fn fake_codex_state_dir(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/fake-codex"
}

///|
fn fake_codex_resume_reset_marker(root : String, project_id : String) -> String {
  fake_codex_state_dir(root, project_id) + "/resume-reset-once"
}

///|
fn fake_codex_update_workspace(
  workspace_path : String,
  prompt : String,
) -> Result[String, String] {
  let normalized = trim_or_default(prompt, "MoonBit Cloud update")
  let async_version = required_reference_module_version("moonbitlang/async")
  let mocket_version = required_reference_module_version("oboard/mocket")
  let x_version = required_reference_module_version("moonbitlang/x")
  let title = if normalized.length() > 48 {
    normalized.unsafe_substring(start=0, end=48)
  } else {
    normalized
  }
  let subtitle = "Smoke mode applied: " + normalized
  safe_write_string(
    workspace_path + "/moon.mod.json",
    (
      #|{
      #|  "name": "moonbitcloud/generated-app",
      #|  "version": "0.1.0",
      #|  "preferred-target": "native",
      #|  "deps": {
    ) +
    "    \"moonbitlang/async\": \"" +
    async_version +
    "\",\n" +
    "    \"oboard/mocket\": \"" +
    mocket_version +
    "\",\n" +
    "    \"moonbitlang/x\": \"" +
    x_version +
    "\"\n" +
    (
      #|  },
      #|  "readme": "README.md",
      #|  "repository": "",
      #|  "license": "Apache-2.0",
      #|  "keywords": ["moonbit", "moonbitcloud", "generated"],
      #|  "description": "Smoke-mode generated MoonBit Cloud app."
      #|}
    ),
  )
  safe_write_string(
    workspace_path + "/moon.pkg",
    (
      #|import {
      #|  "moonbitlang/async",
      #|  "oboard/mocket",
      #|  "moonbitlang/core/env",
      #|  "moonbitlang/core/string",
      #|}
      #|
      #|options(
      #|  "is-main": true,
      #|)
      #|
      #|supported_targets = "native"
    ),
  )
  safe_write_string(
    workspace_path + "/main.mbt",
    (
      #|///|
      #|async fn main {
      #|  let args = @env.args()
      #|  let port = if args.length() > 1 {
      #|    @string.parse_int(args[1]) catch {
      #|      _ => 4300
      #|    }
      #|  } else {
      #|    4300
      #|  }
      #|  let title = 
    ) +
    moonbit_string_literal(title) +
    (
      #|
      #|  let subtitle = 
    ) +
    moonbit_string_literal(subtitle) +
    (
      #|
      #|  let app = @mocket.new()
      #|  app.get("/api/health", _ => @mocket.HttpResponse::new(OK, headers={ "Content-Type": "application/json" }).body("{\"ok\":true}"))
      #|  app.get("/", _ => @mocket.HttpResponse::new(OK, headers={ "Content-Type": "text/html; charset=utf-8" }).body("<!doctype html><html><head><meta charset='utf-8'><title>" + title + "</title><style>body{font-family:sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;background:#f6fbf8;color:#10231b}.card{max-width:680px;padding:40px;border-radius:28px;background:white;box-shadow:0 30px 90px #d7e4dc}p{color:#52645b;line-height:1.6}</style></head><body><main class='card'><p>MoonBit Cloud smoke preview</p><h1>" + title + "</h1><p>" + subtitle + "</p></main></body></html>"))
      #|  app.listen("0.0.0.0:\{port}")
      #|}
    ),
  )
  safe_write_string(
    workspace_path + "/" + preview_script_relative_path(),
    (
      #|#!/usr/bin/env bash
      #|set -euo pipefail
      #|port="${1:-4300}"
      #|profile="${2:-debug}"
      #|exe="$(find "_build/native/${profile}/build" -name '*.exe' -type f | head -n 1)"
      #|if [ -z "${exe}" ]; then
      #|  echo "No native MoonBit executable was found for profile ${profile}." >&2
      #|  exit 1
      #|fi
      #|exec "${exe}" "${port}"
    ),
  )
  safe_write_string(
    workspace_path + "/README.md",
    "# Smoke Mode\n\nLatest request: " + normalized + "\n",
  )
  Ok(
    "Smoke mode updated the workspace for: " +
    normalized +
    ". Validation completed.",
  )
}

///|
fn command_args(command : Array[String]) -> Array[String] {
  let args : Array[String] = []
  for i in 1..<command.length() {
    args.push(command[i])
  }
  args
}

///|
fn codex_command_is_resume(command : Array[String]) -> Bool {
  for part in command {
    if part == "resume" {
      return true
    }
  }
  false
}

///|
async fn collect_local_output(
  executable : String,
  args : Array[String],
  cwd : String,
) -> Result[(Int, String), String] noraise {
  let result = try
    @process.collect_output_merged(executable, args, cwd~)
  catch {
    err => return Err("The local command could not be started: \{err}")
  } noraise {
    value => value
  }
  let (exit_code, output) = result
  let text = output.text() catch { _ => "" }
  Ok((exit_code, text))
}

///|
fn collect_fake_codex_output(
  root : String,
  project : @sdk.ProjectDetail,
  workspace_path : String,
  command : Array[String],
) -> Result[(Int, String, String?), String] {
  if command.length() < 2 {
    return Err("The fake Codex command was malformed.")
  }
  let is_resume = codex_command_is_resume(command)
  let prompt = command[command.length() - 1]
  ensure_dir(fake_codex_state_dir(root, project.id))
  if is_resume {
    let thread_id = command[command.length() - 2]
    let reset_marker = fake_codex_resume_reset_marker(root, project.id)
    if !@fs.path_exists(reset_marker) {
      safe_write_string(reset_marker, "reset")
      return Ok(
        (
          1,
          "Error: thread/resume: thread/resume failed: no rollout found for thread id \{thread_id}",
          None,
        ),
      )
    }
    let summary = match fake_codex_update_workspace(workspace_path, prompt) {
      Ok(summary) => summary
      Err(message) => return Err(message)
    }
    Ok((0, "{\"type\":\"turn.completed\"}", Some(summary)))
  } else {
    let thread_id = next_id("fake-thread")
    let summary = match fake_codex_update_workspace(workspace_path, prompt) {
      Ok(summary) => summary
      Err(message) => return Err(message)
    }
    Ok(
      (
        0,
        "{\"type\":\"thread.started\",\"thread_id\":\"\{thread_id}\"}\n{\"type\":\"turn.completed\"}",
        Some(summary),
      ),
    )
  }
}

///|
fn stage_failure_message(
  stage : String,
  exit_code : Int,
  log_path : String,
  output : String,
) -> String {
  let suffix = tail_text(output, 1200)
  if suffix == "" {
    "\{stage} failed with exit code \{exit_code}. Log: \{log_path}"
  } else {
    "\{stage} failed with exit code \{exit_code}. Log: \{log_path}\n\n\{suffix}"
  }
}

///|
fn command_display(command : Array[String]) -> String {
  let mut text = ""
  for index in 0..<command.length() {
    if index > 0 {
      text = text + " "
    }
    let part = if command.length() > 0 &&
      command[0] == "codex" &&
      index == command.length() - 1 {
      "<prompt>"
    } else {
      command[index]
    }
    text = text + shell_quote(part)
  }
  text
}

///|
fn failure_debug(
  stage : String,
  command : Array[String]?,
  exit_code : Int?,
  artifacts : RunArtifacts?,
) -> @sdk.RunFailureDebug {
  {
    stage,
    command: command.map(command_display),
    exit_code,
    codex_log_path: artifacts.map(fn(artifacts) { artifacts.codex_log_path }),
    validation_log_path: artifacts.map(fn(artifacts) {
      artifacts.validation_log_path
    }),
    final_summary_path: artifacts.map(fn(artifacts) {
      artifacts.last_message_path
    }),
  }
}

///|
fn docker_command_args(
  config : CodexDockerConfig,
  workspace_path : String,
  artifacts : RunArtifacts,
  container_command : Array[String],
) -> Array[String] {
  let args : Array[String] = ["run", "--rm"]
  args.push("-e")
  args.push("HOME=" + config.container_home)
  args.push("-e")
  args.push("CODEX_HOME=" + config.container_codex_home())
  args.push("-e")
  args.push("MOONBITCLOUD_AI_PROVIDER=" + config.provider)
  args.push("-e")
  args.push("MOONBITCLOUD_AI_MODEL=" + config.model)
  args.push("-e")
  args.push("MOONBITCLOUD_AI_API_KEY=" + config.api_key)
  args.push("-v")
  args.push(workspace_path + ":" + codex_container_workspace_dir())
  args.push("-v")
  args.push(artifacts.dir + ":" + codex_container_artifacts_dir())
  args.push("-w")
  args.push(codex_container_workspace_dir())
  args.push(config.image)
  for part in docker_codex_entry_command(container_command) {
    args.push(part)
  }
  args
}

///|
fn docker_codex_entry_command(
  container_command : Array[String],
) -> Array[String] {
  let script_lines : Array[String] = ["set -e"]
  for command in user_project_fetch_commands() {
    script_lines.push(command)
  }
  script_lines.push("exec \"$@\"")
  let wrapped : Array[String] = [
    "sh",
    "-lc",
    script_lines.join("\n"),
    "moonbitcloud-codex",
  ]
  for part in container_command {
    wrapped.push(part)
  }
  wrapped
}

///|
async fn collect_docker_output(
  root : String,
  config : CodexDockerConfig,
  workspace_path : String,
  artifacts : RunArtifacts,
  container_command : Array[String],
) -> Result[(Int, String), String] noraise {
  let docker_args = docker_command_args(
    config, workspace_path, artifacts, container_command,
  )
  let result = try
    @process.collect_output_merged("docker", docker_args, cwd=root)
  catch {
    err =>
      return Err("The Docker-backed Codex command could not be started: \{err}")
  } noraise {
    value => value
  }
  let (exit_code, output) = result
  let text = output.text() catch { _ => "" }
  Ok((exit_code, text))
}

///|
async fn stream_docker_output(
  store : Store,
  root : String,
  project_id : String,
  run_id : String,
  config : CodexDockerConfig,
  workspace_path : String,
  artifacts : RunArtifacts,
  container_command : Array[String],
) -> Result[(Int, String), String] noraise {
  let docker_args = docker_command_args(
    config, workspace_path, artifacts, container_command,
  )
  let pipe = @process.read_from_process() catch {
    err =>
      return Err(
        "The Docker-backed Codex output pipe could not be opened: \{err}",
      )
  }
  let (reader, writer) = pipe
  let chunks : Array[String] = []
  let exit_code_ref : Ref[Int] = @ref.new(-1)
  store.append_run_event(
    project_id, run_id, "status", "Starting Codex session.",
  )
  let group_result = try
    @async.with_task_group(async fn(group) {
      let task = group.spawn(
        async fn() {
          @process.run(
            "docker",
            docker_args,
            stdout=writer,
            stderr=writer,
            cwd=root,
          )
        },
        allow_failure=true,
      )
      let mut reading = true
      while reading {
        match reader.read_until("\n") {
          Some(line) => {
            let text = line.to_string()
            chunks.push(text)
            chunks.push("\n")
            append_codex_display_event(store, project_id, run_id, text)
          }
          None => reading = false
        }
      }
      exit_code_ref.val = task.wait()
      ()
    })
  catch {
    err =>
      return Err(
        "The Docker-backed Codex command failed while streaming output: \{err}",
      )
  } noraise {
    value => value
  }
  ignore(group_result)
  Ok((exit_code_ref.val, chunks.join("")))
}

///|
async fn collect_codex_command_output(
  store : Store,
  run_id : String,
  root : String,
  config : CodexDockerConfig?,
  project : @sdk.ProjectDetail,
  workspace_path : String,
  artifacts : RunArtifacts,
  command : Array[String],
) -> Result[(Int, String, String?), String] noraise {
  if smoke_codex_enabled() {
    let result = match
      collect_fake_codex_output(root, project, workspace_path, command) {
      Ok(result) => result
      Err(message) => return Err(message)
    }
    store.append_run_event(
      project.id,
      run_id,
      "status",
      "Running fake Codex executor.",
    )
    for raw_line in result.1.replace_all(old="\r\n", new="\n").split("\n") {
      let line = raw_line.to_string()
      if line != "" {
        append_codex_display_event(store, project.id, run_id, line)
      }
    }
    Ok(result)
  } else {
    match config {
      Some(config) => {
        let result = match
          stream_docker_output(
            store,
            root,
            project.id,
            run_id,
            config,
            workspace_path,
            artifacts,
            command,
          ) {
          Ok(result) => result
          Err(message) => return Err(message)
        }
        Ok((result.0, result.1, None))
      }
      None => Err("The Docker-backed Codex command is not configured.")
    }
  }
}

///|
fn codex_exec_command(model : String, user_prompt : String) -> Array[String] {
  [
    "codex",
    "exec",
    "--model",
    model,
    "--skip-git-repo-check",
    "--json",
    "--output-last-message",
    codex_container_artifacts_dir() + "/last_message.txt",
    "--dangerously-bypass-approvals-and-sandbox",
    bootstrap_prompt(user_prompt),
  ]
}

///|
fn codex_resume_command(
  model : String,
  thread_id : String,
  user_prompt : String,
) -> Array[String] {
  [
    "codex",
    "exec",
    "resume",
    "--model",
    model,
    "--skip-git-repo-check",
    "--json",
    "--output-last-message",
    codex_container_artifacts_dir() + "/last_message.txt",
    "--dangerously-bypass-approvals-and-sandbox",
    thread_id,
    followup_prompt(user_prompt),
  ]
}

///|
fn codex_failure(
  assistant_message : String,
  error_message : String,
  thread_id : String?,
) -> AgentTurnFailure {
  codex_failure_with_debug(assistant_message, error_message, thread_id, None)
}

///|
fn codex_failure_with_debug(
  assistant_message : String,
  error_message : String,
  thread_id : String?,
  failure_debug : @sdk.RunFailureDebug?,
) -> AgentTurnFailure {
  {
    assistant_message: if assistant_message == "" {
      default_failure_assistant_message()
    } else {
      assistant_message
    },
    error_message,
    thread_id,
    failure_debug,
  }
}

///|
async fn run_codex_turn(
  store : Store,
  root : String,
  config : CodexDockerConfig?,
  project : @sdk.ProjectDetail,
  initial_project_prompt : String,
  workspace_path : String,
  run_id : String,
  user_prompt : String,
) -> Result[CodexExecutionResult, AgentTurnFailure] noraise {
  let artifacts = RunArtifacts::new(root, project.id, run_id)
  safe_write_string(artifacts.last_message_path, "")
  safe_write_string(artifacts.codex_log_path, "")
  let thread_id_before = project.codex_thread_id
  let model = match config {
    Some(config) => config.model
    None => default_codex_model
  }
  let command = match thread_id_before {
    Some(thread_id) => codex_resume_command(model, thread_id, user_prompt)
    None => codex_exec_command(model, user_prompt)
  }
  let mut active_command = command
  let codex_result = match
    collect_codex_command_output(
      store, run_id, root, config, project, workspace_path, artifacts, command,
    ) {
    Ok(result) => result
    Err(message) =>
      return Err(
        codex_failure_with_debug(
          "I couldn't start the Codex worker for that update.",
          message,
          thread_id_before,
          Some(
            failure_debug(
              "Codex command startup",
              Some(command),
              None,
              Some(artifacts),
            ),
          ),
        ),
      )
  }
  let (initial_exit_code, initial_output, initial_fake_summary) = codex_result
  let mut exit_code = initial_exit_code
  let mut output = initial_output
  let mut fake_summary = initial_fake_summary
  append_command_log(
    artifacts.codex_log_path,
    if thread_id_before is Some(_) {
      "codex resume"
    } else {
      "codex exec"
    },
    active_command,
    exit_code,
    output,
  )
  let mut thread_id = thread_id_before
  if thread_id_before is None {
    thread_id = match extract_thread_id(output) {
      Some(thread_id) => Some(thread_id)
      None =>
        return Err(
          codex_failure_with_debug(
            dependency_fetch_failure_assistant_message(
              output,
              default_failure_assistant_message(),
            ),
            stage_failure_message(
              "Codex session startup",
              exit_code,
              artifacts.codex_log_path,
              output,
            ),
            None,
            Some(
              failure_debug(
                "Codex session startup",
                Some(active_command),
                Some(exit_code),
                Some(artifacts),
              ),
            ),
          ),
        )
    }
  }
  if thread_id_before is Some(_) &&
    exit_code != 0 &&
    resume_session_missing(output) {
    let recovery_command = codex_exec_command(
      model,
      recovery_prompt(initial_project_prompt, user_prompt),
    )
    let recovery_result = match
      collect_codex_command_output(
        store, run_id, root, config, project, workspace_path, artifacts, recovery_command,
      ) {
      Ok(result) => result
      Err(message) =>
        return Err(
          codex_failure_with_debug(
            "I couldn't recover the missing Codex session for that update.",
            message,
            thread_id_before,
            Some(
              failure_debug(
                "Codex session recovery startup",
                Some(recovery_command),
                None,
                Some(artifacts),
              ),
            ),
          ),
        )
    }
    let (recovery_exit_code, recovery_output, recovery_fake_summary) = recovery_result
    active_command = recovery_command
    append_command_log(
      artifacts.codex_log_path,
      "codex session recovery",
      active_command,
      recovery_exit_code,
      recovery_output,
    )
    let recovery_thread_id = match extract_thread_id(recovery_output) {
      Some(thread_id) => thread_id
      None =>
        return Err(
          codex_failure_with_debug(
            dependency_fetch_failure_assistant_message(
              recovery_output,
              default_failure_assistant_message(),
            ),
            stage_failure_message(
              "Codex session recovery",
              recovery_exit_code,
              artifacts.codex_log_path,
              recovery_output,
            ),
            None,
            Some(
              failure_debug(
                "Codex session recovery",
                Some(active_command),
                Some(recovery_exit_code),
                Some(artifacts),
              ),
            ),
          ),
        )
    }
    exit_code = recovery_exit_code
    output = recovery_output
    fake_summary = recovery_fake_summary
    thread_id = Some(recovery_thread_id)
  }
  let thread_id = match thread_id {
    Some(thread_id) => thread_id
    None =>
      return Err(
        codex_failure_with_debug(
          default_failure_assistant_message(),
          "The Codex thread id could not be determined for this run.",
          None,
          Some(
            failure_debug(
              "Codex session startup",
              Some(active_command),
              Some(exit_code),
              Some(artifacts),
            ),
          ),
        ),
      )
  }
  match snapshot_workspace(store, root, project.id, workspace_path) {
    Ok(_) => ignore(())
    Err(message) =>
      return Err(
        codex_failure_with_debug(
          default_failure_assistant_message(),
          message,
          Some(thread_id),
          Some(
            failure_debug(
              "Workspace snapshot",
              Some(active_command),
              None,
              Some(artifacts),
            ),
          ),
        ),
      )
  }
  let summary = match fake_summary {
    Some(summary) => trim_or_default(summary, default_success_summary())
    None =>
      trim_or_default(
        safe_read_string_or(artifacts.last_message_path, ""),
        default_success_summary(),
      )
  }
  if exit_code != 0 {
    return Err(
      codex_failure_with_debug(
        dependency_fetch_failure_assistant_message(
          output,
          default_failure_assistant_message(),
        ),
        stage_failure_message(
          "Codex execution",
          exit_code,
          artifacts.codex_log_path,
          output,
        ),
        Some(thread_id),
        Some(
          failure_debug(
            "Codex execution",
            Some(active_command),
            Some(exit_code),
            Some(artifacts),
          ),
        ),
      ),
    )
  }
  Ok({ summary, thread_id, artifacts })
}

///|
async fn run_validation_command(
  root : String,
  config : CodexDockerConfig?,
  workspace_path : String,
  artifacts : RunArtifacts,
  label : String,
  command : Array[String],
  thread_id : String,
) -> Result[Unit, AgentTurnFailure] noraise {
  let result = if smoke_codex_enabled() {
    match
      collect_local_output(command[0], command_args(command), workspace_path) {
      Ok(result) => result
      Err(message) =>
        return Err(
          codex_failure_with_debug(
            "I updated the workspace, but validation could not be started.",
            message,
            Some(thread_id),
            Some(failure_debug(label, Some(command), None, Some(artifacts))),
          ),
        )
    }
  } else {
    match config {
      Some(config) =>
        match
          collect_docker_output(
            root, config, workspace_path, artifacts, command,
          ) {
          Ok(result) => result
          Err(message) =>
            return Err(
              codex_failure_with_debug(
                "I updated the workspace, but validation could not be started.",
                message,
                Some(thread_id),
                Some(failure_debug(label, Some(command), None, Some(artifacts))),
              ),
            )
        }
      None =>
        return Err(
          codex_failure_with_debug(
            "I updated the workspace, but validation could not be started.",
            "The Docker-backed validator is not configured.",
            Some(thread_id),
            Some(failure_debug(label, Some(command), None, Some(artifacts))),
          ),
        )
    }
  }
  let (exit_code, output) = result
  append_command_log(
    artifacts.validation_log_path,
    label,
    command,
    exit_code,
    output,
  )
  if exit_code != 0 {
    return Err(
      codex_failure_with_debug(
        dependency_fetch_failure_assistant_message(
          output, "I updated the workspace, but validation failed before the preview could be refreshed.",
        ),
        stage_failure_message(
          label,
          exit_code,
          artifacts.validation_log_path,
          output,
        ),
        Some(thread_id),
        Some(
          failure_debug(label, Some(command), Some(exit_code), Some(artifacts)),
        ),
      ),
    )
  }
  Ok(())
}

///|
fn validation_shell_script(include_update~ : Bool) -> String {
  let commands : Array[String] = []
  if include_update {
    commands.push("moon update")
  }
  for command in user_project_fetch_commands() {
    commands.push(command)
  }
  commands.push("moon fmt")
  commands.push("moon check")
  commands.push("moon build")
  commands.push("moon test")
  let lines : Array[String] = []
  lines.push("set -e")
  for command in commands {
    lines.push("echo '== " + command + " =='")
    lines.push(command)
  }
  lines.join("\n")
}

///|
async fn run_docker_validation_sequence(
  root : String,
  config : CodexDockerConfig?,
  workspace_path : String,
  artifacts : RunArtifacts,
  thread_id : String,
) -> Result[Unit, AgentTurnFailure] noraise {
  let command = ["sh", "-lc", validation_shell_script(include_update=false)]
  let result = match config {
    Some(config) =>
      match
        collect_docker_output(root, config, workspace_path, artifacts, command) {
        Ok(result) => result
        Err(message) =>
          return Err(
            codex_failure_with_debug(
              "I updated the workspace, but validation could not be started.",
              message,
              Some(thread_id),
              Some(
                failure_debug(
                  "MoonBit validation",
                  Some(command),
                  None,
                  Some(artifacts),
                ),
              ),
            ),
          )
      }
    None =>
      return Err(
        codex_failure_with_debug(
          "I updated the workspace, but validation could not be started.",
          "The Docker-backed validator is not configured.",
          Some(thread_id),
          Some(
            failure_debug(
              "MoonBit validation",
              Some(command),
              None,
              Some(artifacts),
            ),
          ),
        ),
      )
  }
  let (exit_code, output) = result
  append_command_log(
    artifacts.validation_log_path,
    "MoonBit validation",
    command,
    exit_code,
    output,
  )
  if exit_code != 0 {
    return Err(
      codex_failure_with_debug(
        dependency_fetch_failure_assistant_message(
          output, "I updated the workspace, but validation failed before the preview could be refreshed.",
        ),
        stage_failure_message(
          "MoonBit validation",
          exit_code,
          artifacts.validation_log_path,
          output,
        ),
        Some(thread_id),
        Some(
          failure_debug(
            "MoonBit validation",
            Some(command),
            Some(exit_code),
            Some(artifacts),
          ),
        ),
      ),
    )
  }
  Ok(())
}

///|
async fn run_local_validation_sequence(
  root : String,
  config : CodexDockerConfig?,
  workspace_path : String,
  artifacts : RunArtifacts,
  thread_id : String,
) -> Result[Unit, AgentTurnFailure] noraise {
  let _ = config
  match
    run_validation_command(
      root,
      None,
      workspace_path,
      artifacts,
      "moon fmt",
      ["moon", "fmt"],
      thread_id,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  match
    run_validation_command(
      root,
      None,
      workspace_path,
      artifacts,
      "moon check",
      ["moon", "check"],
      thread_id,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  match
    run_validation_command(
      root,
      None,
      workspace_path,
      artifacts,
      "moon test",
      ["moon", "test"],
      thread_id,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  Ok(())
}

///|
async fn run_validation_sequence(
  root : String,
  config : CodexDockerConfig?,
  workspace_path : String,
  artifacts : RunArtifacts,
  thread_id : String,
) -> Result[Unit, AgentTurnFailure] noraise {
  if smoke_codex_enabled() {
    run_local_validation_sequence(
      root, config, workspace_path, artifacts, thread_id,
    )
  } else {
    run_docker_validation_sequence(
      root, config, workspace_path, artifacts, thread_id,
    )
  }
}

///|
async fn AgentGateway::run_turn(
  self : AgentGateway,
  store : Store,
  project : @sdk.ProjectDetail,
  initial_project_prompt : String,
  workspace_path : String,
  run_id : String,
  user_prompt : String,
) -> Result[AgentTurnSuccess, AgentTurnFailure] noraise {
  let config = if smoke_codex_enabled() {
    None
  } else {
    let settings = match store.get_ai_runtime_settings_for_project(project.id) {
      Ok(settings) => settings
      Err(message) =>
        return Err(
          codex_failure(
            "Configure your AI provider and API key in Account before running Codex.",
            message,
            project.codex_thread_id,
          ),
        )
    }
    match CodexDockerConfig::load(settings) {
      Ok(config) => Some(config)
      Err(message) =>
        return Err(
          codex_failure(
            "I couldn't start the Codex worker for that update.",
            message,
            project.codex_thread_id,
          ),
        )
    }
  }
  let codex_result = match
    run_codex_turn(
      store,
      self.root,
      config,
      project,
      initial_project_prompt,
      workspace_path,
      run_id,
      user_prompt,
    ) {
    Ok(result) => result
    Err(failure) => return Err(failure)
  }
  let artifacts = codex_result.artifacts
  let persist_validated_workspace = async fn() noraise {
    match snapshot_workspace(store, self.root, project.id, workspace_path) {
      Ok(_) => Ok(())
      Err(message) =>
        Err(
          codex_failure_with_debug(
            "I updated the workspace, but saving the latest project snapshot failed.",
            message,
            Some(codex_result.thread_id),
            Some(
              failure_debug("Workspace snapshot", None, None, Some(artifacts)),
            ),
          ),
        )
    }
  }
  safe_write_string(artifacts.validation_log_path, "")
  match
    run_validation_sequence(
      self.root,
      config,
      workspace_path,
      artifacts,
      codex_result.thread_id,
    ) {
    Ok(_) => ignore(())
    Err(failure) => {
      ignore(persist_validated_workspace())
      return Err(failure)
    }
  }
  match persist_validated_workspace() {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  Ok({ summary: codex_result.summary, thread_id: Some(codex_result.thread_id) })
}

///|
async fn AppContext::spawn_project_turn_worker(
  self : AppContext,
  project_id : String,
  run_id : String,
) -> Result[Int, String] noraise {
  let executable_path = control_plane_executable_path(
    self.root,
    self.build_profile,
  )
  if !@fs.path_exists(executable_path) {
    return Err(
      "The background run worker executable was not found at \{executable_path}. Build the control plane before sending a request.",
    )
  }
  let artifacts = RunArtifacts::new(self.root, project_id, run_id)
  let worker_log_path = artifacts.dir + "/worker.log"
  spawn_worker_process(
    self.root,
    executable_path,
    worker_log_path,
    project_id,
    run_id,
  )
}

///|
async fn AppContext::run_project_turn(
  self : AppContext,
  project_id : String,
  run_id : String,
) -> Unit {
  let project = match self.store.get_project_detail(project_id) {
    Some(project) => project
    None => {
      self.store.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        "The project for this run was not found.",
        None,
      )
      return
    }
  }
  let prompt = match self.store.get_run_prompt(project_id, run_id) {
    Some(prompt) => prompt
    None => {
      self.store.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        "The user message for this run was not found.",
        project.codex_thread_id,
      )
      return
    }
  }
  let initial_project_prompt = match
    self.store.get_initial_project_prompt(project_id) {
    Some(prompt) => prompt
    None => {
      self.store.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        "The initial project prompt was not persisted for this project.",
        project.codex_thread_id,
      )
      return
    }
  }
  let runtime_workspace_path = project_workspace(self.root, project_id)
  let run_workspace_path = match
    hydrate_run_workspace(self.store, self.root, project_id, run_id) {
    Ok(path) => path
    Err(message) => {
      self.store.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        message,
        project.codex_thread_id,
      )
      return
    }
  }
  let agent_result = self.agent_gateway.run_turn(
    self.store,
    project,
    initial_project_prompt,
    run_workspace_path,
    run_id,
    prompt,
  )
  match agent_result {
    Ok(result) => {
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        runtime_workspace_path,
      )
      remove_run_workspace(self.root, project_id, run_id)
      match restore_cache_result {
        Ok(_) => ignore(())
        Err(message) => {
          self.store.finish_run_failure(
            project_id,
            run_id,
            result.summary +
            "\n\nWorkspace status: the saved snapshot could not be restored into the local cache.",
            message,
            result.thread_id,
          )
          return
        }
      }
      let updated_project = match self.store.get_project_detail(project_id) {
        Some(project) => project
        None => {
          self.store.finish_run_failure(
            project_id,
            run_id,
            default_failure_assistant_message(),
            "The updated project workspace could not be loaded after Codex finished.",
            result.thread_id,
          )
          return
        }
      }
      let preview_result = self.previews.rebuild_and_restart(updated_project)
      match preview_result {
        Ok(preview) =>
          self.store.finish_run_success(
            project_id,
            run_id,
            result.summary,
            result.thread_id,
            preview,
          )
        Err(message) =>
          self.store.finish_run_failure(
            project_id,
            run_id,
            result.summary + "\n\nPreview status: " + message,
            message,
            result.thread_id,
          )
      }
    }
    Err(failure) => {
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        runtime_workspace_path,
      )
      remove_run_workspace(self.root, project_id, run_id)
      match restore_cache_result {
        Ok(_) => ignore(())
        Err(message) =>
          return self.store.finish_run_failure_with_debug(
            project_id,
            run_id,
            failure.assistant_message +
            "\n\nWorkspace status: the saved snapshot could not be restored into the local cache.",
            failure.error_message + "\n\nWorkspace restore failed: " + message,
            failure.thread_id,
            failure.failure_debug,
          )
      }
      self.store.finish_run_failure_with_debug(
        project_id,
        run_id,
        failure.assistant_message,
        failure.error_message,
        failure.thread_id,
        failure.failure_debug,
      )
    }
  }
}

///|
fn worker_process_args(project_id : String, run_id : String) -> Array[String] {
  let args : Array[String] = []
  args.push("run-worker")
  args.push(project_id)
  args.push(run_id)
  args
}

///|
async fn spawn_worker_process(
  root : String,
  executable_path : String,
  log_path : String,
  project_id : String,
  run_id : String,
) -> Result[Int, String] noraise {
  let stdout = try
    @process.redirect_to_file(log_path, create=0o644, truncate=true)
  catch {
    err =>
      return Err("The background run worker log could not be opened: \{err}")
  } noraise {
    output => output
  }
  let stderr = try
    @process.redirect_to_file(log_path, append=true, create=0o644)
  catch {
    err =>
      return Err("The background run worker log could not be opened: \{err}")
  } noraise {
    output => output
  }
  let pid = try
    @process.spawn_orphan(
      executable_path,
      worker_process_args(project_id, run_id),
      stdout~,
      stderr~,
      cwd=root,
    )
  catch {
    err =>
      return Err(
        "The background run worker could not be started: \{err}. Log: \{log_path}",
      )
  } noraise {
    pid => pid
  }
  Ok(pid)
}

///|
async fn run_worker_mode(
  root : String,
  project_id : String,
  run_id : String,
) -> Unit {
  let ctx = match AppContext::try_new_for_worker_async(root) {
    Ok(ctx) => ctx
    Err(message) => abort("MoonBit Cloud worker cannot start: " + message)
  }
  ctx.run_project_turn(project_id, run_id)
}
