///|
pub(all) enum RunState {
  Idle
  Running
  Succeeded
  Failed
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
  ai_provider : String
  ai_model : String
  ai_api_key_configured : Bool
  created_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct SessionResponse {
  authenticated : Bool
  user : UserSummary?
  github_enabled : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct PreviewTarget {
  url : String
  port : Int
  healthy : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProjectSummary {
  id : String
  display_name : String
  status : RunState
  preview : PreviewTarget?
  current_run_id : String?
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProjectDetail {
  id : String
  preview_public_id : String
  display_name : String
  workspace_path : String
  codex_thread_id : String?
  status : RunState
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
  display_name : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateProjectResponse {
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
pub(all) struct CreateRunRequest {
  content : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateRunResponse {
  run : RunStatusResponse
  poll_after_ms : Int?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct SignupRequest {
  email : String
  password : String
  display_name : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct LoginRequest {
  email : String
  password : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RequestPasswordResetRequest {
  email : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ResetPasswordRequest {
  token : String
  password : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ChangePasswordRequest {
  current_password : String
  new_password : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct VerifyEmailRequest {
  token : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AuthResponse {
  user : UserSummary
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AuthActionResponse {
  message : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AiSettingsResponse {
  provider : String
  model : String
  api_key_configured : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateAiSettingsRequest {
  provider : String
  model : String
  api_key : String
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
  }
}

///|
pub fn ChatRole::label(self : ChatRole) -> String {
  match self {
    User => "You"
    Assistant => "Mooncraft"
    System => "System"
  }
}
