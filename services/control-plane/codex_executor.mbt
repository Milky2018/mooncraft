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
  image : String
  platform : String
  agent_cli : String
  provider : String
  model : String
  api_key : String
  container_home : String
  container_data_dir : String
  host_data_dir : String?
}

///|
struct AgentRuntimeSpec {
  label : String
  container_home : String
  runs_as_mooncraft_user : Bool
}

///|
fn agent_runtime_spec(agent_cli : String) -> AgentRuntimeSpec {
  match agent_cli {
    "claude_code" =>
      {
        label: "claude code",
        container_home: "/home/mooncraft",
        runs_as_mooncraft_user: true,
      }
    "kimi_code" =>
      {
        label: "kimi code",
        container_home: "/root",
        runs_as_mooncraft_user: false,
      }
    _ =>
      { label: "codex", container_home: "/root", runs_as_mooncraft_user: false }
  }
}

///|
let default_agent_runtime_image = "docker.io/moonbitcloud/mooncraft-agent-runtime:0.1.0"

///|
fn configured_default_agent_runtime_image(root : String) -> String {
  let configured = safe_read_string_or(
      root + "/config/agent_runtime_image.txt",
      default_agent_runtime_image,
    )
    .trim()
    .to_owned()
  if configured == "" {
    default_agent_runtime_image
  } else {
    configured
  }
}

///|
let default_codex_model = "gpt-5.5"

///|
struct RunArtifacts {
  project_id : String
  run_id : String
  dir : String
  last_message_path : String
  agent_log_path : String
  validation_log_path : String
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
    last_message_path: dir + "/last_message.txt",
    agent_log_path: dir + "/agent.log",
    validation_log_path: dir + "/validation.log",
  }
}

