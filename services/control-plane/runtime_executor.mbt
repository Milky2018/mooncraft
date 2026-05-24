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
  agent_session_id : String
  runtime_session_id : String?
  image : String
  platform : String
  agent_cli : String
  auth_kind : String
  model : String
  secret : ResolvedRuntimeSecret
  container_data_dir : String
  host_data_dir : String?
}

///|
let default_runtime_model = "gpt-5.5"

///|
struct RunArtifacts {
  project_id : String
  run_id : String
  dir : String
  prompt_path : String
  last_message_path : String
  agent_log_path : String
  validation_log_path : String
}

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
fn agent_container_home_dir() -> String {
  "/home/mooncraft"
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
  let mut content = "MOONCRAFT_AGENT_CLI=" +
    docker_env_value(config.agent_cli) +
    "\n" +
    "MOONCRAFT_AI_MODEL=" +
    docker_env_value(config.model) +
    "\n"
  match config.secret.env {
    Some(env) =>
      content = content +
        docker_env_value(env) +
        "=" +
        docker_env_value(config.secret.value) +
        "\n"
    None => ()
  }
  if config.auth_kind == "openrouter_api_key" {
    match config.agent_cli {
      "codex" =>
        content = content +
          "OPENROUTER_API_KEY=" +
          docker_env_value(config.secret.value) +
          "\n"
      "claude" =>
        content = content +
          "ANTHROPIC_BASE_URL=https://openrouter.ai/api\n" +
          "ANTHROPIC_AUTH_TOKEN=" +
          docker_env_value(config.secret.value) +
          "\n" +
          "ANTHROPIC_API_KEY=\n" +
          "ANTHROPIC_DEFAULT_OPUS_MODEL=" +
          docker_env_value(config.model) +
          "\n" +
          "ANTHROPIC_DEFAULT_SONNET_MODEL=" +
          docker_env_value(config.model) +
          "\n" +
          "ANTHROPIC_DEFAULT_HAIKU_MODEL=" +
          docker_env_value(config.model) +
          "\n" +
          "CLAUDE_CODE_SUBAGENT_MODEL=" +
          docker_env_value(config.model) +
          "\n" +
          "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1\n"
      _ => ()
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
  agent_home_path : String,
) -> Result[Unit, String] {
  match config.secret.file {
    Some(file) => {
      let relative_path = match validate_runtime_secret_file_path(file) {
        Ok(path) => path
        Err(message) => return Err(message)
      }
      let target = agent_home_path + "/" + relative_path
      ensure_dir(parent_dir(target))
      @fs.write_string_to_file(target, config.secret.value) catch {
        err => return Err("Runtime secret file could not be written: \{err}")
      }
      ignore(shell_status("chmod a+rw " + shell_quote(target)))
    }
    None => ()
  }
  Ok(())
}

///|
fn write_codex_openrouter_config(
  config : AgentRuntimeConfig,
  agent_home_path : String,
) -> Unit {
  ignore(config)
  let codex_home = agent_home_path + "/.codex"
  ensure_dir(codex_home)
  safe_write_string(
    codex_home + "/config.toml",
    (
      #|model_provider = "openrouter"
      #|
      #|[model_providers.openrouter]
      #|name = "OpenRouter"
      #|base_url = "https://openrouter.ai/api/v1"
      #|env_key = "OPENROUTER_API_KEY"
      #|wire_api = "responses"
    ),
  )
}

///|
fn prepare_agent_auth(
  config : AgentRuntimeConfig,
  agent_home_path : String,
) -> Result[Unit, String] {
  match materialize_runtime_file_secrets(config, agent_home_path) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  if config.agent_cli == "codex" && config.auth_kind == "openrouter_api_key" {
    write_codex_openrouter_config(config, agent_home_path)
  }
  Ok(())
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
    agent_session_id,
    runtime_session_id: settings.runtime_session_id,
    image: settings.runtime_spec.image,
    platform,
    agent_cli: settings.runtime_spec.agent,
    auth_kind: settings.runtime_spec.auth.kind,
    model: settings.runtime_spec.model,
    secret: settings.secret,
    container_data_dir: trim_mount_path(root) + "/data",
    host_data_dir,
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
fn agent_container_last_message_path() -> String {
  agent_container_artifacts_dir() + "/last_message.txt"
}

///|
fn agent_system_prompt(root : String) -> String {
  safe_read_string_or(
    root + "/docker/agent-runtime/mooncraft-agent-system.md",
    "",
  )
}

///|
fn codex_agent_command(
  config : AgentRuntimeConfig,
  prompt : String,
  resume_existing : Bool,
) -> Array[String] {
  let command : Array[String] = ["codex", "exec"]
  match config.runtime_session_id {
    Some(session_id) if resume_existing => {
      command.push("resume")
      command.push("--model")
      command.push(config.model)
      command.push("--skip-git-repo-check")
      command.push("--json")
      command.push("--output-last-message")
      command.push(agent_container_last_message_path())
      command.push("--dangerously-bypass-approvals-and-sandbox")
      command.push(session_id)
      command.push(prompt)
    }
    _ => {
      command.push("--model")
      command.push(config.model)
      command.push("--skip-git-repo-check")
      command.push("--json")
      command.push("--output-last-message")
      command.push(agent_container_last_message_path())
      command.push("--dangerously-bypass-approvals-and-sandbox")
      command.push(prompt)
    }
  }
  command
}

///|
fn claude_agent_command(
  root : String,
  config : AgentRuntimeConfig,
  prompt : String,
  resume_existing : Bool,
) -> Array[String] {
  let command : Array[String] = ["claude"]
  match config.runtime_session_id {
    Some(session_id) if resume_existing => {
      command.push("--resume")
      command.push(session_id)
    }
    _ => ()
  }
  command.push("--bare")
  command.push("-p")
  command.push(prompt)
  command.push("--model")
  command.push(config.model)
  command.push("--append-system-prompt")
  command.push(agent_system_prompt(root))
  command.push("--output-format")
  command.push("stream-json")
  command.push("--verbose")
  command.push("--dangerously-skip-permissions")
  command
}

///|
fn agent_command(
  root : String,
  config : AgentRuntimeConfig,
  prompt : String,
  resume_existing : Bool,
) -> Result[Array[String], String] {
  match config.agent_cli {
    "codex" => Ok(codex_agent_command(config, prompt, resume_existing))
    "claude" => Ok(claude_agent_command(root, config, prompt, resume_existing))
    _ => Err("Unsupported Runtime agent: \{config.agent_cli}")
  }
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
    #|MoonCraft preview audit failed after the preview passed HTTP health checks.
    #|
    #|This is a mandatory repair task.
    #|
    #|Preview audit failure:
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
    #|Repair the existing workspace so the user-facing preview at `/` returns a successful non-empty HTTP response through the MoonCraft preview proxy. Preserve the requested app behavior and keep the MoonCraft runtime contract intact.
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
  "The app was generated, but the preview audit still fails after repair. Send another message to retry the preview."
}

///|
fn default_failure_assistant_message() -> String {
  "The update failed before the preview could be refreshed."
}

///|
fn agent_runtime_timeout_output(output : String) -> Bool {
  output.contains("MoonCraft builder exceeded the configured runtime limit")
}

///|
fn agent_runtime_timeout_assistant_message() -> String {
  "The app builder took too long and was stopped. Retry the run or contact an administrator."
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
  if agent_runtime_timeout_output(output) {
    agent_runtime_timeout_assistant_message()
  } else if ai_provider_temporarily_overloaded(output) ||
    ai_quota_or_capacity_limited(output) {
    mooncraft_capacity_assistant_message()
  } else {
    fallback
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
fn extract_agent_session_id(events : String, agent : String) -> String? {
  let field = match agent {
    "codex" => "thread_id"
    "claude" => "session_id"
    _ => "runtime_session_id"
  }
  let mut session_id : String? = None
  for raw_line in events.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("\"" + field + "\":\"") {
      match extract_json_string_field(line, field) {
        Some(value) if value.trim() != "" => session_id = Some(value)
        _ => ()
      }
    }
  }
  session_id
}

///|
fn resume_session_missing(output : String) -> Bool {
  let lower = output.to_lower()
  lower.contains("runtime/resume failed") &&
  (
    lower.contains("no runtime session found") ||
    (lower.contains("runtime session id") && lower.contains("not found"))
  )
}

///|
fn runtime_command_progress_message(line : String) -> String? {
  ignore(line)
  None
}

///|
fn runtime_display_event(line : String) -> (String, String)? {
  let trimmed = line.trim().to_owned()
  if trimmed == "" {
    return None
  }
  if !trimmed.has_prefix("{") {
    if trimmed.contains("Unable to find image") ||
      trimmed.contains("Pulling from") {
      return Some(("status", "Pulling the Runtime image."))
    }
    if trimmed.contains("Status: Image is up to date") ||
      trimmed.contains("Status: Downloaded newer image") {
      return Some(("status", "Runtime image is ready."))
    }
    return None
  }
  if trimmed.contains("\"type\":\"runtime.started\"") {
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
      match runtime_command_progress_message(trimmed) {
        Some(message) => Some(("status", message))
        None => None
      }
    }
  } else {
    None
  }
}

///|
async fn append_runtime_display_event(
  store : Store,
  project_id : String,
  run_id : String,
  line : String,
) -> Unit noraise {
  match runtime_display_event(line) {
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
fn command_args(command : Array[String]) -> Array[String] {
  let args : Array[String] = []
  for i in 1..<command.length() {
    args.push(command[i])
  }
  args
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
      command[0] == "claude" &&
      index > 0 &&
      command[index - 1] == "--append-system-prompt" {
      "<system-prompt>"
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
    runtime_log_path: artifacts.map(fn(artifacts) { artifacts.agent_log_path }),
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
  agent_home_path : String,
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
  args.push("-v")
  args.push(
    docker_bind_source(config, agent_home_path) +
    ":" +
    agent_container_home_dir(),
  )
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
  for part in container_command {
    args.push(part)
  }
  args
}

///|
fn agent_runtime_timeout_seconds() -> Int {
  match @env.get_env_var("MOONCRAFT_AGENT_RUNTIME_TIMEOUT_SECONDS") {
    Some(value) => {
      let parsed = @string.parse_int(value.trim().to_owned()) catch {
        _ => 3600
      }
      if parsed <= 0 {
        3600
      } else if parsed > 3600 {
        3600
      } else {
        parsed
      }
    }
    None => 3600
  }
}

///|
fn docker_run_timeout_script(
  docker_args : Array[String],
  container_name : String,
  timeout_seconds : Int,
) -> String {
  let docker_command : Array[String] = ["docker"]
  for arg in docker_args {
    docker_command.push(arg)
  }
  [
    "set -eu",
    "timeout_marker=\"${TMPDIR:-/tmp}/mooncraft-runtime-timeout.$$.marker\"",
    "watchdog_pid=\"\"",
    "cleanup() {",
    "  if [ -n \"$watchdog_pid\" ]; then",
    "    kill \"$watchdog_pid\" >/dev/null 2>&1 || true",
    "    wait \"$watchdog_pid\" >/dev/null 2>&1 || true",
    "  fi",
    "  rm -f \"$timeout_marker\"",
    "}",
    "trap cleanup EXIT INT TERM",
    "rm -f \"$timeout_marker\"",
    "(",
    "  sleep " + timeout_seconds.to_string(),
    "  touch \"$timeout_marker\"",
    "  echo " +
    shell_quote(
      "MoonCraft builder exceeded the configured runtime limit of " +
      timeout_seconds.to_string() +
      " seconds; stopping the Runtime container.",
    ) +
    " >&2",
    "  docker rm -f " + shell_quote(container_name) + " >/dev/null 2>&1 || true",
    ") &",
    "watchdog_pid=\"$!\"",
    "set +e",
    command_display(docker_command) + " &",
    "docker_pid=\"$!\"",
    "wait \"$docker_pid\"",
    "status=\"$?\"",
    "set -e",
    "if [ ! -f \"$timeout_marker\" ]; then",
    "  kill \"$watchdog_pid\" >/dev/null 2>&1 || true",
    "  wait \"$watchdog_pid\" >/dev/null 2>&1 || true",
    "  watchdog_pid=\"\"",
    "fi",
    "exit \"$status\"",
  ].join("\n")
}

///|
async fn append_streaming_command_text(
  store : Store,
  project_id : String,
  run_id : String,
  pending : Ref[String],
  chunk : String,
) -> Unit {
  let text = pending.val + chunk.replace_all(old="\r\n", new="\n")
  let lines = text.split("\n").to_array()
  if lines.length() == 0 {
    pending.val = ""
    return
  }
  for index in 0..<(lines.length() - 1) {
    let line = lines[index].to_owned().trim(chars="\r").to_owned()
    if line != "" {
      append_runtime_display_event(store, project_id, run_id, line)
    }
  }
  pending.val = lines[lines.length() - 1].to_owned()
}

///|
async fn flush_streaming_command_text(
  store : Store,
  project_id : String,
  run_id : String,
  pending : Ref[String],
) -> Unit {
  let line = pending.val.trim(chars="\r").to_owned()
  if line != "" {
    append_runtime_display_event(store, project_id, run_id, line)
  }
  pending.val = ""
}

///|
async fn stream_command_log_delta(
  store : Store,
  project_id : String,
  run_id : String,
  log_path : String,
  seen_length : Ref[Int],
  pending : Ref[String],
  output_chunks : Array[String],
) -> Unit {
  let output = safe_read_string_or(log_path, "")
  if output.length() <= seen_length.val {
    return
  }
  let chunk = output.unsafe_substring(
    start=seen_length.val,
    end=output.length(),
  )
  seen_length.val = output.length()
  output_chunks.push(chunk)
  append_streaming_command_text(store, project_id, run_id, pending, chunk)
}

///|
async fn run_streaming_command(
  store : Store,
  root : String,
  project_id : String,
  run_id : String,
  stream_log_path : String,
  command : String,
  args : Array[String],
) -> Result[(Int, String), String] noraise {
  try
    @async.with_task_group(group => {
      ensure_dir(parent_dir(stream_log_path))
      let writer = @process.redirect_to_file(
        stream_log_path,
        create=0o644,
        truncate=true,
      )
      let output_chunks : Array[String] = []
      let pending_line = @ref.new("")
      let seen_length = @ref.new(0)
      let process = @process.spawn(
        group,
        command,
        args,
        stdout=writer,
        stderr=writer,
        cwd=root,
        no_wait=true,
      )
      store.append_run_event(
        project_id, run_id, "status", "Runtime container is running.",
      )
      let mut exit_status : Int? = None
      while exit_status is None {
        stream_command_log_delta(
          store, project_id, run_id, stream_log_path, seen_length, pending_line,
          output_chunks,
        )
        let status = process.try_wait() catch { _ => None }
        match status {
          Some(code) => exit_status = Some(code)
          None => @async.sleep(200)
        }
      }
      stream_command_log_delta(
        store, project_id, run_id, stream_log_path, seen_length, pending_line, output_chunks,
      )
      flush_streaming_command_text(store, project_id, run_id, pending_line)
      let code = match exit_status {
        Some(code) => code
        None => process.wait()
      }
      (code, output_chunks.join(""))
    })
  catch {
    err => Err("The AI builder command could not be started: \{err}")
  } noraise {
    value => Ok(value)
  }
}

///|
async fn stream_docker_output(
  store : Store,
  root : String,
  project_id : String,
  run_id : String,
  config : AgentRuntimeConfig,
  workspace_path : String,
  agent_home_path : String,
  artifacts : RunArtifacts,
  container_command : Array[String],
) -> Result[(Int, String), String] noraise {
  store.append_run_event(
    project_id, run_id, "status", "Preparing the builder environment.",
  )
  let env_file_path = write_docker_env_file(config, artifacts)
  store.append_run_event(
    project_id, run_id, "status", "Preparing builder workspace mounts.",
  )
  prepare_agent_mounts(workspace_path, Some(agent_home_path), artifacts)
  store.append_run_event(
    project_id, run_id, "status", "Preparing builder authentication.",
  )
  match prepare_agent_auth(config, agent_home_path) {
    Ok(_) => ignore(())
    Err(message) => {
      remove_docker_env_file(env_file_path)
      return Err(message)
    }
  }
  let docker_args = docker_command_args(
    config, env_file_path, workspace_path, agent_home_path, artifacts, container_command,
  )
  store.append_run_event(
    project_id, run_id, "status", "Launching the Runtime container.",
  )
  let result = match
    run_streaming_command(
      store,
      root,
      project_id,
      run_id,
      artifacts.agent_log_path + ".stream",
      "sh",
      [
        "-c",
        docker_run_timeout_script(
          docker_args,
          agent_runtime_container_name(project_id, run_id),
          agent_runtime_timeout_seconds(),
        ),
      ],
    ) {
    Ok(result) => result
    Err(message) => {
      remove_docker_env_file(env_file_path)
      return Err(message)
    }
  }
  remove_docker_env_file(env_file_path)
  Ok(result)
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
  if smoke_runtime_enabled() {
    let result = match
      collect_fake_runtime_output(root, project, workspace_path, command) {
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
        append_runtime_display_event(store, project.id, run_id, line)
      }
    }
    Ok(result)
  } else {
    match config {
      Some(config) => {
        let agent_home_path = project_runtime_agent_home(
          root,
          project.id,
          config.agent_session_id,
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
fn fake_runtime_send_command(prompt : String) -> Array[String] {
  ["fake-runtime", "send", prompt]
}

///|
fn fake_runtime_resume_command(
  runtime_session_id : String,
  prompt : String,
) -> Array[String] {
  ["fake-runtime", "resume", runtime_session_id, prompt]
}

///|
fn runtime_failure(
  assistant_message : String,
  error_message : String,
  thread_id : String?,
) -> AgentTurnFailure {
  runtime_failure_with_debug(assistant_message, error_message, thread_id, None)
}

///|
fn runtime_failure_with_debug(
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
async fn run_runtime_turn(
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
  let thread_id_before = project.runtime_session_id
  let model = match config {
    Some(config) => config.model
    None => default_runtime_model
  }
  let prompt = if raw_prompt {
    user_prompt
  } else if thread_id_before is Some(_) && resume_existing {
    followup_prompt(user_prompt)
  } else {
    bootstrap_prompt(user_prompt)
  }
  safe_write_string(artifacts.prompt_path, prompt)
  let command = match config {
    Some(config) =>
      match
        agent_command(root, config, prompt, resume_existing && !raw_prompt) {
        Ok(command) => command
        Err(message) =>
          return Err(
            runtime_failure_with_debug(
              "The AI builder could not be started for that update.",
              message,
              thread_id_before,
              Some(
                failure_debug("AI builder startup", None, None, Some(artifacts)),
              ),
            ),
          )
      }
    None =>
      match thread_id_before {
        Some(runtime_session_id) if resume_existing && !raw_prompt =>
          fake_runtime_resume_command(runtime_session_id, prompt)
        _ => fake_runtime_send_command(prompt)
      }
  }
  let mut active_command = command
  let runtime_result = match
    collect_agent_command_output(
      store, run_id, root, config, project, workspace_path, artifacts, command,
    ) {
    Ok(result) => result
    Err(message) =>
      return Err(
        runtime_failure_with_debug(
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
  let (initial_exit_code, initial_output, initial_fake_summary) = runtime_result
  let mut exit_code = initial_exit_code
  let mut output = initial_output
  let mut fake_summary = initial_fake_summary
  append_command_log(
    artifacts.agent_log_path,
    "agent run",
    active_command,
    exit_code,
    output,
  )
  let mut thread_id = thread_id_before
  let agent_name = match config {
    Some(config) => config.agent_cli
    None => "fake-runtime"
  }
  match extract_agent_session_id(output, agent_name) {
    Some(runtime_session_id) => thread_id = Some(runtime_session_id)
    None => ()
  }
  if thread_id_before is None && thread_id is None {
    return Err(
      runtime_failure_with_debug(
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
  if !raw_prompt &&
    thread_id_before is Some(_) &&
    exit_code != 0 &&
    resume_session_missing(output) {
    let recovery_prompt_text = recovery_prompt(
      initial_project_prompt, user_prompt,
    )
    let recovery_command = match config {
      Some(config) =>
        match agent_command(root, config, recovery_prompt_text, false) {
          Ok(command) => command
          Err(message) =>
            return Err(
              runtime_failure_with_debug(
                "The builder session could not be recovered for that update.",
                message,
                thread_id_before,
                Some(
                  failure_debug(
                    "AI builder session recovery startup",
                    None,
                    None,
                    Some(artifacts),
                  ),
                ),
              ),
            )
        }
      None => fake_runtime_send_command(recovery_prompt_text)
    }
    let recovery_result = match
      collect_agent_command_output(
        store, run_id, root, config, project, workspace_path, artifacts, recovery_command,
      ) {
      Ok(result) => result
      Err(message) =>
        return Err(
          runtime_failure_with_debug(
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
      "runtime session recovery",
      active_command,
      recovery_exit_code,
      recovery_output,
    )
    let recovery_thread_id = match
      extract_agent_session_id(recovery_output, agent_name) {
      Some(runtime_session_id) => runtime_session_id
      None =>
        return Err(
          runtime_failure_with_debug(
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
  if exit_code != 0 {
    return Err(
      runtime_failure_with_debug(
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
        thread_id,
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
  let thread_id = match thread_id {
    Some(thread_id) => thread_id
    None =>
      return Err(
        runtime_failure_with_debug(
          default_failure_assistant_message(),
          "The builder session id could not be determined for this run.",
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
  Ok({ summary, thread_id, artifacts })
}

///|
fn preview_audit_script_path(root : String) -> String {
  root + "/scripts/preview_audit.sh"
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
  @fs.path_exists(preview_audit_script_path(root))
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
fn preview_audit_base_url() -> String {
  match @env.get_env_var("MOONCRAFT_PREVIEW_AUDIT_BASE_URL") {
    Some(value) if value.trim() != "" => value.trim().to_owned()
    _ =>
      match @env.get_env_var("MOONCRAFT_PORT") {
        Some(port) if port.trim() != "" => "http://127.0.0.1:\{port.trim()}"
        _ => "http://127.0.0.1:8080"
      }
  }
}

///|
fn trim_trailing_slash(value : String) -> String {
  if value.has_suffix("/") {
    value[:value.length() - 1].to_owned()
  } else {
    value
  }
}

///|
fn preview_audit_target_url_for_base(
  base_url : String,
  preview : @sdk.PreviewTarget,
) -> String {
  if preview.url.has_prefix("http://") || preview.url.has_prefix("https://") {
    preview.url
  } else {
    trim_trailing_slash(base_url) + preview.url
  }
}

///|
fn preview_audit_target_url(preview : @sdk.PreviewTarget) -> String {
  preview_audit_target_url_for_base(preview_audit_base_url(), preview)
}

///|
fn preview_audit_command(
  root : String,
  preview : @sdk.PreviewTarget,
) -> Array[String] {
  ["sh", preview_audit_script_path(root), preview_audit_target_url(preview)]
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
    "HTTP preview audit",
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
      message: trim_or_default(output, "The HTTP preview audit failed."),
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
        runtime_failure_with_debug(
          "The workspace was updated, but saving the latest project snapshot failed.",
          message,
          Some(thread_id),
          Some(failure_debug("Workspace snapshot", None, None, Some(artifacts))),
        ),
      )
  }
}

///|
async fn RuntimeGateway::run_turn(
  self : RuntimeGateway,
  store : Store,
  project : @sdk.ProjectDetail,
  initial_project_prompt : String,
  workspace_path : String,
  run_id : String,
  user_prompt : String,
  raw_prompt? : Bool = false,
  resume_existing? : Bool = true,
) -> Result[AgentTurnSuccess, AgentTurnFailure] noraise {
  let config = if smoke_runtime_enabled() {
    None
  } else {
    let settings = match
      store.lease_ai_runtime_settings_for_project(project.id, run_id) {
      Ok(settings) => settings
      Err(message) =>
        return Err(
          runtime_failure(
            "MoonCraft's app builder is temporarily unavailable. Please retry later.",
            message,
            project.runtime_session_id,
          ),
        )
    }
    match AgentRuntimeConfig::load(self.root, settings) {
      Ok(config) => Some(config)
      Err(message) =>
        return Err(
          runtime_failure(
            "The app builder could not be started for that update.",
            message,
            project.runtime_session_id,
          ),
        )
    }
  }
  let runtime_result = match
    run_runtime_turn(
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
      runtime_result.thread_id,
      runtime_result.artifacts,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  Ok({
    summary: runtime_result.summary,
    thread_id: Some(runtime_result.thread_id),
  })
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
  match self.store.set_project_preview(project_id, current_preview) {
    Some(_) => ignore(())
    None => {
      self.store.finish_run_failure(
        project_id,
        run_id,
        preview_audit_repair_failed_assistant_message(),
        "The preview target could not be persisted before preview audit.",
        current_thread_id,
      )
      return
    }
  }
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
    let repair_result = self.runtime_gateway.run_turn(
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
      Some(thread_id) =>
        self.store.save_project_runtime_session_id(project_id, thread_id)
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
    match self.store.set_project_preview(project_id, current_preview) {
      Some(_) => ignore(())
      None => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The repaired preview target could not be persisted before preview audit.",
          current_thread_id,
        )
        return
      }
    }
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
        project.runtime_session_id,
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
        project.runtime_session_id,
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
        project.runtime_session_id,
      )
      return
    }
  }
  let agent_result = self.runtime_gateway.run_turn(
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
            let repair_result = self.runtime_gateway.run_turn(
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
