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
struct RunArtifacts {
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
  thread_id : String?
  artifacts : RunArtifacts
}

///|
async fn RunArtifacts::new(
  root : String,
  project_id : String,
  run_id : String,
) -> RunArtifacts {
  let dir = run_artifacts_dir(root, project_id, run_id)
  ensure_dir(dir)
  {
    dir,
    prompt_path: "\{dir}/prompt.txt",
    last_message_path: "\{dir}/last_message.txt",
    agent_log_path: "\{dir}/agent.log",
    validation_log_path: "\{dir}/validation.log",
  }
}

///|
fn agent_container_workspace_dir() -> String {
  "/workspace"
}

///|
fn agent_container_home_dir() -> String {
  "/home/mooncraft"
}

///|
fn agent_runtime_container_name(project_id : String, run_id : String) -> String {
  "mooncraft-\{project_id}-\{run_id}"
}

///|
fn docker_env_value(value : String) -> String {
  value.replace_all(old="\r", new="").replace_all(old="\n", new="")
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
  output : String,
  fallback : String,
) -> String {
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
fn resume_session_missing(output : String) -> Bool {
  let lower = output.to_lower()
  lower.contains("runtime/resume failed") &&
  (
    lower.contains("no runtime session found") ||
    (lower.contains("runtime session id") && lower.contains("not found"))
  )
}

///|
async fn append_runtime_display_event(
  store : Store,
  project_id : String,
  run_id : String,
  worker_id : String,
  attempt : Int,
  line : String,
) -> Unit noraise {
  if runtime_display_event(line) is Some(event) {
    store.append_worker_run_event(
      project_id,
      run_id,
      worker_id,
      attempt,
      event.kind,
      event.code,
      event.content,
    )
  }
}

///|
async fn append_command_log(
  path : String,
  label : String,
  command : Array[String],
  exit_code : Int,
  content : String,
) -> Result[Unit, String] noraise {
  let output = trim_or_default(content, "(no output)")
  @async_fs.write_file(
    path,
    "== \{label} ==\ncommand: \{command_display(command)}\nexit_code: \{exit_code}\n\n\{output}\n\n",
    append=true,
    create=0o644,
  ) catch {
    err => return Err("Could not append command log \{path}: \{err}")
  }
  Ok(())
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
fn command_display(command : Array[String]) -> String {
  let text = StringBuilder()
  for index in 0..<command.length() {
    if index > 0 {
      text <+ " "
    }
    text <+ "\{shell_quote(command[index])}"
  }
  text.to_string()
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
async fn collect_agent_command_output(
  store : Store,
  run_id : String,
  worker_id : String,
  attempt : Int,
  root : String,
  project : @sdk.ProjectDetail,
  workspace_path : String,
  command : Array[String],
) -> Result[(Int, String, String?), String] noraise {
  let result = match
    collect_fake_runtime_output(root, project, workspace_path, command) {
    Ok(result) => result
    Err(message) => return Err(message)
  }
  store.append_worker_run_event(
    project.id,
    run_id,
    worker_id,
    attempt,
    "status",
    @sdk.run_event_code_local_builder_running(),
    "Running local builder.",
  )
  for raw_line in result.1.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line != "" {
      append_runtime_display_event(
        store,
        project.id,
        run_id,
        worker_id,
        attempt,
        line,
      )
    }
  }
  Ok(result)
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
async fn run_runtime_service_turn(
  store : Store,
  endpoint : RuntimeServiceEndpoint,
  project : @sdk.ProjectDetail,
  run_id : String,
  worker_id : String,
  attempt : Int,
  prompt : String,
  artifacts : RunArtifacts,
) -> Result[AgentExecutionResult, AgentTurnFailure] noraise {
  ignore(
    store.set_runtime_service_state(
      project.id,
      runtime_service_state_running(),
      None,
    ),
  )
  store.append_worker_run_event(
    project.id,
    run_id,
    worker_id,
    attempt,
    "status",
    @sdk.run_event_code_builder_started(),
    "Started the Runtime Service run.",
  )
  let accepted = match runtime_service_post_exec(endpoint, run_id, prompt) {
    Ok(run) => run
    Err(message) => {
      ignore(
        store.set_runtime_service_state(
          project.id,
          runtime_service_state_ready(),
          Some(runtime_service_idle_expires_at()),
        ),
      )
      return Err(
        runtime_failure_with_debug(
          "The app builder runtime could not start this run.",
          message,
          project.runtime_session_id,
          Some(
            failure_debug("Runtime Service /exec", None, None, Some(artifacts)),
          ),
        ),
      )
    }
  }
  let after : Ref[Int] = @ref.new(0)
  let mut current = accepted
  while true {
    match runtime_service_get_events(endpoint, run_id, after.val) {
      Ok(response) =>
        append_runtime_service_events(
          store,
          project.id,
          run_id,
          worker_id,
          attempt,
          response.events,
          after,
        )
      Err(message) => {
        ignore(
          store.set_runtime_service_state(
            project.id,
            runtime_service_state_ready(),
            Some(runtime_service_idle_expires_at()),
          ),
        )
        return Err(
          runtime_failure_with_debug(
            "The app builder runtime stopped reporting progress.",
            message,
            project.runtime_session_id,
            Some(
              failure_debug(
                "Runtime Service events",
                None,
                None,
                Some(artifacts),
              ),
            ),
          ),
        )
      }
    }
    match runtime_service_get_run(endpoint, run_id) {
      Ok(run) => current = run
      Err(message) => {
        ignore(
          store.set_runtime_service_state(
            project.id,
            runtime_service_state_ready(),
            Some(runtime_service_idle_expires_at()),
          ),
        )
        return Err(
          runtime_failure_with_debug(
            "The app builder runtime stopped reporting run status.",
            message,
            project.runtime_session_id,
            Some(
              failure_debug(
                "Runtime Service run status",
                None,
                None,
                Some(artifacts),
              ),
            ),
          ),
        )
      }
    }
    match current.status {
      "running" =>
        @async.sleep(1000) catch {
          _ =>
            return Err(
              runtime_failure_with_debug(
                "The app builder runtime was interrupted.",
                "Runtime Service polling was cancelled.",
                project.runtime_session_id,
                Some(
                  failure_debug(
                    "Runtime Service polling",
                    None,
                    None,
                    Some(artifacts),
                  ),
                ),
              ),
            )
        }
      "succeeded" => {
        store.append_worker_run_event(
          project.id,
          run_id,
          worker_id,
          attempt,
          "status",
          @sdk.run_event_code_builder_ended(),
          runtime_service_status_message(current),
        )
        ignore(
          store.set_runtime_service_state(
            project.id,
            runtime_service_state_ready(),
            Some(runtime_service_idle_expires_at()),
          ),
        )
        return Ok({
          summary: runtime_service_status_message(current),
          thread_id: project.runtime_session_id,
          artifacts,
        })
      }
      "failed" => {
        store.append_worker_run_event(
          project.id,
          run_id,
          worker_id,
          attempt,
          "status",
          @sdk.run_event_code_builder_failed(),
          runtime_service_status_message(current),
        )
        ignore(
          store.set_runtime_service_state(
            project.id,
            runtime_service_state_ready(),
            Some(runtime_service_idle_expires_at()),
          ),
        )
        return Err(
          runtime_failure_with_debug(
            runtime_service_status_message(current),
            runtime_service_status_message(current),
            project.runtime_session_id,
            Some(
              failure_debug(
                "Runtime Service run failed",
                None,
                None,
                Some(artifacts),
              ),
            ),
          ),
        )
      }
      other => {
        ignore(
          store.set_runtime_service_state(
            project.id,
            runtime_service_state_ready(),
            Some(runtime_service_idle_expires_at()),
          ),
        )
        return Err(
          runtime_failure_with_debug(
            "The app builder runtime returned an invalid run status.",
            "Runtime Service returned unsupported run status: \{other}",
            project.runtime_session_id,
            Some(
              failure_debug(
                "Runtime Service run status",
                None,
                None,
                Some(artifacts),
              ),
            ),
          ),
        )
      }
    }
  }
  Err(
    runtime_failure_with_debug(
      "The app builder runtime stopped unexpectedly.",
      "Runtime Service polling exited without a terminal run status.",
      project.runtime_session_id,
      Some(
        failure_debug("Runtime Service polling", None, None, Some(artifacts)),
      ),
    ),
  )
}

///|
async fn run_runtime_turn(
  store : Store,
  root : String,
  project : @sdk.ProjectDetail,
  initial_project_prompt : String,
  workspace_path : String,
  run_id : String,
  worker_id : String,
  attempt : Int,
  user_prompt : String,
  reset_logs? : Bool = true,
  raw_prompt? : Bool = false,
  resume_existing? : Bool = true,
) -> Result[AgentExecutionResult, AgentTurnFailure] noraise {
  let artifacts = RunArtifacts::new(root, project.id, run_id) catch {
    err =>
      return Err(
        runtime_failure(
          "The AI builder could not prepare run artifacts.",
          "Run artifact directory could not be created: \{err}",
          project.runtime_session_id,
        ),
      )
  }
  @async_fs.write_file(
    artifacts.last_message_path,
    "",
    create=0o644,
    truncate=true,
  ) catch {
    err =>
      return Err(
        runtime_failure_with_debug(
          "The AI builder could not prepare run logs.",
          "Run summary file could not be written: \{err}",
          project.runtime_session_id,
          Some(failure_debug("AI builder startup", None, None, Some(artifacts))),
        ),
      )
  }
  if reset_logs {
    @async_fs.write_file(
      artifacts.agent_log_path,
      "",
      create=0o644,
      truncate=true,
    ) catch {
      err =>
        return Err(
          runtime_failure_with_debug(
            "The AI builder could not prepare run logs.",
            "Run log file could not be written: \{err}",
            project.runtime_session_id,
            Some(
              failure_debug("AI builder startup", None, None, Some(artifacts)),
            ),
          ),
        )
    }
  }
  let thread_id_before = project.runtime_session_id
  let prompt = if raw_prompt {
    user_prompt
  } else if thread_id_before is Some(_) && resume_existing {
    followup_prompt(user_prompt)
  } else {
    bootstrap_prompt(user_prompt)
  }
  @async_fs.write_file(
    artifacts.prompt_path,
    prompt,
    create=0o644,
    truncate=true,
  ) catch {
    err =>
      return Err(
        runtime_failure_with_debug(
          "The AI builder could not prepare the prompt.",
          "Prompt file could not be written: \{err}",
          project.runtime_session_id,
          Some(failure_debug("AI builder startup", None, None, Some(artifacts))),
        ),
      )
  }
  let command = match thread_id_before {
    Some(runtime_session_id) if resume_existing && !raw_prompt =>
      fake_runtime_resume_command(runtime_session_id, prompt)
    _ => fake_runtime_send_command(prompt)
  }
  let mut active_command = command
  let runtime_result = match
    collect_agent_command_output(
      store, run_id, worker_id, attempt, root, project, workspace_path, command,
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
  if append_command_log(
      artifacts.agent_log_path,
      "agent run",
      active_command,
      exit_code,
      output,
    )
    is Err(message) {
    return Err(
      runtime_failure_with_debug(
        "The AI builder could not write run logs.",
        message,
        thread_id_before,
        Some(failure_debug("AI builder logs", None, None, Some(artifacts))),
      ),
    )
  }
  let mut thread_id = thread_id_before
  if extract_runtime_session_id(output) is Some(runtime_session_id) {
    thread_id = Some(runtime_session_id)
  }
  if thread_id_before is None && thread_id is None {
    return Err(
      runtime_failure_with_debug(
        ai_builder_failure_assistant_message(
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
    let recovery_command = fake_runtime_send_command(recovery_prompt_text)
    let recovery_result = match
      collect_agent_command_output(
        store, run_id, worker_id, attempt, root, project, workspace_path, recovery_command,
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
    if append_command_log(
        artifacts.agent_log_path,
        "runtime session recovery",
        active_command,
        recovery_exit_code,
        recovery_output,
      )
      is Err(message) {
      return Err(
        runtime_failure_with_debug(
          "The builder session recovered, but writing run logs failed.",
          message,
          thread_id_before,
          Some(failure_debug("AI builder logs", None, None, Some(artifacts))),
        ),
      )
    }
    let recovery_thread_id = match extract_runtime_session_id(recovery_output) {
      Some(runtime_session_id) => runtime_session_id
      None =>
        return Err(
          runtime_failure_with_debug(
            ai_builder_failure_assistant_message(
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
        @async_fs.read_file(artifacts.last_message_path).text() catch {
          _ => ""
        },
        default_success_summary(),
      )
  }
  Ok({ summary, thread_id: Some(thread_id), artifacts })
}

///|
fn preview_audit_script_path(root : String) -> String {
  "\{root}/scripts/preview_audit.sh"
}

///|
fn preview_audit_log_path(
  root : String,
  project_id : String,
  run_id : String,
) -> String {
  "\{run_artifacts_dir(root, project_id, run_id)}/preview-audit.log"
}

///|
async fn preview_audit_auto_available(root : String) -> Bool noraise {
  @async_fs.exists(preview_audit_script_path(root)) catch {
    _ => false
  }
}

///|
async fn preview_audit_enabled(root : String) -> Bool noraise {
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
  if append_command_log(
      preview_audit_log_path(root, project_id, run_id),
      "HTTP preview audit",
      command,
      exit_code,
      output,
    )
    is Err(message) {
    return { enabled: true, passed: false, message }
  }
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
  thread_id : String?,
  artifacts : RunArtifacts,
) -> Result[Unit, AgentTurnFailure] noraise {
  match snapshot_workspace(store, root, project_id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) =>
      Err(
        runtime_failure_with_debug(
          "The workspace was updated, but saving the latest project snapshot failed.",
          message,
          thread_id,
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
  worker_id : String,
  attempt : Int,
  user_prompt : String,
  raw_prompt? : Bool = false,
  resume_existing? : Bool = true,
) -> Result[AgentTurnSuccess, AgentTurnFailure] noraise {
  let runtime_result = if smoke_runtime_enabled() {
    match
      run_runtime_turn(
        store,
        self.root,
        project,
        initial_project_prompt,
        workspace_path,
        run_id,
        worker_id,
        attempt,
        user_prompt,
        raw_prompt~,
        resume_existing~,
      ) {
      Ok(result) => result
      Err(failure) => return Err(failure)
    }
  } else {
    let endpoint = match
      self.ensure_project_runtime_service(store, project.id) {
      Ok(endpoint) => endpoint
      Err(message) =>
        return Err(
          runtime_failure(
            "The app builder runtime is not ready. Please retry after the server is updated.",
            message,
            project.runtime_session_id,
          ),
        )
    }
    let artifacts = RunArtifacts::new(self.root, project.id, run_id) catch {
      err =>
        return Err(
          runtime_failure(
            "The app builder runtime could not prepare run artifacts.",
            "Run artifact directory could not be created: \{err}",
            project.runtime_session_id,
          ),
        )
    }
    match
      run_runtime_service_turn(
        store, endpoint, project, run_id, worker_id, attempt, user_prompt, artifacts,
      ) {
      Ok(result) => result
      Err(failure) => return Err(failure)
    }
  }
  store.append_worker_run_event(
    project.id,
    run_id,
    worker_id,
    attempt,
    "status",
    @sdk.run_event_code_workspace_saving(),
    "Saving the updated workspace.",
  )
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
  Ok({ summary: runtime_result.summary, thread_id: runtime_result.thread_id })
}

///|
async fn AppContext::spawn_project_turn_worker(
  self : AppContext,
  project_id : String,
  run_id : String,
  worker_id : String,
  attempt : Int,
) -> Result[Int, String] noraise {
  let executable_path = control_plane_executable_path(
    self.root,
    self.build_profile,
  )
  let executable_exists = @async_fs.exists(executable_path) catch {
    err =>
      return Err(
        "The background run worker executable could not be checked at \{executable_path}: \{err}",
      )
  }
  if !executable_exists {
    return Err(
      "The background run worker executable was not found at \{executable_path}. Build the control plane before sending a request.",
    )
  }
  let artifacts = RunArtifacts::new(self.root, project_id, run_id) catch {
    err => return Err("Run artifact directory could not be created: \{err}")
  }
  let worker_log_path = "\{artifacts.dir}/worker.log"
  spawn_worker_process(
    self.root,
    executable_path,
    worker_log_path,
    project_id,
    run_id,
    worker_id,
    attempt,
  )
}

///|
async fn AppContext::run_project_turn(
  self : AppContext,
  project_id : String,
  run_id : String,
  worker_id : String,
  attempt : Int,
) -> Unit {
  @async.with_task_group(group => {
    let done : Ref[Bool] = @ref.new(false)
    defer {
      done.val = true
    }
    group.spawn_bg(() => {
      while !done.val {
        self.store.touch_run_worker(
          project_id,
          run_id,
          worker_id,
          attempt,
          AgentRunning,
        )
        @async.sleep(5000) catch {
          _ => return
        }
      }
    })
    ProjectRunWorkflow::from_context(self, worker_id, attempt).run(
      project_id, run_id,
    )
  })
}

///|
fn worker_process_args(
  project_id : String,
  run_id : String,
  worker_id : String,
  attempt : Int,
) -> Array[String] {
  let args : Array[String] = []
  args.push("run-worker")
  args.push(project_id)
  args.push(run_id)
  args.push(worker_id)
  args.push(attempt.to_string())
  args
}

///|
async fn spawn_worker_process(
  root : String,
  executable_path : String,
  log_path : String,
  project_id : String,
  run_id : String,
  worker_id : String,
  attempt : Int,
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
      worker_process_args(project_id, run_id, worker_id, attempt),
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
  worker_id : String,
  attempt : Int,
) -> Unit {
  let ctx = match AppContext::try_new_for_worker_async(root) {
    Ok(ctx) => ctx
    Err(message) => abort("MoonCraft worker cannot start: \{message}")
  }
  ctx.run_project_turn(project_id, run_id, worker_id, attempt)
}
