///|
pub fn run_event_code_agent_progress() -> String {
  "agent_progress"
}

///|
pub fn run_event_code_builder_auth_preparing() -> String {
  "builder_auth_preparing"
}

///|
pub fn run_event_code_builder_environment_preparing() -> String {
  "builder_environment_preparing"
}

///|
pub fn run_event_code_builder_ended() -> String {
  "builder_ended"
}

///|
pub fn run_event_code_builder_failed() -> String {
  "builder_failed"
}

///|
pub fn run_event_code_builder_mounts_preparing() -> String {
  "builder_mounts_preparing"
}

///|
pub fn run_event_code_builder_started() -> String {
  "builder_started"
}

///|
pub fn run_event_code_files_editing() -> String {
  "files_editing"
}

///|
pub fn run_event_code_files_updated() -> String {
  "files_updated"
}

///|
pub fn run_event_code_local_builder_running() -> String {
  "local_builder_running"
}

///|
pub fn run_event_code_preview_preparing() -> String {
  "preview_preparing"
}

///|
pub fn run_event_code_preview_repairing() -> String {
  "preview_repairing"
}

///|
pub fn run_event_code_provider_retrying() -> String {
  "provider_retrying"
}

///|
pub fn run_event_code_runtime_container_launching() -> String {
  "runtime_container_launching"
}

///|
pub fn run_event_code_runtime_container_running() -> String {
  "runtime_container_running"
}

///|
pub fn run_event_code_runtime_image_pulling() -> String {
  "runtime_image_pulling"
}

///|
pub fn run_event_code_runtime_image_ready() -> String {
  "runtime_image_ready"
}

///|
pub fn run_event_code_stopping_builder() -> String {
  "stopping_builder"
}

///|
pub fn run_event_code_turn_planning() -> String {
  "turn_planning"
}

///|
pub fn run_event_code_workspace_check_failed() -> String {
  "workspace_check_failed"
}

///|
pub fn run_event_display_text(code : String, content : String) -> String {
  match code {
    "builder_auth_preparing" => "Preparing auth"
    "builder_environment_preparing" => "Preparing"
    "builder_ended" => "Finalizing"
    "builder_failed" => "Failed"
    "builder_mounts_preparing" => "Preparing workspace"
    "builder_started" => "Starting"
    "files_editing" => "Editing files"
    "files_updated" => "Updated files"
    "local_builder_running" => "Building"
    "preview_preparing" => "Preparing preview"
    "preview_repairing" => "Repairing preview"
    "provider_retrying" => "Waiting for provider"
    "runtime_container_launching" => "Launching runtime"
    "runtime_container_running" => "Runtime running"
    "runtime_image_pulling" => "Pulling runtime image"
    "runtime_image_ready" => "Runtime image ready"
    "stopping_builder" => "Stopping"
    "turn_planning" => "Planning"
    "workspace_check_failed" => "Fixing workspace"
    _ => if content == "" { "Starting" } else { content }
  }
}