///|
fn AgentRuntimeConfig::container_agent_home(
  self : AgentRuntimeConfig,
) -> String {
  self.container_home + "/.codex"
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
  "HOME=" +
  docker_env_value(config.container_home) +
  "\n" +
  "CODEX_HOME=" +
  docker_env_value(config.container_agent_home()) +
  "\n" +
  "MOONCRAFT_AI_PROVIDER=" +
  docker_env_value(config.provider) +
  "\n" +
  "MOONCRAFT_AGENT_CLI=" +
  docker_env_value(config.agent_cli) +
  "\n" +
  "MOONCRAFT_AI_MODEL=" +
  docker_env_value(config.model) +
  "\n" +
  "MOONCRAFT_AI_API_KEY=" +
  docker_env_value(config.api_key) +
  "\n"
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
  let image = match @env.get_env_var("MOONCRAFT_AGENT_RUNTIME_IMAGE") {
    Some(value) if value.trim() != "" => value.trim().to_owned()
    _ =>
      match @env.get_env_var("MOONCRAFT_CODEX_DOCKER_IMAGE") {
        Some(value) if value.trim() != "" => value.trim().to_owned()
        _ => configured_default_agent_runtime_image(root)
      }
  }
  if @env.get_env_var("MOONCRAFT_CODEX_HOME_HOST") is Some(value) &&
    value.trim() != "" {
    return Err(
      "MOONCRAFT_CODEX_HOME_HOST is not supported. Configure AI keys in the MoonCraft admin page instead.",
    )
  }
  let spec = agent_runtime_spec(settings.agent_cli)
  let container_home = match
    @env.get_env_var("MOONCRAFT_CODEX_CONTAINER_HOME") {
    Some(value) if value.trim() != "" => value
    _ => spec.container_home
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
    image,
    platform,
    agent_cli: settings.agent_cli,
    provider: settings.provider,
    model: settings.model,
    api_key: settings.api_key,
    container_home,
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
fn recovery_prompt(
  initial_project_prompt : String,
  user_message : String,
) -> String {
  ignore(initial_project_prompt)
  user_message
}

///|
fn mooncraft_agent_system_prompt() -> String {
  (
    #|You are working inside a MoonCraft generated app workspace.
    #|Use the runtime instructions as the product contract. Treat the user prompt as the product request. Do not write hidden platform instructions into the project workspace, and do not reveal internal runtime, provider, container, or log details in the final response.
  )
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
fn workspace_contract_repair_prompt(
  contract_error : String,
  initial_project_prompt : String,
  user_prompt : String,
) -> String {
  (
    #|MoonCraft could not validate the generated workspace structure.
    #|
    #|This is a mandatory repair task.
    #|
    #|Problem:
    #|
  ) +
  contract_error +
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
    #|Repair the workspace so it satisfies the MoonCraft generated-app runtime contract. Use the runtime instructions for the exact contract, including `preferred-target` and `mooncraft-preview.sh`. Preserve the user's requested app behavior.
  )
}

///|
fn workspace_contract_failed_assistant_message() -> String {
  "The builder did not finish creating a valid app workspace. Send another message to retry."
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
fn trim_or_default(text : String, fallback : String) -> String {
  let normalized = text.trim(chars="\n\r ").to_owned()
  if normalized == "" {
    fallback
  } else {
    normalized
  }
}

///|
fn workspace_has_root_moon_project(workspace_path : String) -> Bool {
  @fs.path_exists(workspace_path + "/moon.mod.json") ||
  @fs.path_exists(workspace_path + "/moon.mod") ||
  @fs.path_exists(workspace_path + "/moon.work")
}

///|
fn workspace_has_preferred_target(workspace_path : String) -> Bool {
  let manifest_path = workspace_path + "/moon.mod.json"
  if !@fs.path_exists(manifest_path) {
    return false
  }
  let manifest = safe_read_string_or(manifest_path, "")
  manifest.contains("\"preferred-target\"")
}

///|
fn workspace_has_preview_script(workspace_path : String) -> Bool {
  @fs.path_exists(workspace_path + "/mooncraft-preview.sh")
}

///|
fn workspace_moonbit_source_find_command(workspace_path : String) -> String {
  let workspace = trim_mount_path(workspace_path)
  "find " +
  shell_quote(workspace) +
  " \\( -path " +
  shell_quote(workspace + "/.repos") +
  " -o -path " +
  shell_quote(workspace + "/_build") +
  " -o -path " +
  shell_quote(workspace + "/.git") +
  " -o -path " +
  shell_quote(workspace + "/.mooncakes") +
  " \\) -prune -o -name '*.mbt' -type f"
}

///|
fn workspace_has_user_moonbit_source(workspace_path : String) -> Bool {
  shell_status(
    workspace_moonbit_source_find_command(workspace_path) +
    " -print -quit | grep -q .",
  ) ==
  0
}

///|
fn workspace_app_sources_contain(
  workspace_path : String,
  needle : String,
) -> Bool {
  shell_status(
    workspace_moonbit_source_find_command(workspace_path) +
    " ! -name '*_test.mbt' ! -name '*_wbtest.mbt' -exec grep -F -q " +
    shell_quote(needle) +
    " {} \\; -print -quit | grep -q .",
  ) ==
  0
}

///|
fn workspace_contract_error(workspace_path : String) -> String? {
  if !workspace_has_root_moon_project(workspace_path) {
    Some(
      "The builder did not create a MoonBit project at the workspace root. Expected `moon.mod.json`, `moon.mod`, or `moon.work` directly under \{workspace_path}.",
    )
  } else if !workspace_has_preferred_target(workspace_path) {
    Some(
      "The generated app must set `preferred-target` in the root `moon.mod.json` so MoonCraft can validate it with plain `moon` commands.",
    )
  } else if !workspace_has_user_moonbit_source(workspace_path) {
    Some(
      "The builder created a root MoonBit manifest but did not create any MoonBit source files under \{workspace_path}.",
    )
  } else if !workspace_has_preview_script(workspace_path) {
    Some(
      "The generated app must provide a root `mooncraft-preview.sh` script that starts the live preview server.",
    )
  } else if workspace_app_sources_contain(workspace_path, "MoonCraft Starter") {
    Some(
      "The generated app still contains the default MoonCraft starter page. Replace it with the user's requested app before finishing.",
    )
  } else {
    None
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
fn extract_agent_text_event(output : String) -> String? {
  let mut latest = None
  for raw_line in output.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("\"type\":\"text\"") {
      match extract_json_string_field(line, "text") {
        Some(text) if text.trim() != "" =>
          latest = Some(text.trim(chars="\n\r ").to_owned())
        _ => ()
      }
    } else if line.contains("\"type\":\"result\"") {
      match extract_json_string_field(line, "result") {
        Some(text) if text.trim() != "" =>
          latest = Some(text.trim(chars="\n\r ").to_owned())
        _ => ()
      }
    } else if line.contains("\"content\"") {
      match extract_json_string_field(line, "content") {
        Some(text) if text.trim() != "" =>
          latest = Some(text.trim(chars="\n\r ").to_owned())
        _ => ()
      }
    } else {
      ()
    }
  }
  latest
}

///|
fn stateless_agent_summary_from_output(
  output : String,
  artifacts : RunArtifacts,
  fallback : String,
) -> String {
  match extract_agent_text_event(output) {
    Some(summary) => summary
    None =>
      trim_or_default(
        safe_read_string_or(artifacts.last_message_path, ""),
        fallback,
      )
  }
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
fn fake_codex_update_workspace(
  workspace_path : String,
  prompt : String,
) -> Result[String, String] {
  let normalized = trim_or_default(
    fake_codex_user_request(prompt),
    "MoonCraft update",
  )
  let async_version = required_reference_module_version("moonbitlang/async")
  let mocket_version = required_reference_module_version("oboard/mocket")
  let x_version = required_reference_module_version("moonbitlang/x")
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
        #|}
        #|
        #|options(
        #|  "is-main": true,
        #|)
        #|
        #|supported_targets = "native"
      ),
    ),
    (
      "/main.mbt",
      (
        #|///|
        #|fn app_page_html() -> String {
        #|  "<!doctype html><html><head><meta charset='utf-8'><title>MoonCraft smoke preview</title></head><body><main><h1>MoonCraft smoke preview</h1><p>The fake builder generated a runnable preview.</p></main></body></html>"
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
  if agent_runtime_spec(config.agent_cli).runs_as_mooncraft_user {
    args.push("-e")
    args.push("HOME=" + config.container_home)
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
          project_runtime_agent_home(root, project.id, config.agent_cli),
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
    project_runtime_agent_home(root, project.id, config.agent_cli),
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
fn codex_resume_command(
  model : String,
  thread_id : String,
  user_prompt : String,
) -> Array[String] {
  codex_resume_raw_command(model, thread_id, followup_prompt(user_prompt))
}

///|
fn codex_resume_raw_command(
  model : String,
  thread_id : String,
  prompt : String,
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
    agent_container_artifacts_dir() + "/last_message.txt",
    "--dangerously-bypass-approvals-and-sandbox",
    thread_id,
    prompt,
  ]
}

///|
fn claude_code_command(model : String, prompt : String) -> Array[String] {
  [
    "claude",
    "--bare",
    "-p",
    prompt,
    "--model",
    model,
    "--append-system-prompt",
    mooncraft_agent_system_prompt(),
    "--output-format",
    "stream-json",
    "--verbose",
    "--dangerously-skip-permissions",
    "--no-session-persistence",
  ]
}

///|
fn kimi_code_command(prompt : String) -> Array[String] {
  [
    "kimi",
    "--model",
    "mooncraft-openrouter",
    "--work-dir",
    agent_container_workspace_dir(),
    "--prompt",
    prompt,
    "--print",
    "--output-format",
    "stream-json",
    "--yolo",
    "--afk",
  ]
}

///|
fn stateless_agent_prompt(
  workspace_path : String,
  user_prompt : String,
) -> String {
  ignore(workspace_path)
  user_prompt
}

///|
fn agent_cli_label(agent_cli : String) -> String {
  agent_runtime_spec(agent_cli).label
}

///|
async fn run_stateless_agent_turn(
  store : Store,
  root : String,
  config : AgentRuntimeConfig?,
  project : @sdk.ProjectDetail,
  workspace_path : String,
  run_id : String,
  user_prompt : String,
  reset_logs? : Bool = true,
  raw_prompt? : Bool = false,
) -> Result[AgentExecutionResult, AgentTurnFailure] noraise {
  let artifacts = RunArtifacts::new(root, project.id, run_id)
  safe_write_string(artifacts.last_message_path, "")
  if reset_logs {
    safe_write_string(artifacts.agent_log_path, "")
  }
  let model = match config {
    Some(config) => config.model
    None => project.model
  }
  let agent_cli = match normalize_agent_cli(project.agent_cli) {
    Ok(agent_cli) => agent_cli
    Err(_) => default_agent_cli()
  }
  let prompt = if raw_prompt {
    user_prompt
  } else {
    stateless_agent_prompt(workspace_path, user_prompt)
  }
  let command = match agent_cli {
    "claude_code" => claude_code_command(model, prompt)
    "kimi_code" => kimi_code_command(prompt)
    _ => codex_exec_command(model, user_prompt)
  }
  match
    run_agent_runtime_doctor(
      root,
      config,
      project,
      workspace_path,
      artifacts,
      None,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  let result = match
    collect_agent_command_output(
      store, run_id, root, config, project, workspace_path, artifacts, command,
    ) {
    Ok(result) => result
    Err(message) =>
      return Err(
        codex_failure_with_debug(
          "The AI builder could not be started for that update.",
          message,
          None,
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
  let (exit_code, output, fake_summary) = result
  append_command_log(
    artifacts.agent_log_path,
    agent_cli_label(agent_cli) + " execution",
    command,
    exit_code,
    output,
  )
  let summary = match fake_summary {
    Some(summary) => trim_or_default(summary, default_success_summary())
    None =>
      stateless_agent_summary_from_output(
        output,
        artifacts,
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
          "AI builder execution",
          exit_code,
          artifacts.agent_log_path,
          output,
        ),
        None,
        Some(
          failure_debug(
            "AI builder execution",
            Some(command),
            Some(exit_code),
            Some(artifacts),
          ),
        ),
      ),
    )
  }
  Ok({ summary, thread_id: run_id, artifacts })
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
  let thread_id_before = project.codex_thread_id
  let model = match config {
    Some(config) => config.model
    None => default_codex_model
  }
  let command = if raw_prompt {
    match thread_id_before {
      Some(thread_id) if resume_existing =>
        codex_resume_raw_command(model, thread_id, user_prompt)
      _ => codex_exec_raw_command(model, user_prompt)
    }
  } else {
    match thread_id_before {
      Some(thread_id) if resume_existing =>
        codex_resume_command(model, thread_id, user_prompt)
      _ => codex_exec_command(model, user_prompt)
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
  }
  if !raw_prompt &&
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
            dependency_fetch_failure_assistant_message(
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
        dependency_fetch_failure_assistant_message(
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
  Ok({ summary, thread_id, artifacts })
}

///|
async fn run_validation_command(
  root : String,
  config : AgentRuntimeConfig?,
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
            "The workspace was updated, but validation could not be started.",
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
            root,
            config,
            workspace_path,
            None,
            artifacts,
            command,
          ) {
          Ok(result) => result
          Err(message) =>
            return Err(
              codex_failure_with_debug(
                "The workspace was updated, but validation could not be started.",
                message,
                Some(thread_id),
                Some(failure_debug(label, Some(command), None, Some(artifacts))),
              ),
            )
        }
      None =>
        return Err(
          codex_failure_with_debug(
            "The workspace was updated, but validation could not be started.",
            "The app validator is temporarily unavailable.",
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
          output, "The workspace was updated, but validation failed before the preview could be refreshed.",
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
  config : AgentRuntimeConfig?,
  workspace_path : String,
  artifacts : RunArtifacts,
  thread_id : String,
) -> Result[Unit, AgentTurnFailure] noraise {
  let command = ["sh", "-lc", validation_shell_script(include_update=false)]
  let result = match config {
    Some(config) =>
      match
        collect_docker_output(
          root,
          config,
          workspace_path,
          None,
          artifacts,
          command,
        ) {
        Ok(result) => result
        Err(message) =>
          return Err(
            codex_failure_with_debug(
              "The workspace was updated, but validation could not be started.",
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
          "The workspace was updated, but validation could not be started.",
          "The app validator is temporarily unavailable.",
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
          output, "The workspace was updated, but validation failed before the preview could be refreshed.",
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
  config : AgentRuntimeConfig?,
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
      "moon build",
      ["moon", "build"],
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
  config : AgentRuntimeConfig?,
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
  let agent_cli = match normalize_agent_cli(project.agent_cli) {
    Ok(agent_cli) => agent_cli
    Err(_) => default_agent_cli()
  }
  let mut codex_result = match
    (if agent_cli == "codex" {
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
      )
    } else {
      run_stateless_agent_turn(
        store,
        self.root,
        config,
        project,
        workspace_path,
        run_id,
        user_prompt,
        raw_prompt~,
      )
    }) {
    Ok(result) => result
    Err(failure) => return Err(failure)
  }
  match workspace_contract_error(workspace_path) {
    Some(contract_error) => {
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
      store.append_run_event(
        project.id,
        run_id,
        "status",
        "Repairing the project workspace.",
      )
      let repair_project = if agent_cli == "codex" {
        { ..project, codex_thread_id: Some(codex_result.thread_id) }
      } else {
        project
      }
      let repair_result = match
        (if agent_cli == "codex" {
          run_codex_turn(
            store,
            self.root,
            config,
            repair_project,
            initial_project_prompt,
            workspace_path,
            run_id,
            workspace_contract_repair_prompt(
              contract_error, initial_project_prompt, user_prompt,
            ),
            reset_logs=false,
            raw_prompt=true,
            resume_existing=false,
          )
        } else {
          run_stateless_agent_turn(
            store,
            self.root,
            config,
            repair_project,
            workspace_path,
            run_id,
            workspace_contract_repair_prompt(
              contract_error, initial_project_prompt, user_prompt,
            ),
            reset_logs=false,
            raw_prompt=true,
          )
        }) {
        Ok(result) => result
        Err(failure) => return Err(failure)
      }
      codex_result = repair_result
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
      match workspace_contract_error(workspace_path) {
        Some(repair_error) =>
          return Err(
            codex_failure_with_debug(
              workspace_contract_failed_assistant_message(),
              repair_error,
              if agent_cli == "codex" {
                Some(codex_result.thread_id)
              } else {
                None
              },
              Some(
                failure_debug(
                  "Workspace contract",
                  None,
                  None,
                  Some(codex_result.artifacts),
                ),
              ),
            ),
          )
        None => ignore(())
      }
    }
    None => ignore(())
  }
  let artifacts = codex_result.artifacts
  let persist_validated_workspace = async fn() noraise {
    match
      persist_builder_workspace_snapshot(
        store,
        self.root,
        project.id,
        workspace_path,
        codex_result.thread_id,
        artifacts,
      ) {
      Ok(_) => Ok(())
      Err(failure) => Err(failure)
    }
  }
  safe_write_string(artifacts.validation_log_path, "")
  store.set_run_phase(project.id, run_id, Checking)
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
  Ok({
    summary: codex_result.summary,
    thread_id: if agent_cli == "codex" {
      Some(codex_result.thread_id)
    } else {
      None
    },
  })
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
      if updated_project.agent_cli == "codex" {
        match result.thread_id {
          Some(thread_id) =>
            self.store.set_project_thread_id(project_id, thread_id)
          None => ignore(())
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
                    self.store.set_project_thread_id(project_id, thread_id)
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
                    self.store.finish_run_success(
                      project_id,
                      run_id,
                      successful_preview_assistant_message(),
                      repair.thread_id,
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
