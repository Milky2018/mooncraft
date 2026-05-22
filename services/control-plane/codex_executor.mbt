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
struct AgentRuntimeConfig {
  runtime_id : String
  runtime_name : String
  agent_session_id : String
  runtime_session_id : String?
  protocol_version : Int
  image : String
  platform : String
  agent_cli : String
  provider : String
  model : String
  secrets : Array[ResolvedRuntimeSecret]
  container_home : String
  container_data_dir : String
  host_data_dir : String?
  send : Array[String]
}

///|
let default_codex_model = "gpt-5.5"

///|
struct RunArtifacts {
  project_id : String
  run_id : String
  dir : String
  prompt_path : String
  runtime_context_path : String
  result_path : String
  last_message_path : String
  agent_log_path : String
  validation_log_path : String
}

///|
struct RuntimeContext {
  protocol_version : Int
  project_id : String
  run_id : String
  agent_session_id : String
  runtime_session_id : String?
  prompt_file : String
  workspace : String
  artifacts : String
  runtime_id : String
  runtime_name : String
  agent : String
  model : String
  provider : String
} derive(ToJson)

///|
struct RuntimeResult {
  runtime_session_id : String
  last_message : String?
} derive(FromJson)

///|
struct PreviewAuditResult {
  enabled : Bool
  passed : Bool
  message : String
}

///|
struct AgentExecutionResult {
  summary : String
  thread_id : String
  artifacts : RunArtifacts
}

///|
fn smoke_codex_enabled() -> Bool {
  match @env.get_env_var("MOONCRAFT_CODEX_FAKE_MODE") {
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
    project_id,
    run_id,
    dir,
    prompt_path: dir + "/prompt.txt",
    runtime_context_path: dir + "/runtime_context.json",
    result_path: dir + "/result.json",
    last_message_path: dir + "/last_message.txt",
    agent_log_path: dir + "/agent.log",
    validation_log_path: dir + "/validation.log",
  }
}

///|
fn agent_container_workspace_dir() -> String {
  "/workspace"
}

///|
fn agent_container_artifacts_dir() -> String {
  "/artifacts"
}

///|
fn agent_runtime_container_name(project_id : String, run_id : String) -> String {
  "mooncraft-" + project_id + "-" + run_id
}

///|
fn trim_mount_path(path : String) -> String {
  let mut value = path.trim().to_owned()
  while value.length() > 1 && value.has_suffix("/") {
    value = value[:value.length() - 1].to_owned()
  }
  value
}

///|
fn configured_host_data_dir(root : String) -> Result[String?, String] {
  let host_data_dir = match @env.get_env_var("MOONCRAFT_HOST_DATA_DIR") {
    Some(value) if value.trim() != "" => Some(trim_mount_path(value))
    _ => None
  }
  match host_data_dir {
    Some(path) =>
      if !path.has_prefix("/") {
        Err(
          "MOONCRAFT_HOST_DATA_DIR must be an absolute host path so Docker bind mounts resolve correctly.",
        )
      } else {
        Ok(Some(path))
      }
    None =>
      if trim_mount_path(root) == "/app" {
        Err(
          "MOONCRAFT_HOST_DATA_DIR must be set when MoonCraft runs in Docker. It must point to the host directory bind-mounted as /app/data.",
        )
      } else {
        Ok(None)
      }
  }
}

///|
fn docker_bind_source(config : AgentRuntimeConfig, path : String) -> String {
  match config.host_data_dir {
    Some(host_data_dir) => {
      let container_data_dir = trim_mount_path(config.container_data_dir)
      let source = trim_mount_path(path)
      if source == container_data_dir {
        host_data_dir
      } else {
        let prefix = container_data_dir + "/"
        if source.has_prefix(prefix) {
          host_data_dir + source[container_data_dir.length():].to_owned()
        } else {
          source
        }
      }
    }
    None => path
  }
}

///|
fn docker_env_value(value : String) -> String {
  value.replace_all(old="\r", new="").replace_all(old="\n", new="")
}

///|
fn docker_env_file_path(artifacts : RunArtifacts) -> String {
  artifacts.dir + "/agent.env"
}

///|
fn docker_env_file_content(config : AgentRuntimeConfig) -> String {
  let mut content = "HOME=" +
    docker_env_value(config.container_home) +
    "\n" +
    "MOONCRAFT_AI_PROVIDER=" +
    docker_env_value(config.provider) +
    "\n" +
    "MOONCRAFT_AGENT_CLI=" +
    docker_env_value(config.agent_cli) +
    "\n" +
    "MOONCRAFT_AI_MODEL=" +
    docker_env_value(config.model) +
    "\n"
  for secret in config.secrets {
    match secret.env {
      Some(env) =>
        content = content +
          docker_env_value(env) +
          "=" +
          docker_env_value(secret.value) +
          "\n"
      None => ()
    }
  }
  content
}

///|
fn write_docker_env_file(
  config : AgentRuntimeConfig,
  artifacts : RunArtifacts,
) -> String {
  let path = docker_env_file_path(artifacts)
  safe_write_string(path, docker_env_file_content(config))
  path
}

