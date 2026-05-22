///|
pub(all) enum RunState {
  Idle
  Running
  Succeeded
  Failed
  Cancelled
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) enum RunPhase {
  NoPhase
  AgentRunning
  Checking
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) enum ChatRole {
  User
  Assistant
  System
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct UserSummary {
  id : String
  email : String
  email_verified : Bool
  display_name : String
  github_login : String?
  created_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct SessionResponse {
  authenticated : Bool
  user : UserSummary?
  github_enabled : Bool
  app_mode : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct PreviewTarget {
  url : String
  port : Int
  healthy : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeSecretBinding {
  source : String
  env : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeSpec {
  protocol_version : Int
  image : String
  agent : String
  model : String
  provider : String
  send : Array[String]
  container_home : String
  secrets : Array[RuntimeSecretBinding]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeSummary {
  id : String
  name : String
  agent : String
  model : String
  enabled : Bool
  is_default : Bool
  created_at : String
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeDetail {
  id : String
  name : String
  spec : RuntimeSpec
  spec_json : String
  enabled : Bool
  is_default : Bool
  created_at : String
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ListRuntimesResponse {
  default_runtime_id : String
  items : Array[RuntimeSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProjectSummary {
  id : String
  display_name : String
  runtime_id : String
  runtime_name : String
  agent_session_id : String
  agent_cli : String
  model : String
  status : RunState
  current_run_phase : RunPhase
  preview : PreviewTarget?
  current_run_id : String?
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProjectDetail {
  id : String
  preview_public_id : String
  display_name : String
  runtime_id : String
  runtime_name : String
  runtime_spec : RuntimeSpec?
  agent_session_id : String
  runtime_session_id : String?
  agent_cli : String
  model : String
  workspace_path : String
  codex_thread_id : String?
  status : RunState
  current_run_phase : RunPhase
  preview : PreviewTarget?
  current_run_id : String?
  last_error : String?
  created_at : String
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ChatMessage {
  id : String
  project_id : String
  run_id : String?
  role : ChatRole
  content : String
  created_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RunFailureDebug {
  stage : String
  command : String?
  exit_code : Int?
  codex_log_path : String?
  validation_log_path : String?
  final_summary_path : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RunStatusResponse {
  run_id : String
  project_id : String
  state : RunState
  phase : RunPhase
  summary : String?
  error_message : String?
  failure_debug : RunFailureDebug?
  preview : PreviewTarget?
  started_at : String
  finished_at : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RunEvent {
  seq : Int
  kind : String
  content : String
  created_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateProjectRequest {
  display_name : String
  runtime_id : String?
  agent_cli : String?
  model : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateProjectResponse {
  project : ProjectDetail
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateProjectRequest {
  display_name : String?
  model : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateProjectResponse {
  project : ProjectDetail
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ListProjectsResponse {
  items : Array[ProjectSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ListMessagesResponse {
  items : Array[ChatMessage]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ListRunEventsResponse {
  items : Array[RunEvent]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminRunLogFile {
  label : String
  path : String?
  exists : Bool
  truncated : Bool
  content : String?
  error : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminRunLogsResponse {
  run : RunStatusResponse
  events : Array[RunEvent]
  logs : Array[AdminRunLogFile]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListRunsResponse {
  items : Array[RunStatusResponse]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminUserSummary {
  user : UserSummary
  project_count : Int
  running_project_count : Int
  latest_project_updated_at : String?
  latest_run_started_at : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminUserDetail {
  user : UserSummary
  project_count : Int
  running_project_count : Int
  session_count : Int
  oauth_providers : Array[String]
  latest_project_updated_at : String?
  latest_run_started_at : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminProjectSummary {
  project : ProjectDetail
  owner : UserSummary?
  message_count : Int
  run_count : Int
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListUsersResponse {
  items : Array[AdminUserSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminUserDetailResponse {
  user : AdminUserDetail
  projects : Array[AdminProjectSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminUserProjectsResponse {
  user : UserSummary
  projects : Array[AdminProjectSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminProjectDiagnosticsResponse {
  project : AdminProjectSummary
  messages : Array[ChatMessage]
  runs : Array[RunStatusResponse]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListProjectsResponse {
  items : Array[AdminProjectSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminProjectMessagesResponse {
  project : AdminProjectSummary
  messages : Array[ChatMessage]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminAiKeySummary {
  id : String
  provider : String
  label : String
  key_hint : String
  status : String
  priority : Int
  last_used_at : String?
  last_error : String?
  created_at : String
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListAiKeysResponse {
  items : Array[AdminAiKeySummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateAdminAiKeyRequest {
  label : String
  api_key : String
  priority : Int
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateAdminAiKeyRequest {
  label : String
  api_key : String
  status : String
  priority : Int
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminAiKeyUsageSummary {
  id : String
  key_id : String
  run_id : String
  project_id : String
  user_id : String
  model : String
  state : String
  error_code : String?
  started_at : String
  finished_at : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListAiKeyUsagesResponse {
  items : Array[AdminAiKeyUsageSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListRuntimesResponse {
  default_runtime_id : String
  items : Array[RuntimeDetail]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateAdminRuntimeRequest {
  name : String
  spec_json : String
  enabled : Bool
  is_default : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateAdminRuntimeRequest {
  name : String
  spec_json : String
  enabled : Bool
  is_default : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminAiConfigResponse {
  default_model : String
  allowed_models : Array[String]
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminAiModelSummary {
  id : String
  name : String
  context_length : Int
  prompt_price : String
  completion_price : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AiModelSummary {
  id : String
  name : String
  context_length : Int
  prompt_price : String
  completion_price : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ListAiModelsResponse {
  default_agent_cli : String
  default_model : String
  items : Array[AiModelSummary]
  fetched_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListAiModelsResponse {
  items : Array[AdminAiModelSummary]
  fetched_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateAdminAiConfigRequest {
  default_model : String
  allowed_models : Array[String]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateRunRequest {
  content : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateRunResponse {
  run : RunStatusResponse
  poll_after_ms : Int?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CancelRunResponse {
  run : RunStatusResponse
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AuthResponse {
  user : UserSummary
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct HealthResponse {
  ok : Bool
} derive(Debug, ToJson, FromJson)

///|
pub fn RunState::label(self : RunState) -> String {
  match self {
    Idle => "Idle"
    Running => "Running"
    Succeeded => "Ready"
    Failed => "Needs attention"
    Cancelled => "Stopped"
  }
}

///|
pub fn RunPhase::label(self : RunPhase) -> String {
  match self {
    NoPhase => ""
    AgentRunning => "Working"
    Checking => "Checking"
  }
}

///|
pub fn ChatRole::label(self : ChatRole) -> String {
  match self {
    User => "You"
    Assistant => "MoonCraft"
    System => "System"
  }
}
