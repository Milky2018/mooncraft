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
}

///|
struct CodexDockerConfig {
  image : String
  host_codex_home : String
  container_home : String
}

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
fn CodexDockerConfig::load() -> Result[CodexDockerConfig, String] {
  let image = match @env.get_env_var("MOONBITCLOUD_CODEX_DOCKER_IMAGE") {
    Some(value) if value.trim() != "" => value
    _ =>
      return Err(
        "Set MOONBITCLOUD_CODEX_DOCKER_IMAGE to a Docker image that provides codex and the MoonBit toolchain.",
      )
  }
  let host_codex_home = match @env.get_env_var("MOONBITCLOUD_CODEX_HOME_HOST") {
    Some(value) if value.trim() != "" => value
    _ =>
      match @env.get_env_var("HOME") {
        Some(home) if home.trim() != "" => home + "/.codex"
        _ =>
          return Err(
            "The host Codex auth directory could not be determined. Set MOONBITCLOUD_CODEX_HOME_HOST.",
          )
      }
  }
  if !@fs.path_exists(host_codex_home) {
    return Err(
      "The host Codex auth directory was not found at \{host_codex_home}. Log in locally first or set MOONBITCLOUD_CODEX_HOME_HOST.",
    )
  }
  let container_home = match
    @env.get_env_var("MOONBITCLOUD_CODEX_CONTAINER_HOME") {
    Some(value) if value.trim() != "" => value
    _ => "/root"
  }
  Ok({ image, host_codex_home, container_home })
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
    #|- You may inspect, edit, create, and delete files anywhere in this workspace.
    #|- You may run shell commands as needed.
    #|- Before finishing, run `moon fmt`, `moon check`, and `moon test`.
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
    #|- You may inspect, edit, create, and delete files anywhere in this workspace.
    #|- You may run shell commands as needed.
    #|- Before finishing, run `moon fmt`, `moon check`, and `moon test`.
    #|- Your final response must be brief: summarize what you built, mention validation status, and mention any blocking failure.
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
fn append_command_log(path : String, label : String, content : String) -> Unit {
  safe_append_string(
    path,
    "== \{label} ==\n" + trim_or_default(content, "(no output)") + "\n\n",
  )
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
  args.push("-v")
  args.push(config.host_codex_home + ":" + config.container_codex_home())
  args.push("-v")
  args.push(workspace_path + ":" + codex_container_workspace_dir())
  args.push("-v")
  args.push(artifacts.dir + ":" + codex_container_artifacts_dir())
  args.push("-w")
  args.push(codex_container_workspace_dir())
  args.push(config.image)
  for part in container_command {
    args.push(part)
  }
  args
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
fn codex_exec_command(user_prompt : String) -> Array[String] {
  [
    "codex",
    "exec",
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
  thread_id : String,
  user_prompt : String,
) -> Array[String] {
  [
    "codex",
    "exec",
    "resume",
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
  {
    assistant_message: if assistant_message == "" {
      default_failure_assistant_message()
    } else {
      assistant_message
    },
    error_message,
    thread_id,
  }
}

///|
async fn run_codex_turn(
  root : String,
  config : CodexDockerConfig,
  project : @sdk.ProjectDetail,
  run_id : String,
  user_prompt : String,
) -> Result[CodexExecutionResult, AgentTurnFailure] noraise {
  let artifacts = RunArtifacts::new(root, project.id, run_id)
  safe_write_string(artifacts.last_message_path, "")
  let thread_id_before = project.codex_thread_id
  let command = match thread_id_before {
    Some(thread_id) => codex_resume_command(thread_id, user_prompt)
    None => codex_exec_command(user_prompt)
  }
  let codex_result = match
    collect_docker_output(
      root,
      config,
      project.workspace_path,
      artifacts,
      command,
    ) {
    Ok(result) => result
    Err(message) =>
      return Err(
        codex_failure(
          "I couldn't start the Codex worker for that update.", message, thread_id_before,
        ),
      )
  }
  let (exit_code, output) = codex_result
  safe_write_string(artifacts.codex_log_path, output)
  let thread_id = match thread_id_before {
    Some(thread_id) => thread_id
    None =>
      match extract_thread_id(output) {
        Some(thread_id) => thread_id
        None =>
          return Err(
            codex_failure(
              default_failure_assistant_message(),
              stage_failure_message(
                "Codex session startup",
                exit_code,
                artifacts.codex_log_path,
                output,
              ),
              None,
            ),
          )
      }
  }
  let summary = trim_or_default(
    safe_read_string_or(artifacts.last_message_path, ""),
    default_success_summary(),
  )
  if exit_code != 0 {
    return Err(
      codex_failure(
        default_failure_assistant_message(),
        stage_failure_message(
          "Codex execution",
          exit_code,
          artifacts.codex_log_path,
          output,
        ),
        Some(thread_id),
      ),
    )
  }
  Ok({ summary, thread_id, artifacts })
}

///|
async fn run_validation_command(
  root : String,
  config : CodexDockerConfig,
  workspace_path : String,
  artifacts : RunArtifacts,
  label : String,
  command : Array[String],
  thread_id : String,
) -> Result[Unit, AgentTurnFailure] noraise {
  let result = match
    collect_docker_output(root, config, workspace_path, artifacts, command) {
    Ok(result) => result
    Err(message) =>
      return Err(
        codex_failure(
          "I updated the workspace, but validation could not be started.",
          message,
          Some(thread_id),
        ),
      )
  }
  let (exit_code, output) = result
  append_command_log(artifacts.validation_log_path, label, output)
  if exit_code != 0 {
    return Err(
      codex_failure(
        "I updated the workspace, but validation failed before the preview could be refreshed.",
        stage_failure_message(
          label,
          exit_code,
          artifacts.validation_log_path,
          output,
        ),
        Some(thread_id),
      ),
    )
  }
  Ok(())
}

///|
async fn AgentGateway::run_turn(
  self : AgentGateway,
  project : @sdk.ProjectDetail,
  run_id : String,
  user_prompt : String,
) -> Result[AgentTurnSuccess, AgentTurnFailure] noraise {
  let config = match CodexDockerConfig::load() {
    Ok(config) => config
    Err(message) =>
      return Err(
        codex_failure(
          "I couldn't start the Codex worker for that update.",
          message,
          project.codex_thread_id,
        ),
      )
  }
  let codex_result = match
    run_codex_turn(self.root, config, project, run_id, user_prompt) {
    Ok(result) => result
    Err(failure) => return Err(failure)
  }
  let artifacts = codex_result.artifacts
  safe_write_string(artifacts.validation_log_path, "")
  match
    run_validation_command(
      self.root,
      config,
      project.workspace_path,
      artifacts,
      "moon fmt",
      ["moon", "fmt"],
      codex_result.thread_id,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  match
    run_validation_command(
      self.root,
      config,
      project.workspace_path,
      artifacts,
      "moon check",
      ["moon", "check"],
      codex_result.thread_id,
    ) {
    Ok(_) => ignore(())
    Err(failure) => return Err(failure)
  }
  match
    run_validation_command(
      self.root,
      config,
      project.workspace_path,
      artifacts,
      "moon test",
      ["moon", "test"],
      codex_result.thread_id,
    ) {
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
) -> Result[Unit, String] noraise {
  let args : Array[String] = [
    "run",
    "--manifest-path",
    self.root + "/moon.work",
    "services/control-plane",
    "--target",
    "native",
  ]
  if self.build_profile is Release {
    args.push("--release")
  }
  args.push("--")
  args.push("run-worker")
  args.push(project_id)
  args.push(run_id)
  let _ = try @process.spawn_orphan("moon", args, cwd=self.root) catch {
    err => return Err("The background run worker could not be started: \{err}")
  } noraise {
    pid => pid
  }
  Ok(())
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
  let agent_result = self.agent_gateway.run_turn(project, run_id, prompt)
  match agent_result {
    Ok(result) => {
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
    Err(failure) =>
      self.store.finish_run_failure(
        project_id,
        run_id,
        failure.assistant_message,
        failure.error_message,
        failure.thread_id,
      )
  }
}

///|
async fn run_worker_mode(
  root : String,
  project_id : String,
  run_id : String,
) -> Unit {
  let ctx = AppContext::new(root)
  ctx.run_project_turn(project_id, run_id)
}