///|
fn remove_docker_env_file(path : String) -> Unit {
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
fn materialize_runtime_file_secrets(
  config : AgentRuntimeConfig,
  agent_home_path : String?,
) -> Result[Unit, String] {
  for secret in config.secrets {
    match secret.file {
      Some(file) => {
        let home = match agent_home_path {
          Some(path) => path
          None =>
            return Err(
              "Runtime file secrets require a mounted agent home directory.",
            )
        }
        let relative_path = match validate_runtime_secret_file_path(file) {
          Ok(path) => path
          Err(message) => return Err(message)
        }
        let target = home + "/" + relative_path
        ensure_dir(parent_dir(target))
        @fs.write_string_to_file(target, secret.value) catch {
          err => return Err("Runtime secret file could not be written: \{err}")
        }
        ignore(shell_status("chmod 600 " + shell_quote(target)))
      }
      None => ()
    }
  }
  Ok(())
}

///|
fn write_runtime_context(
  config : AgentRuntimeConfig,
  project : @sdk.ProjectDetail,
  artifacts : RunArtifacts,
  prompt : String,
) -> Unit {
  safe_write_string(artifacts.prompt_path, prompt)
  let context : RuntimeContext = {
    protocol_version: config.protocol_version,
    project_id: project.id,
    run_id: artifacts.run_id,
    agent_session_id: config.agent_session_id,
    runtime_session_id: config.runtime_session_id,
    prompt_file: agent_container_artifacts_dir() + "/prompt.txt",
    workspace: agent_container_workspace_dir(),
    artifacts: agent_container_artifacts_dir(),
    runtime_id: config.runtime_id,
    runtime_name: config.runtime_name,
    agent: config.agent_cli,
    model: config.model,
    provider: config.provider,
  }
  safe_write_string(
    artifacts.runtime_context_path,
    context.to_json().stringify(),
  )
}

///|
fn runtime_command_arg(
  config : AgentRuntimeConfig,
  artifacts : RunArtifacts,
  value : String,
) -> String {
  match value {
    "$prompt_file" => agent_container_artifacts_dir() + "/prompt.txt"
    "$runtime_context" =>
      agent_container_artifacts_dir() + "/runtime_context.json"
    "$result_file" => agent_container_artifacts_dir() + "/result.json"
    "$agent_session_id" => config.agent_session_id
    "$runtime_session_id" => config.runtime_session_id.unwrap_or("")
    "$workspace" => agent_container_workspace_dir()
    "$artifacts" => agent_container_artifacts_dir()
    "$project_id" => artifacts.project_id
    "$run_id" => artifacts.run_id
    "$model" => config.model
    _ => value
  }
}

///|
fn runtime_send_command(
  config : AgentRuntimeConfig,
  artifacts : RunArtifacts,
) -> Array[String] {
  config.send.map(fn(value) { runtime_command_arg(config, artifacts, value) })
}

///|
fn read_runtime_result(
  artifacts : RunArtifacts,
) -> Result[RuntimeResult, String] {
  if !@fs.path_exists(artifacts.result_path) {
    return Err("Runtime did not write /artifacts/result.json.")
  }
  let text = safe_read_string_or(artifacts.result_path, "")
  let parsed = @json.parse(text) catch {
    _ => return Err("Runtime result.json is not valid JSON.")
  }
  let result : RuntimeResult = @json.from_json(parsed) catch {
    _ => return Err("Runtime result.json does not match the expected shape.")
  }
  if result.runtime_session_id.trim() == "" {
    return Err("Runtime result.json did not include runtime_session_id.")
  }
  Ok({
    runtime_session_id: result.runtime_session_id.trim().to_owned(),
    last_message: result.last_message,
  })
}

///|
fn normalize_docker_architecture(
  architecture : String,
) -> Result[String, String] {
  let normalized = architecture.trim().to_lower()
  if normalized == "amd64" || normalized == "x86_64" {
    Ok("linux/amd64")
  } else if normalized == "arm64" || normalized == "aarch64" {
    Ok("linux/arm64")
  } else {
    Err(
      "Unsupported Docker host architecture '\{architecture.trim()}'. MoonCraft supports only linux/amd64 and linux/arm64 agent runtime containers.",
    )
  }
}

///|
async fn detect_docker_platform(
  root : String,
) -> Result[String, String] noraise {
  let result = try
    @process.collect_output_merged(
      "docker",
      ["info", "--format", "{{.Architecture}}"],
      cwd=root,
    )
  catch {
    err => return Err("Docker host architecture could not be detected: \{err}")
  } noraise {
    value => value
  }
  let (exit_code, output) = result
  let text = output.text() catch { _ => "" }
  if exit_code != 0 {
    return Err(
      "Docker host architecture could not be detected. `docker info` exited with code \{exit_code}: \{tail_text(text, 600)}",
    )
  }
  normalize_docker_architecture(text)
}

///|
async fn AgentRuntimeConfig::load(
  root : String,
  settings : AiRuntimeSettings,
) -> Result[AgentRuntimeConfig, String] noraise {
  let agent_session_id = settings.agent_session_id.trim().to_owned()
  if agent_session_id == "" {
    return Err("Project Runtime agent session id is missing.")
  }
  let platform = match detect_docker_platform(root) {
    Ok(platform) => platform
    Err(message) => return Err(message)
  }
  let host_data_dir = match configured_host_data_dir(root) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  Ok({
    runtime_id: settings.runtime_id,
    runtime_name: settings.runtime_name,
    agent_session_id,
    runtime_session_id: settings.runtime_session_id,
    protocol_version: settings.runtime_spec.protocol_version,
    image: settings.runtime_spec.image,
    platform,
    agent_cli: settings.runtime_spec.agent,
    provider: settings.runtime_spec.provider,
    model: settings.runtime_spec.model,
    secrets: settings.secrets,
    container_home: settings.runtime_spec.container_home,
    container_data_dir: trim_mount_path(root) + "/data",
    host_data_dir,
    send: settings.runtime_spec.send,
  })
}

///|
fn prepare_agent_mount_path(path : String) -> Unit {
  ensure_dir(path)
  ignore(shell_status("chmod -R a+rwX " + shell_quote(path)))
}

///|
fn prepare_agent_mounts(
  workspace_path : String,
  agent_home_path : String?,
  artifacts : RunArtifacts,
) -> Unit {
  match agent_home_path {
    Some(path) => prepare_agent_mount_path(path)
    None => ()
  }
  prepare_agent_mount_path(workspace_path)
  prepare_agent_mount_path(artifacts.dir)
}

///|
fn bootstrap_prompt(user_message : String) -> String {
  user_message
}

///|
fn followup_prompt(user_message : String) -> String {
  user_message
}

///|
fn recovery_prompt(
  initial_project_prompt : String,
  user_message : String,
) -> String {
  ignore(initial_project_prompt)
  user_message
}

///|
fn preview_setup_repair_prompt() -> String {
  (
    #|MoonCraft preview startup failed. Repair the existing app so it satisfies the MoonCraft generated-app runtime contract.
    #|
    #|Use the runtime instructions for the exact contract. Preserve the user's app behavior except for changes required to make `mooncraft-preview.sh` start and pass HTTP health checks.
  )
}

///|
fn preview_audit_repair_prompt(
  audit_error : String,
  initial_project_prompt : String,
  user_prompt : String,
) -> String {
  (
    #|MoonCraft browser preview audit failed after the preview passed HTTP health checks.
    #|
    #|This is a mandatory repair task.
    #|
    #|Browser audit failure:
    #|
  ) +
  audit_error +
  (
    #|
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
  user_prompt +
  (
    #|
    #|
    #|Repair the existing workspace so the user-facing preview at `/` loads in a browser without page errors or console errors. Preserve the requested app behavior and keep the MoonCraft runtime contract intact.
  )
}

///|
fn default_success_summary() -> String {
  successful_preview_assistant_message()
}

///|
fn successful_preview_assistant_message() -> String {
  "The app is updated and the preview is ready."
}

///|
fn preview_refresh_failed_assistant_message() -> String {
  "The app was updated, but the live preview could not be refreshed. Send another message to retry the preview."
}

///|
fn preview_setup_repair_failed_assistant_message() -> String {
  "The app was generated, but the live preview could not be started. MoonCraft tried to repair the preview setup but could not finish it. Send another message to retry the preview."
}

///|
fn preview_audit_repair_failed_assistant_message() -> String {
  "The app was generated, but the browser preview still reports runtime errors after repair. Send another message to retry the preview."
}

///|
fn default_failure_assistant_message() -> String {
  "The update failed before the preview could be refreshed."
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
    "Some required MoonBit packages could not be fetched right now, so the preview could not be refreshed. This is usually temporary. Retry the update in a few minutes."
  } else {
    fallback
  }
}

///|
fn ai_provider_temporarily_overloaded(output : String) -> Bool {
  let lower = output.to_lower()
  lower.contains("experiencing high demand") ||
  lower.contains("temporarily overloaded") ||
  lower.contains("provider is overloaded") ||
  (lower.contains("high demand") && lower.contains("temporary"))
}

///|
fn ai_quota_or_capacity_limited(output : String) -> Bool {
  let lower = output.to_lower()
  lower.contains("insufficient credits") ||
  lower.contains("requires more credits") ||
  lower.contains("quota") ||
  lower.contains("monthly limit") ||
  lower.contains("key limit exceeded") ||
  lower.contains("credit limit")
}

///|
fn mooncraft_capacity_assistant_message() -> String {
  "MoonCraft is under heavy load. Please try again later or contact an administrator."
}

///|
fn ai_builder_failure_assistant_message(
  model : String,
  output : String,
  fallback : String,
) -> String {
  ignore(model)
  if ai_provider_temporarily_overloaded(output) ||
    ai_quota_or_capacity_limited(output) {
    mooncraft_capacity_assistant_message()
  } else {
    dependency_fetch_failure_assistant_message(output, fallback)
  }
}

///|
fn trim_or_default(text : String, fallback : String) -> String {
  let normalized = text.trim(chars="\n\r ").to_owned()
  if normalized == "" {
    fallback
  } else {
    normalized
  }
}

///|
fn tail_text(text : String, limit : Int) -> String {
  let normalized = text.trim(chars="\n\r ").to_owned()
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
fn prompt_section_after(prompt : String, marker : String) -> String? {
  match prompt.find(marker) {
    Some(index) =>
      Some(
        prompt[index + marker.length():]
        .to_owned()
        .trim(chars="\n\r ")
        .to_owned(),
      )
    None => None
  }
}

///|
fn fake_codex_user_request(prompt : String) -> String {
  let markers = [
    "Latest user request:\n\n", "Latest user request:\n", "User's requirement:\n\n",
    "User's requirement:\n", "Original project requirement:\n\n", "Original project requirement:\n",
  ]
  for marker in markers {
    match prompt_section_after(prompt, marker) {
      Some(request) if request != "" => return request
      _ => ()
    }
  }
  prompt
}

///|
fn fake_codex_forced_failure(prompt : String) -> String? {
  match @env.get_env_var("MOONCRAFT_CODEX_FAKE_FAIL_CONTAINS") {
    Some(value) if value.trim() != "" => {
      let needle = value.trim().to_owned()
      if fake_codex_user_request(prompt).contains(needle) {
        Some("Local builder forced failure for Playwright coverage.")
      } else {
        None
      }
    }
    _ => None
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
    let line = raw_line.to_owned()
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
  let trimmed = line.trim().to_owned()
  if trimmed == "" || !trimmed.has_prefix("{") {
    return None
  }
  if trimmed.contains("\"type\":\"thread.started\"") {
    Some(("status", "Started the builder session."))
  } else if trimmed.contains("\"type\":\"turn.started\"") {
    Some(("status", "Planning the change."))
  } else if trimmed.contains("\"type\":\"turn.completed\"") {
    Some(("status", "Builder session ended."))
  } else if trimmed.contains("\"type\":\"turn.failed\"") {
    Some(("status", "The app update failed."))
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
      Some(("status", "A workspace check failed; the builder is fixing it."))
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
fn fake_codex_state_dir(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/fake-codex"
}

///|
fn fake_codex_resume_reset_marker(root : String, project_id : String) -> String {
  fake_codex_state_dir(root, project_id) + "/resume-reset-once"
}

///|
fn fake_codex_preview_html(root : String) -> String {
  web_public_string(
    root, "control-plane-assets/smoke-preview/index.html", "MoonCraft smoke preview",
  )
}

///|
fn fake_codex_update_workspace(
  root : String,
  workspace_path : String,
  prompt : String,
) -> Result[String, String] {
  let normalized = trim_or_default(
    fake_codex_user_request(prompt),
    "MoonCraft update",
  )
  let async_version = "0.18.1"
  let mocket_version = "0.7.1"
  let x_version = "0.4.43"
  let files : Array[(String, String)] = [
    (
      "/moon.mod.json",
      (
        #|{
        #|  "name": "mooncraft/smoke-app",
        #|  "version": "0.1.0",
        #|  "preferred-target": "native",
        #|  "deps": {
      ) +
      "    \"moonbitlang/async\": \"\{async_version}\",\n" +
      "    \"oboard/mocket\": \"\{mocket_version}\",\n" +
      "    \"moonbitlang/x\": \"\{x_version}\"\n" +
      (
        #|  },
        #|  "readme": "README.md",
        #|  "repository": "",
        #|  "license": "Apache-2.0",
        #|  "keywords": [],
        #|  "description": "MoonCraft smoke app"
        #|}
      ),
    ),
    (
      "/moon.pkg",
      (
        #|import {
        #|  "moonbitlang/async",
        #|  "oboard/mocket",
        #|  "moonbitlang/core/env",
        #|  "moonbitlang/core/string",
        #|  "moonbitlang/x/fs",
        #|}
        #|
        #|options(
        #|  "is-main": true,
        #|)
        #|
        #|supported_targets = "native"
      ),
    ),
    ("/index.html", fake_codex_preview_html(root)),
    (
      "/main.mbt",
      (
        #|///|
        #|fn app_page_html() -> String {
        #|  @fs.read_file_to_string("index.html") catch {
        #|    _ => "MoonCraft smoke preview"
        #|  }
        #|}
        #|
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
        #|  let app = @mocket.new()
        #|  app.get("/api/health", _ => @mocket.HttpResponse::new(OK, headers={ "Content-Type": "application/json" }).body("{\"ok\":true}"))
        #|  app.get("/", _ => @mocket.HttpResponse::new(OK, headers={ "Content-Type": "text/html; charset=utf-8" }).body(app_page_html()))
        #|  app.listen("0.0.0.0:\{port}")
        #|}
      ),
    ),
    (
      "/mooncraft-preview.sh",
      (
        #|#!/bin/sh
        #|set -eu
        #|port="${1:-4300}"
        #|moon build
        #|exe="$(find ./_build -name '*.exe' -type f ! -path '*.dSYM/*' ! -path '*/cmd/*' | head -n 1)"
        #|exec "$exe" "$port"
      ),
    ),
    (
      "/main_wbtest.mbt",
      (
        #|///|
        #|test "page includes smoke title" {
        #|  assert_true(app_page_html().contains("MoonCraft smoke preview"))
        #|}
      ),
    ),
    ("/README.md", "# MoonCraft Smoke App\n\n" + normalized + "\n"),
  ]
  for file in files {
    match scaffold_write_file(workspace_path + file.0, file.1) {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
  }
  Ok(successful_preview_assistant_message())
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
    return Err("The local builder command was malformed.")
  }
  let is_resume = codex_command_is_resume(command)
  let prompt = command[command.length() - 1]
  ensure_dir(fake_codex_state_dir(root, project.id))
  match fake_codex_forced_failure(prompt) {
    Some(message) => return Ok((1, message, None))
    None => ignore(())
  }
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
    let summary = match
      fake_codex_update_workspace(root, workspace_path, prompt) {
      Ok(summary) => summary
      Err(message) => return Err(message)
    }
    Ok((0, "{\"type\":\"turn.completed\"}", Some(summary)))
  } else {
    let thread_id = next_id("fake-thread")
    let summary = match
      fake_codex_update_workspace(root, workspace_path, prompt) {
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
    } else if command.length() > 0 &&
      command[0] == "claude" &&
      index > 0 &&
      command[index - 1] == "-p" {
      "<prompt>"
    } else if command.length() > 0 &&
      command[0] == "kimi" &&
      index > 0 &&
      command[index - 1] == "--prompt" {
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
    codex_log_path: artifacts.map(fn(artifacts) { artifacts.agent_log_path }),
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
  config : AgentRuntimeConfig,
  env_file_path : String,
  workspace_path : String,
  agent_home_path : String?,
  artifacts : RunArtifacts,
  container_command : Array[String],
) -> Array[String] {
  let args : Array[String] = ["run", "--rm"]
  args.push("--name")
  args.push(
    agent_runtime_container_name(artifacts.project_id, artifacts.run_id),
  )
  args.push("--platform")
  args.push(config.platform)
  args.push("--env-file")
  args.push(env_file_path)
  match agent_home_path {
    Some(path) => {
      args.push("-v")
      args.push(docker_bind_source(config, path) + ":" + config.container_home)
    }
    None => ()
  }
  args.push("-v")
  args.push(
    docker_bind_source(config, workspace_path) +
    ":" +
    agent_container_workspace_dir(),
  )
  args.push("-v")
  args.push(
    docker_bind_source(config, artifacts.dir) +
    ":" +
    agent_container_artifacts_dir(),
  )
  args.push("-w")
  args.push(agent_container_workspace_dir())
  args.push(config.image)
  for part in agent_runtime_entry_command(container_command) {
    args.push(part)
  }
  args
}

///|
fn agent_runtime_entry_command(
  container_command : Array[String],
) -> Array[String] {
  let script_lines : Array[String] = ["set -e"]
  script_lines.push(
    "if [ \"${1:-}\" = \"mooncraft-agent-doctor\" ]; then exec \"$@\"; fi",
  )
  for command in user_project_fetch_commands() {
    script_lines.push(command)
  }
  script_lines.push(
    "if [ \"${1:-}\" = \"claude\" ]; then chmod -R a+rwX /workspace /artifacts \"${HOME:-/home/mooncraft}\" >/dev/null 2>&1 || true; exec runuser -u mooncraft -- env HOME=\"${HOME:-/home/mooncraft}\" \"$@\"; fi",
  )
  script_lines.push("exec \"$@\"")
  let wrapped : Array[String] = [
    "sh",
    "-c",
    script_lines.join("\n"),
    "mooncraft-agent",
  ]
  for part in container_command {
    wrapped.push(part)
  }
  wrapped
}

///|
async fn collect_docker_output(
  root : String,
  config : AgentRuntimeConfig,
  workspace_path : String,
  agent_home_path : String?,
  artifacts : RunArtifacts,
  container_command : Array[String],
) -> Result[(Int, String), String] noraise {
  let env_file_path = write_docker_env_file(config, artifacts)
  prepare_agent_mounts(workspace_path, agent_home_path, artifacts)
  match materialize_runtime_file_secrets(config, agent_home_path) {
    Ok(_) => ignore(())
    Err(message) => {
      remove_docker_env_file(env_file_path)
      return Err(message)
    }
  }
  let docker_args = docker_command_args(
    config, env_file_path, workspace_path, agent_home_path, artifacts, container_command,
  )
  let result = try
    @process.collect_output_merged("docker", docker_args, cwd=root)
  catch {
    err => {
      remove_docker_env_file(env_file_path)
      return Err("The AI builder command could not be started: \{err}")
    }
  } noraise {
    value => value
  }
  remove_docker_env_file(env_file_path)
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
  config : AgentRuntimeConfig,
  workspace_path : String,
  agent_home_path : String?,
  artifacts : RunArtifacts,
  container_command : Array[String],
) -> Result[(Int, String), String] noraise {
  let env_file_path = write_docker_env_file(config, artifacts)
  prepare_agent_mounts(workspace_path, agent_home_path, artifacts)
  match materialize_runtime_file_secrets(config, agent_home_path) {
    Ok(_) => ignore(())
    Err(message) => {
      remove_docker_env_file(env_file_path)
      return Err(message)
    }
  }
  let docker_args = docker_command_args(
    config, env_file_path, workspace_path, agent_home_path, artifacts, container_command,
  )
  let pipe = @process.read_from_process() catch {
    err => {
      remove_docker_env_file(env_file_path)
      return Err("The AI builder output pipe could not be opened: \{err}")
    }
  }
  let (reader, writer) = pipe
  let chunks : Array[String] = []
  let exit_code_ref : Ref[Int] = @ref.new(-1)
  store.append_run_event(
    project_id, run_id, "status", "Starting the builder session.",
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
    err => {
      remove_docker_env_file(env_file_path)
      return Err("The AI builder command failed while streaming output: \{err}")
    }
  } noraise {
    value => value
  }
  remove_docker_env_file(env_file_path)
  ignore(group_result)
  Ok((exit_code_ref.val, chunks.join("")))
}

///|
async fn collect_agent_command_output(
  store : Store,
  run_id : String,
  root : String,
  config : AgentRuntimeConfig?,
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
      "Running local builder.",
    )
    for raw_line in result.1.replace_all(old="\r\n", new="\n").split("\n") {
      let line = raw_line.to_owned()
      if line != "" {
        append_codex_display_event(store, project.id, run_id, line)
      }
    }
    Ok(result)
  } else {
    match config {
      Some(config) => {
        let agent_home_path = Some(
          project_runtime_agent_home(root, project.id, config.agent_session_id),
        )
        let result = match
          stream_docker_output(
            store,
            root,
            project.id,
            run_id,
            config,
            workspace_path,
            agent_home_path,
            artifacts,
            command,
          ) {
          Ok(result) => result
          Err(message) => return Err(message)
        }
        Ok((result.0, result.1, None))
      }
      None => Err("MoonCraft's app builder is temporarily unavailable.")
    }
  }
}

///|
fn agent_runtime_doctor_command() -> Array[String] {
  ["mooncraft-agent-doctor"]
}

///|
async fn run_agent_runtime_doctor(
  root : String,
  config : AgentRuntimeConfig?,
  project : @sdk.ProjectDetail,
  workspace_path : String,
  artifacts : RunArtifacts,
  thread_id : String?,
) -> Result[Unit, AgentTurnFailure] noraise {
  if smoke_codex_enabled() {
    return Ok(())
  }
  let config = match config {
    Some(config) => config
    None =>
      return Err(
        codex_failure_with_debug(
          "The app builder runtime is not available.",
          "MoonCraft's app builder is temporarily unavailable.",
          thread_id,
          Some(
            failure_debug("Agent runtime doctor", None, None, Some(artifacts)),
          ),
        ),
      )
  }
  let command = agent_runtime_doctor_command()
  let agent_home_path = Some(
    project_runtime_agent_home(root, project.id, config.agent_session_id),
  )
  let result = match
    collect_docker_output(
      root, config, workspace_path, agent_home_path, artifacts, command,
    ) {
    Ok(result) => result
    Err(message) =>
      return Err(
        codex_failure_with_debug(
          "The app builder runtime could not be checked.",
          message,
          thread_id,
          Some(
            failure_debug(
              "Agent runtime doctor",
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
    artifacts.agent_log_path,
    "agent runtime doctor",
    command,
    exit_code,
    output,
  )
  if exit_code != 0 {
    return Err(
      codex_failure_with_debug(
        "The app builder runtime is not ready. Please retry after the server is updated.",
        stage_failure_message(
          "Agent runtime doctor",
          exit_code,
          artifacts.agent_log_path,
          output,
        ),
        thread_id,
        Some(
          failure_debug(
            "Agent runtime doctor",
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
fn codex_exec_command(model : String, user_prompt : String) -> Array[String] {
  codex_exec_raw_command(model, bootstrap_prompt(user_prompt))
}

///|
fn codex_exec_raw_command(model : String, prompt : String) -> Array[String] {
  [
    "codex",
    "exec",
    "--model",
    model,
    "--skip-git-repo-check",
    "--json",
    "--output-last-message",
    agent_container_artifacts_dir() + "/last_message.txt",
    "--dangerously-bypass-approvals-and-sandbox",
    prompt,
  ]
}

///|
fn codex_resume_raw_command(
  thread_id : String,
  prompt : String,
) -> Array[String] {
  ["codex", "resume", thread_id, prompt]
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
  config : AgentRuntimeConfig?,
  project : @sdk.ProjectDetail,
  initial_project_prompt : String,
  workspace_path : String,
  run_id : String,
  user_prompt : String,
  reset_logs? : Bool = true,
  raw_prompt? : Bool = false,
  resume_existing? : Bool = true,
) -> Result[AgentExecutionResult, AgentTurnFailure] noraise {
  let artifacts = RunArtifacts::new(root, project.id, run_id)
  safe_write_string(artifacts.last_message_path, "")
  if reset_logs {
    safe_write_string(artifacts.agent_log_path, "")
  }
  let thread_id_before = match project.runtime_session_id {
    Some(value) => Some(value)
    None => project.codex_thread_id
  }
  let model = match config {
    Some(config) => config.model
    None => default_codex_model
  }
  let prompt = if raw_prompt {
    user_prompt
  } else if thread_id_before is Some(_) && resume_existing {
    followup_prompt(user_prompt)
  } else {
    bootstrap_prompt(user_prompt)
  }
  let command = match config {
    Some(config) => {
      write_runtime_context(config, project, artifacts, prompt)
      runtime_send_command(config, artifacts)
    }
    None =>
      match thread_id_before {
        Some(thread_id) if resume_existing && !raw_prompt =>
          codex_resume_raw_command(thread_id, prompt)
        _ => codex_exec_raw_command(model, prompt)
      }
  }
  match
    run_agent_runtime_doctor(
      root, config, project, workspace_path, artifacts, thread_id_before,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  let mut active_command = command
  let codex_result = match
    collect_agent_command_output(
      store, run_id, root, config, project, workspace_path, artifacts, command,
    ) {
    Ok(result) => result
    Err(message) =>
      return Err(
        codex_failure_with_debug(
          "The AI builder could not be started for that update.",
          message,
          thread_id_before,
          Some(
            failure_debug(
              "AI builder startup",
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
    artifacts.agent_log_path,
    "runtime send",
    active_command,
    exit_code,
    output,
  )
  let mut thread_id = thread_id_before
  if config is None && thread_id_before is None {
    let thread_id = match extract_thread_id(output) {
      Some(thread_id) => thread_id
      None =>
        return Err(
          codex_failure_with_debug(
            ai_builder_failure_assistant_message(
              model,
              output,
              default_failure_assistant_message(),
            ),
            stage_failure_message(
              "AI builder session startup",
              exit_code,
              artifacts.agent_log_path,
              output,
            ),
            None,
            Some(
              failure_debug(
                "AI builder session startup",
                Some(active_command),
                Some(exit_code),
                Some(artifacts),
              ),
            ),
          ),
        )
    }
    let summary = trim_or_default(
      safe_read_string_or(artifacts.last_message_path, ""),
      default_success_summary(),
    )
    return Ok({ summary, thread_id, artifacts })
  }
  if config is None &&
    !raw_prompt &&
    thread_id_before is Some(_) &&
    exit_code != 0 &&
    resume_session_missing(output) {
    let recovery_command = codex_exec_command(
      model,
      recovery_prompt(initial_project_prompt, user_prompt),
    )
    let recovery_result = match
      collect_agent_command_output(
        store, run_id, root, config, project, workspace_path, artifacts, recovery_command,
      ) {
      Ok(result) => result
      Err(message) =>
        return Err(
          codex_failure_with_debug(
            "The builder session could not be recovered for that update.",
            message,
            thread_id_before,
            Some(
              failure_debug(
                "AI builder session recovery startup",
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
      artifacts.agent_log_path,
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
            ai_builder_failure_assistant_message(
              model,
              recovery_output,
              default_failure_assistant_message(),
            ),
            stage_failure_message(
              "AI builder session recovery",
              recovery_exit_code,
              artifacts.agent_log_path,
              recovery_output,
            ),
            None,
            Some(
              failure_debug(
                "AI builder session recovery",
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
  if config is None {
    let thread_id = match thread_id {
      Some(thread_id) => thread_id
      None =>
        return Err(
          codex_failure_with_debug(
            default_failure_assistant_message(),
            "The builder session could not be restored for this run.",
            None,
            Some(
              failure_debug(
                "AI builder session startup",
                Some(active_command),
                Some(exit_code),
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
          ai_builder_failure_assistant_message(
            model,
            output,
            default_failure_assistant_message(),
          ),
          stage_failure_message(
            "AI builder execution",
            exit_code,
            artifacts.agent_log_path,
            output,
          ),
          Some(thread_id),
          Some(
            failure_debug(
              "AI builder execution",
              Some(active_command),
              Some(exit_code),
              Some(artifacts),
            ),
          ),
        ),
      )
    }
    return Ok({ summary, thread_id, artifacts })
  }
  if exit_code != 0 {
    return Err(
      codex_failure_with_debug(
        ai_builder_failure_assistant_message(
          model,
          output,
          default_failure_assistant_message(),
        ),
        stage_failure_message(
          "AI builder execution",
          exit_code,
          artifacts.agent_log_path,
          output,
        ),
        thread_id_before,
        Some(
          failure_debug(
            "AI builder execution",
            Some(active_command),
            Some(exit_code),
            Some(artifacts),
          ),
        ),
      ),
    )
  }
  let runtime_result = match read_runtime_result(artifacts) {
    Ok(result) => result
    Err(message) =>
      return Err(
        codex_failure_with_debug(
          default_failure_assistant_message(),
          message,
          thread_id_before,
          Some(
            failure_debug(
              "AI builder result",
              Some(active_command),
              Some(exit_code),
              Some(artifacts),
            ),
          ),
        ),
      )
  }
  let summary = match runtime_result.last_message {
    Some(message) => trim_or_default(message, default_success_summary())
    None =>
      match fake_summary {
        Some(summary) => trim_or_default(summary, default_success_summary())
        None =>
          trim_or_default(
            safe_read_string_or(artifacts.last_message_path, ""),
            default_success_summary(),
          )
      }
  }
  Ok({ summary, thread_id: runtime_result.runtime_session_id, artifacts })
}

///|
fn preview_audit_script_path(root : String) -> String {
  root + "/scripts/preview_audit.mjs"
}

///|
fn preview_audit_log_path(
  root : String,
  project_id : String,
  run_id : String,
) -> String {
  RunArtifacts::new(root, project_id, run_id).dir + "/preview-audit.log"
}

///|
fn preview_audit_auto_available(root : String) -> Bool {
  @fs.path_exists(preview_audit_script_path(root)) &&
  (
    @fs.path_exists(root + "/node_modules/playwright/package.json") ||
    @fs.path_exists(root + "/node_modules/playwright-core/package.json")
  )
}

///|
fn preview_audit_enabled(root : String) -> Bool {
  match @env.get_env_var("MOONCRAFT_PREVIEW_AUDIT") {
    Some(value) => {
      let normalized = value.trim().to_lower()
      normalized != "" &&
      normalized != "0" &&
      normalized != "false" &&
      normalized != "off" &&
      normalized != "disabled"
    }
    None => preview_audit_auto_available(root)
  }
}

///|
fn preview_audit_repair_attempts() -> Int {
  match @env.get_env_var("MOONCRAFT_PREVIEW_AUDIT_REPAIR_ATTEMPTS") {
    Some(value) => {
      let attempts = @string.parse_int(value.trim().to_owned()) catch { _ => 2 }
      if attempts < 0 {
        0
      } else if attempts > 5 {
        5
      } else {
        attempts
      }
    }
    None => 2
  }
}

///|
fn preview_audit_target_url(preview : @sdk.PreviewTarget) -> String {
  "http://127.0.0.1:\{preview.port}/"
}

///|
fn preview_audit_command(
  root : String,
  preview : @sdk.PreviewTarget,
) -> Array[String] {
  ["node", preview_audit_script_path(root), preview_audit_target_url(preview)]
}

///|
async fn run_preview_audit(
  root : String,
  project_id : String,
  run_id : String,
  preview : @sdk.PreviewTarget,
) -> PreviewAuditResult noraise {
  if !preview_audit_enabled(root) {
    return { enabled: false, passed: true, message: "Preview audit skipped." }
  }
  let command = preview_audit_command(root, preview)
  let result = match
    collect_local_output(command[0], command_args(command), root) {
    Ok(result) => result
    Err(message) => (127, message)
  }
  let (exit_code, output) = result
  append_command_log(
    preview_audit_log_path(root, project_id, run_id),
    "Playwright preview audit",
    command,
    exit_code,
    output,
  )
  if exit_code == 0 {
    {
      enabled: true,
      passed: true,
      message: trim_or_default(output, "Preview audit passed."),
    }
  } else {
    {
      enabled: true,
      passed: false,
      message: trim_or_default(output, "The browser preview audit failed."),
    }
  }
}

///|
async fn persist_builder_workspace_snapshot(
  store : Store,
  root : String,
  project_id : String,
  workspace_path : String,
  thread_id : String,
  artifacts : RunArtifacts,
) -> Result[Unit, AgentTurnFailure] noraise {
  match snapshot_workspace(store, root, project_id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) =>
      Err(
        codex_failure_with_debug(
          "The workspace was updated, but saving the latest project snapshot failed.",
          message,
          Some(thread_id),
          Some(failure_debug("Workspace snapshot", None, None, Some(artifacts))),
        ),
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
  raw_prompt? : Bool = false,
  resume_existing? : Bool = true,
) -> Result[AgentTurnSuccess, AgentTurnFailure] noraise {
  let config = if smoke_codex_enabled() {
    None
  } else {
    let settings = match
      store.lease_ai_runtime_settings_for_project(project.id, run_id) {
      Ok(settings) => settings
      Err(message) =>
        return Err(
          codex_failure(
            "MoonCraft's app builder is temporarily unavailable. Please retry later.",
            message,
            project.codex_thread_id,
          ),
        )
    }
    match AgentRuntimeConfig::load(self.root, settings) {
      Ok(config) => Some(config)
      Err(message) =>
        return Err(
          codex_failure(
            "The app builder could not be started for that update.",
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
      raw_prompt~,
      resume_existing~,
    ) {
    Ok(result) => result
    Err(failure) => return Err(failure)
  }
  match
    persist_builder_workspace_snapshot(
      store,
      self.root,
      project.id,
      workspace_path,
      codex_result.thread_id,
      codex_result.artifacts,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  Ok({ summary: codex_result.summary, thread_id: Some(codex_result.thread_id) })
}

///|
async fn AppContext::finish_run_with_preview_audit(
  self : AppContext,
  project_id : String,
  run_id : String,
  workspace_path : String,
  initial_project_prompt : String,
  user_prompt : String,
  result : AgentTurnSuccess,
  preview : @sdk.PreviewTarget,
) -> Unit {
  let mut current_preview = preview
  let mut current_thread_id = result.thread_id
  let mut current_summary = result.summary
  let mut audit = run_preview_audit(
    self.root,
    project_id,
    run_id,
    current_preview,
  )
  if !audit.enabled || audit.passed {
    self.store.finish_run_success(
      project_id, run_id, current_summary, current_thread_id, current_preview,
    )
    return
  }
  let mut audit_error = audit.message
  for _ in 0..<preview_audit_repair_attempts() {
    self.store.append_run_event(
      project_id, run_id, "status", "Repairing browser preview errors.",
    )
    let repair_project = match self.store.get_project_detail(project_id) {
      Some(project) => project
      None => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The updated project workspace could not be loaded before preview audit repair.",
          current_thread_id,
        )
        return
      }
    }
    let repair_result = self.agent_gateway.run_turn(
      self.store,
      repair_project,
      initial_project_prompt,
      workspace_path,
      run_id,
      preview_audit_repair_prompt(
        audit_error, initial_project_prompt, user_prompt,
      ),
      raw_prompt=true,
      resume_existing=false,
    )
    let repair = match repair_result {
      Ok(repair) => repair
      Err(failure) => {
        self.store.finish_run_failure_with_debug(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit failed: " +
          audit_error +
          "\n\nPreview audit repair failed: " +
          failure.error_message,
          failure.thread_id,
          failure.failure_debug,
        )
        return
      }
    }
    current_thread_id = repair.thread_id
    current_summary = successful_preview_assistant_message()
    let repair_restore_result = restore_workspace_snapshot(
      self.store,
      self.root,
      project_id,
      workspace_path,
    )
    match repair_restore_result {
      Ok(_) => ignore(())
      Err(restore_message) => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit repair completed, but the saved snapshot could not be restored into the local cache: " +
          restore_message,
          current_thread_id,
        )
        return
      }
    }
    match current_thread_id {
      Some(thread_id) => self.store.set_project_thread_id(project_id, thread_id)
      None => ignore(())
    }
    let repaired_project = match self.store.get_project_detail(project_id) {
      Some(project) => project
      None => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The repaired project workspace could not be loaded.",
          current_thread_id,
        )
        return
      }
    }
    let repaired_preview = match
      self.previews.rebuild_and_restart(repaired_project) {
      Ok(preview) => preview
      Err(message) => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit repair completed, but the repaired preview could not be started: " +
          message,
          current_thread_id,
        )
        return
      }
    }
    current_preview = repaired_preview
    audit = run_preview_audit(self.root, project_id, run_id, current_preview)
    if !audit.enabled || audit.passed {
      self.store.finish_run_success(
        project_id, run_id, current_summary, current_thread_id, current_preview,
      )
      return
    }
    audit_error = audit.message
  }
  self.store.finish_run_failure(
    project_id,
    run_id,
    preview_audit_repair_failed_assistant_message(),
    "Preview audit failed: " + audit_error,
    current_thread_id,
  )
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
  let workspace_path = match
    restore_project_workspace_for_run(self.store, self.root, project_id) {
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
    workspace_path,
    run_id,
    prompt,
  )
  match agent_result {
    Ok(result) => {
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        workspace_path,
      )
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
            "The updated project workspace could not be loaded after the builder finished.",
            result.thread_id,
          )
          return
        }
      }
      match result.thread_id {
        Some(thread_id) =>
          ignore(
            self.store.set_project_runtime_session_id(project_id, thread_id),
          )
        None => ignore(())
      }
      let preview_result = self.previews.rebuild_and_restart(updated_project)
      match preview_result {
        Ok(preview) =>
          self.finish_run_with_preview_audit(
            project_id, run_id, workspace_path, initial_project_prompt, prompt, result,
            preview,
          )
        Err(message) =>
          if preview_error_needs_startup_repair(message) {
            self.store.append_run_event(
              project_id, run_id, "status", "Preparing the live preview.",
            )
            let repair_project = match
              self.store.get_project_detail(project_id) {
              Some(project) => project
              None => {
                self.store.finish_run_failure(
                  project_id,
                  run_id,
                  preview_setup_repair_failed_assistant_message(),
                  "The updated project workspace could not be loaded before preview repair.",
                  result.thread_id,
                )
                return
              }
            }
            let repair_result = self.agent_gateway.run_turn(
              self.store,
              repair_project,
              initial_project_prompt,
              workspace_path,
              run_id,
              preview_setup_repair_prompt(),
              raw_prompt=true,
              resume_existing=false,
            )
            match repair_result {
              Ok(repair) => {
                let repair_restore_result = restore_workspace_snapshot(
                  self.store,
                  self.root,
                  project_id,
                  workspace_path,
                )
                match repair_restore_result {
                  Ok(_) => ignore(())
                  Err(restore_message) => {
                    self.store.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      restore_message,
                      repair.thread_id,
                    )
                    return
                  }
                }
                match repair.thread_id {
                  Some(thread_id) =>
                    ignore(
                      self.store.set_project_runtime_session_id(
                        project_id, thread_id,
                      ),
                    )
                  None => ignore(())
                }
                let repaired_project = match
                  self.store.get_project_detail(project_id) {
                  Some(project) => project
                  None => {
                    self.store.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      "The repaired project workspace could not be loaded.",
                      repair.thread_id,
                    )
                    return
                  }
                }
                match self.previews.rebuild_and_restart(repaired_project) {
                  Ok(preview) =>
                    self.finish_run_with_preview_audit(
                      project_id,
                      run_id,
                      workspace_path,
                      initial_project_prompt,
                      prompt,
                      {
                        summary: successful_preview_assistant_message(),
                        thread_id: repair.thread_id,
                      },
                      preview,
                    )
                  Err(repair_preview_message) =>
                    self.store.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      message +
                      "\n\nPreview repair did not produce a usable preview: " +
                      repair_preview_message,
                      repair.thread_id,
                    )
                }
              }
              Err(failure) => {
                let repair_restore_result = restore_workspace_snapshot(
                  self.store,
                  self.root,
                  project_id,
                  workspace_path,
                )
                match repair_restore_result {
                  Ok(_) => ignore(())
                  Err(restore_message) =>
                    return self.store.finish_run_failure_with_debug(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      message +
                      "\n\nPreview repair failed: " +
                      failure.error_message +
                      "\n\nWorkspace restore failed: " +
                      restore_message,
                      failure.thread_id,
                      failure.failure_debug,
                    )
                }
                self.store.finish_run_failure_with_debug(
                  project_id,
                  run_id,
                  preview_setup_repair_failed_assistant_message(),
                  message +
                  "\n\nPreview repair failed: " +
                  failure.error_message,
                  failure.thread_id,
                  failure.failure_debug,
                )
              }
            }
          } else {
            self.store.finish_run_failure(
              project_id,
              run_id,
              preview_refresh_failed_assistant_message(),
              message,
              result.thread_id,
            )
          }
      }
    }
    Err(failure) => {
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        workspace_path,
      )
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
    Err(message) => abort("MoonCraft worker cannot start: " + message)
  }
  ctx.run_project_turn(project_id, run_id)
}
