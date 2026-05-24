///|
priv enum AgentAdapter {
  Codex
  Claude
}

///|
priv struct RuntimeDisplayEvent {
  kind : String
  code : String
  content : String
}

///|
fn runtime_display_event_value(
  kind : String,
  code : String,
  content : String,
) -> RuntimeDisplayEvent {
  { kind, code, content }
}

///|
fn runtime_activity_event_value(
  code : String,
  content : String,
) -> RuntimeDisplayEvent {
  runtime_display_event_value("activity", code, content)
}

///|
fn AgentAdapter::from_cli(agent_cli : String) -> Result[AgentAdapter, String] {
  match agent_cli {
    "codex" => Ok(Codex)
    "claude" => Ok(Claude)
    _ => Err("Unsupported Runtime agent: \{agent_cli}")
  }
}

///|
fn AgentAdapter::from_command_name(command_name : String) -> AgentAdapter? {
  match command_name {
    "codex" => Some(Codex)
    "claude" => Some(Claude)
    _ => None
  }
}

///|
fn AgentAdapter::session_id_field(self : AgentAdapter) -> String {
  match self {
    Codex => "thread_id"
    Claude => "session_id"
  }
}

///|
fn AgentAdapter::openrouter_env_file_content(
  self : AgentAdapter,
  config : AgentRuntimeConfig,
) -> String {
  if config.auth_kind != "openrouter_api_key" {
    return ""
  }
  match self {
    Codex =>
      "OPENROUTER_API_KEY=" + docker_env_value(config.secret.value) + "\n"
    Claude =>
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
  }
}

///|
fn agent_openrouter_env_file_content(config : AgentRuntimeConfig) -> String {
  match AgentAdapter::from_cli(config.agent_cli) {
    Ok(adapter) => adapter.openrouter_env_file_content(config)
    Err(_) => ""
  }
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
fn AgentAdapter::prepare_auth(
  self : AgentAdapter,
  config : AgentRuntimeConfig,
  agent_home_path : String,
) -> Result[Unit, String] {
  match self {
    Codex =>
      if config.auth_kind == "openrouter_api_key" {
        write_codex_openrouter_config(config, agent_home_path)
      }
    Claude => ignore(())
  }
  Ok(())
}

///|
async fn prepare_agent_auth(
  config : AgentRuntimeConfig,
  agent_home_path : String,
) -> Result[Unit, String] noraise {
  match materialize_runtime_file_secrets(config, agent_home_path) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  match AgentAdapter::from_cli(config.agent_cli) {
    Ok(adapter) => adapter.prepare_auth(config, agent_home_path)
    Err(message) => Err(message)
  }
}

///|
fn agent_system_prompt(root : String) -> String {
  safe_read_string_or(
    root + "/docker/agent-runtime/mooncraft-agent-system.md",
    "",
  )
}

///|
fn AgentAdapter::command(
  self : AgentAdapter,
  root : String,
  config : AgentRuntimeConfig,
  prompt : String,
  resume_existing : Bool,
) -> Array[String] {
  match self {
    Codex => codex_agent_command(config, prompt, resume_existing)
    Claude => claude_agent_command(root, config, prompt, resume_existing)
  }
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
  match AgentAdapter::from_cli(config.agent_cli) {
    Ok(adapter) => Ok(adapter.command(root, config, prompt, resume_existing))
    Err(message) => Err(message)
  }
}

///|
fn json_object_fields(line : String) -> Map[String, Json]? {
  let parsed = @json.parse(line) catch { _ => return None }
  match parsed {
    Object(fields) => Some(fields)
    _ => None
  }
}

///|
fn json_line_string_field(line : String, field : String) -> String? {
  match json_object_fields(line) {
    Some(fields) => json_string_field(fields, field)
    None => None
  }
}

///|
fn extract_json_lines_string_field(events : String, field : String) -> String? {
  let mut session_id : String? = None
  for raw_line in events.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    match json_line_string_field(line, field) {
      Some(value) if value.trim() != "" => session_id = Some(value)
      _ => ()
    }
  }
  session_id
}

///|
fn AgentAdapter::extract_session_id(
  self : AgentAdapter,
  events : String,
) -> String? {
  extract_json_lines_string_field(events, self.session_id_field())
}

///|
fn extract_fake_runtime_session_id(events : String) -> String? {
  extract_json_lines_string_field(events, "runtime_session_id")
}

///|
fn extract_agent_session_id(events : String, agent : String) -> String? {
  match AgentAdapter::from_cli(agent) {
    Ok(adapter) => adapter.extract_session_id(events)
    Err(_) => extract_fake_runtime_session_id(events)
  }
}

