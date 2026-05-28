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
  RuntimeRunning
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
pub(all) struct ProjectActivity {
  run_id : String
  phase : RunPhase
  message_code : String?
  message : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeSecretTarget {
  kind : String
  name : String?
  path : String?
} derive(Debug)

///|
pub impl ToJson for RuntimeSecretTarget with fn to_json(self) {
  let fields = { "type": self.kind.to_json() }
  if self.name is Some(name) {
    fields["name"] = name.to_json()
  }
  if self.path is Some(path) {
    fields["path"] = path.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for RuntimeSecretTarget with fn from_json(json, path) {
  match json {
    Object(fields) => {
      let kind = match fields.get("type") {
        Some(String(value)) => value
        _ =>
          raise JsonDecodeError(
            (path.add_key("type"), "Runtime secret target type is required"),
          )
      }
      let name = match fields.get("name") {
        Some(String(value)) => Some(value)
        Some(Null) | None => None
        _ =>
          raise JsonDecodeError(
            (
              path.add_key("name"),
              "Runtime secret target name must be a string",
            ),
          )
      }
      let file_path = match fields.get("path") {
        Some(String(value)) => Some(value)
        Some(Null) | None => None
        _ =>
          raise JsonDecodeError(
            (
              path.add_key("path"),
              "Runtime secret target path must be a string",
            ),
          )
      }
      { kind, name, path: file_path }
    }
    _ =>
      raise JsonDecodeError(
        (path, "Runtime secret target must be a JSON object"),
      )
  }
}

///|
pub(all) struct RuntimeSecret {
  source : String
  target : RuntimeSecretTarget
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeSpec {
  protocol_version : Int
  image : String
  env : Map[String, String]
  secrets : Array[RuntimeSecret]
} derive(Debug)

///|
pub impl ToJson for RuntimeSpec with fn to_json(self) {
  let env_fields : Map[String, Json] = {}
  for key, value in self.env {
    env_fields[key] = value.to_json()
  }
  Json::object({
    "protocol_version": self.protocol_version.to_json(),
    "image": self.image.to_json(),
    "env": Json::object(env_fields),
    "secrets": self.secrets.to_json(),
  })
}

///|
pub impl @json.FromJson for RuntimeSpec with fn from_json(json, path) {
  match json {
    Object(fields) => {
      let protocol_version = match fields.get("protocol_version") {
        Some(Number(_, ..) as value) =>
          @string.parse_int(value.stringify()) catch {
            _ =>
              raise JsonDecodeError(
                (
                  path.add_key("protocol_version"),
                  "Runtime protocol_version must be an integer",
                ),
              )
          }
        Some(String(value)) =>
          @string.parse_int(value) catch {
            _ =>
              raise JsonDecodeError(
                (
                  path.add_key("protocol_version"),
                  "Runtime protocol_version must be an integer",
                ),
              )
          }
        _ =>
          raise JsonDecodeError(
            (
              path.add_key("protocol_version"),
              "Runtime protocol_version is required",
            ),
          )
      }
      let image = match fields.get("image") {
        Some(String(value)) => value
        _ =>
          raise JsonDecodeError(
            (path.add_key("image"), "Runtime image is required"),
          )
      }
      let env : Map[String, String] = {}
      match fields.get("env") {
        Some(Object(env_fields)) =>
          for key, value in env_fields {
            match value {
              String(text) => env[key] = text
              _ =>
                raise JsonDecodeError(
                  (
                    path.add_key("env").add_key(key),
                    "Runtime env value must be a string",
                  ),
                )
            }
          }
        Some(Null) | None => ()
        _ =>
          raise JsonDecodeError(
            (path.add_key("env"), "Runtime env must be an object"),
          )
      }
      let secrets : Array[RuntimeSecret] = []
      match fields.get("secrets") {
        Some(Array(items)) =>
          for item in items {
            let secret : RuntimeSecret = @json.from_json(item) catch {
              err =>
                raise JsonDecodeError(
                  (path.add_key("secrets"), "Runtime secret is invalid: \{err}"),
                )
            }
            secrets.push(secret)
          }
        Some(Null) | None => ()
        _ =>
          raise JsonDecodeError(
            (path.add_key("secrets"), "Runtime secrets must be an array"),
          )
      }
      { protocol_version, image, env, secrets }
    }
    _ => raise JsonDecodeError((path, "Runtime spec must be a JSON object"))
  }
}

///|
pub(all) struct RuntimeSummary {
  id : String
  name : String
  image : String
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
  is_processing : Bool
  activity : ProjectActivity?
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
  status : RunState
  is_processing : Bool
  activity : ProjectActivity?
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
  runtime_log_path : String?
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
  code : String
  content : String
  created_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateProjectRequest {
  display_name : String
  runtime_id : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateProjectResponse {
  project : ProjectDetail
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateProjectRequest {
  display_name : String?
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
pub(all) struct AdminSecretSummary {
  id : String
  name : String
  value_hint : String
  created_at : String
  updated_at : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AdminListSecretsResponse {
  items : Array[AdminSecretSummary]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CreateAdminSecretRequest {
  name : String
  value : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpdateAdminSecretRequest {
  name : String
  value : String
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
    RuntimeRunning => "Working"
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