///|
fn json_string_field(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_object_field(
  fields : Map[String, Json],
  name : String,
) -> Map[String, Json]? {
  match fields.get(name) {
    Some(Object(value)) => Some(value)
    _ => None
  }
}

///|
fn json_bool_field(fields : Map[String, Json], name : String) -> Bool? {
  match fields.get(name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn claude_message_content(fields : Map[String, Json]) -> Array[Json]? {
  match fields.get("message") {
    Some(Object(message)) =>
      match message.get("content") {
        Some(Array(items)) => Some(items)
        _ => None
      }
    _ => None
  }
}

///|
fn claude_content_text(items : Array[Json]) -> String? {
  for item in items {
    match item {
      Object(content) =>
        match json_string_field(content, "type") {
          Some("text") =>
            match json_string_field(content, "text") {
              Some(text) if text.trim() != "" => return Some(text)
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  None
}

///|
fn claude_tool_description(items : Array[Json]) -> String? {
  for item in items {
    match item {
      Object(content) =>
        match json_string_field(content, "type") {
          Some("tool_use") => {
            let tool_name = json_string_field(content, "name").unwrap_or("")
            if tool_name == "Edit" {
              return Some("Editing project files.")
            }
            if tool_name == "Read" {
              return Some("Inspecting project files.")
            }
            match content.get("input") {
              Some(Object(input)) =>
                match json_string_field(input, "description") {
                  Some(description) if description.trim() != "" =>
                    return Some(description)
                  _ => ()
                }
              _ => ()
            }
            if tool_name != "" {
              return Some("Using \{tool_name}.")
            }
          }
          _ => ()
        }
      _ => ()
    }
  }
  None
}

///|
fn claude_tool_result_failed(items : Array[Json]) -> Bool {
  for item in items {
    match item {
      Object(content) =>
        match json_string_field(content, "type") {
          Some("tool_result") =>
            match json_bool_field(content, "is_error") {
              Some(true) => return true
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  false
}

///|
fn claude_stream_display_event(trimmed : String) -> RuntimeDisplayEvent? {
  match json_object_fields(trimmed) {
    Some(fields) => {
      let event_type = json_string_field(fields, "type").unwrap_or("")
      let subtype = json_string_field(fields, "subtype").unwrap_or("")
      match event_type {
        "system" =>
          match subtype {
            "init" =>
              Some(
                runtime_display_event_value(
                  "status",
                  @sdk.run_event_code_builder_started(),
                  "Started the builder session.",
                ),
              )
            "api_retry" =>
              Some(
                runtime_display_event_value(
                  "status",
                  @sdk.run_event_code_provider_retrying(),
                  "Waiting for the model provider to retry the request.",
                ),
              )
            "task_started" =>
              match json_string_field(fields, "description") {
                Some(description) if description.trim() != "" =>
                  Some(
                    runtime_activity_event_value(
                      @sdk.run_event_code_activity_tool_running(),
                      description,
                    ),
                  )
                _ => None
              }
            "task_notification" =>
              match json_string_field(fields, "summary") {
                Some(summary) if summary.trim() != "" => {
                  let code = match json_string_field(fields, "status") {
                    Some("completed") =>
                      @sdk.run_event_code_activity_tool_completed()
                    Some("failed") | Some("stopped") =>
                      @sdk.run_event_code_activity_tool_error()
                    _ => @sdk.run_event_code_activity_tool_running()
                  }
                  Some(runtime_activity_event_value(code, summary))
                }
                _ => None
              }
            _ => None
          }
        "assistant" =>
          match claude_message_content(fields) {
            Some(items) =>
              match claude_content_text(items) {
                Some(text) =>
                  Some(
                    runtime_activity_event_value(
                      @sdk.run_event_code_activity_message(),
                      text,
                    ),
                  )
                None =>
                  match claude_tool_description(items) {
                    Some(description) =>
                      Some(
                        runtime_activity_event_value(
                          @sdk.run_event_code_activity_tool_running(),
                          description,
                        ),
                      )
                    None => None
                  }
              }
            None => None
          }
        "user" =>
          match claude_message_content(fields) {
            Some(items) =>
              if claude_tool_result_failed(items) {
                Some(
                  runtime_activity_event_value(
                    @sdk.run_event_code_activity_tool_error(),
                    "A workspace check failed; the builder is fixing it.",
                  ),
                )
              } else {
                None
              }
            None => None
          }
        "result" =>
          match subtype {
            "success" =>
              Some(
                runtime_display_event_value(
                  "status",
                  @sdk.run_event_code_builder_ended(),
                  "Builder session ended.",
                ),
              )
            "error" =>
              Some(
                runtime_display_event_value(
                  "status",
                  @sdk.run_event_code_builder_failed(),
                  "The app update failed.",
                ),
              )
            _ => None
          }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn codex_agent_message_display_event(
  fields : Map[String, Json],
) -> RuntimeDisplayEvent? {
  match json_string_field(fields, "text") {
    Some(text) if text.trim() != "" =>
      Some(
        runtime_activity_event_value(
          @sdk.run_event_code_activity_message(),
          text,
        ),
      )
    _ => None
  }
}

///|
fn codex_file_change_display_event(
  fields : Map[String, Json],
) -> RuntimeDisplayEvent? {
  match json_string_field(fields, "status") {
    Some("completed") =>
      Some(
        runtime_activity_event_value(
          @sdk.run_event_code_activity_files_updated(),
          "Updated project files.",
        ),
      )
    _ =>
      Some(
        runtime_activity_event_value(
          @sdk.run_event_code_activity_files_editing(),
          "Editing project files.",
        ),
      )
  }
}

///|
fn codex_command_execution_display_event(
  fields : Map[String, Json],
) -> RuntimeDisplayEvent? {
  match json_string_field(fields, "status") {
    Some("failed") =>
      Some(
        runtime_activity_event_value(
          @sdk.run_event_code_activity_tool_error(),
          "A workspace check failed; the builder is fixing it.",
        ),
      )
    Some("completed") =>
      Some(
        runtime_activity_event_value(
          @sdk.run_event_code_activity_tool_completed(),
          "Finished command.",
        ),
      )
    _ =>
      Some(
        runtime_activity_event_value(
          @sdk.run_event_code_activity_tool_running(),
          "Running command.",
        ),
      )
  }
}

///|
fn codex_item_display_event(fields : Map[String, Json]) -> RuntimeDisplayEvent? {
  match json_object_field(fields, "item") {
    Some(item) =>
      match json_string_field(item, "type") {
        Some("agent_message") => codex_agent_message_display_event(item)
        Some("file_change") => codex_file_change_display_event(item)
        Some("command_execution") => codex_command_execution_display_event(item)
        _ => None
      }
    None => None
  }
}

///|
fn codex_stream_display_event(trimmed : String) -> RuntimeDisplayEvent? {
  match json_object_fields(trimmed) {
    Some(fields) => {
      let event_type = json_string_field(fields, "type").unwrap_or("")
      match event_type {
        "runtime.started" | "thread.started" =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_builder_started(),
              "Started the builder session.",
            ),
          )
        "turn.started" =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_turn_planning(),
              "Planning the change.",
            ),
          )
        "turn.completed" =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_builder_ended(),
              "Builder session ended.",
            ),
          )
        "turn.failed" =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_builder_failed(),
              "The app update failed.",
            ),
          )
        "agent_message" => codex_agent_message_display_event(fields)
        "file_change" => codex_file_change_display_event(fields)
        "command_execution" => codex_command_execution_display_event(fields)
        "item.started" | "item.completed" => codex_item_display_event(fields)
        _ => None
      }
    }
    None => None
  }
}

///|
fn AgentAdapter::display_event(
  self : AgentAdapter,
  trimmed : String,
) -> RuntimeDisplayEvent? {
  match self {
    Codex => codex_stream_display_event(trimmed)
    Claude => claude_stream_display_event(trimmed)
  }
}

///|
fn agent_stream_display_event(trimmed : String) -> RuntimeDisplayEvent? {
  match Codex.display_event(trimmed) {
    Some(event) => return Some(event)
    None => ()
  }
  Claude.display_event(trimmed)
}

///|
fn runtime_display_event(line : String) -> RuntimeDisplayEvent? {
  let trimmed = line.trim().to_owned()
  if trimmed == "" {
    return None
  }
  if !trimmed.has_prefix("{") {
    if trimmed.contains("Unable to find image") ||
      trimmed.contains("Pulling from") {
      return Some(
        runtime_display_event_value(
          "status",
          @sdk.run_event_code_runtime_image_pulling(),
          "Pulling the Runtime image.",
        ),
      )
    }
    if trimmed.contains("Status: Image is up to date") ||
      trimmed.contains("Status: Downloaded newer image") {
      return Some(
        runtime_display_event_value(
          "status",
          @sdk.run_event_code_runtime_image_ready(),
          "Runtime image is ready.",
        ),
      )
    }
    return None
  }
  agent_stream_display_event(trimmed)
}

///|
fn AgentAdapter::redact_command_arg(
  self : AgentAdapter,
  command : Array[String],
  index : Int,
) -> String? {
  match self {
    Codex => if index == command.length() - 1 { Some("<prompt>") } else { None }
    Claude =>
      if index > 0 && command[index - 1] == "-p" {
        Some("<prompt>")
      } else if index > 0 && command[index - 1] == "--append-system-prompt" {
        Some("<system-prompt>")
      } else {
        None
      }
  }
}

///|
fn command_display(command : Array[String]) -> String {
  let adapter = if command.length() > 0 {
    AgentAdapter::from_command_name(command[0])
  } else {
    None
  }
  let mut text = ""
  for index in 0..<command.length() {
    if index > 0 {
      text = text + " "
    }
    let part = match adapter {
      Some(adapter) =>
        match adapter.redact_command_arg(command, index) {
          Some(redacted) => redacted
          None => command[index]
        }
      None => command[index]
    }
    text = text + shell_quote(part)
  }
  text
}
