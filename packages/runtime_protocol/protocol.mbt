///|
pub fn runtime_service_health_path() -> String {
  "/health"
}

///|
pub fn runtime_service_init_path() -> String {
  "/init"
}

///|
pub fn runtime_service_exec_path() -> String {
  "/exec"
}

///|
pub fn runtime_service_preview_path() -> String {
  "/preview/"
}

///|
pub fn runtime_service_serve_path() -> String {
  "/serve"
}

///|
pub fn preview_cache_control(path : String) -> String {
  if path == "/" || path == "index.html" || path.has_suffix(".html") {
    "no-store"
  } else {
    "no-cache"
  }
}

///|
pub fn runtime_service_run_path(run_id : String) -> String {
  "/runs/\{run_id}"
}

///|
pub fn runtime_service_run_events_path(run_id : String, after : Int) -> String {
  "/runs/\{run_id}/events?after=\{after}"
}

///|
pub fn runtime_service_health_status_not_initialized() -> String {
  "not_initialized"
}

///|
pub fn runtime_service_health_status_ready() -> String {
  "ready"
}

///|
pub fn runtime_service_health_status_running() -> String {
  "running"
}

///|
pub fn runtime_service_run_status_running() -> String {
  "running"
}

///|
pub fn runtime_service_run_status_succeeded() -> String {
  "succeeded"
}

///|
pub fn runtime_service_run_status_failed() -> String {
  "failed"
}

///|
pub fn runtime_service_event_level_info() -> String {
  "info"
}

///|
pub fn runtime_service_event_level_warning() -> String {
  "warning"
}

///|
pub fn runtime_service_event_level_error() -> String {
  "error"
}

///|
pub fn runtime_service_not_initialized_message() -> String {
  "Runtime Service is not initialized. Call /init first."
}

///|
pub fn runtime_service_init_conflict_message() -> String {
  "Runtime Service is already initialized with different initialization data."
}

///|
pub(all) struct RuntimeServiceExecRequest {
  run_id : String
  prompt : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceProjectRef {
  id : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceSourceRepository {
  url : String
  default_branch : String
  current_commit_sha : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceSourceCredential {
  kind : String
  username : String
  password : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceSecret {
  name : String
  value : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceInitRequest {
  project : RuntimeServiceProjectRef
  source_repository : RuntimeServiceSourceRepository
  source_credential : RuntimeServiceSourceCredential
  secrets : Array[RuntimeServiceSecret]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceHealthResponse {
  status : String
  message : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceInitResponse {
  status : String
  current_commit_sha : String?
  message : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceRun {
  run_id : String
  status : String
  message : String
  ready_commit_sha : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceEvent {
  id : Int
  time : String
  level : String
  message : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceEventsResponse {
  events : Array[RuntimeServiceEvent]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceServeResponse {
  status : String
  message : String?
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct RuntimeServiceError {
  message : String
} derive(Debug, ToJson, FromJson)

///|
fn allowed_fields_check(
  fields : Map[String, Json],
  allowed : Array[String],
  label : String,
) -> Result[Unit, String] {
  for key in fields.keys() {
    if !allowed.any(fn(name) { name == key }) {
      return Err("\{label} field is not supported: \{key}")
    }
  }
  Ok(())
}

///|
fn object_fields(
  json : Json,
  label : String,
) -> Result[Map[String, Json], String] {
  match json {
    Object(fields) => Ok(fields)
    _ => Err("\{label} must be a JSON object.")
  }
}

///|
fn json_string_field(
  fields : Map[String, Json],
  name : String,
  label : String,
) -> Result[String, String] {
  match fields.get(name) {
    Some(String(value)) => Ok(value)
    _ => Err("\{label}.\{name} is required.")
  }
}

///|
fn json_optional_string_field(
  fields : Map[String, Json],
  name : String,
  label : String,
) -> Result[String?, String] {
  match fields.get(name) {
    Some(String(value)) => Ok(Some(value))
    Some(Null) | None => Ok(None)
    _ => Err("\{label}.\{name} must be a string or null.")
  }
}

///|
fn validate_init_request_shape(json : Json) -> Result[Unit, String] {
  let fields = match object_fields(json, "Runtime Service /init request") {
    Ok(fields) => fields
    Err(message) => return Err(message)
  }
  if allowed_fields_check(
      fields,
      ["project", "source_repository", "source_credential", "secrets"],
      "Runtime Service /init request",
    )
    is Err(message) {
    return Err(message)
  }
  match fields.get("project") {
    Some(value) =>
      match object_fields(value, "Runtime Service /init project") {
        Ok(project_fields) =>
          if allowed_fields_check(
              project_fields,
              ["id"],
              "Runtime Service /init project",
            )
            is Err(message) {
            return Err(message)
          }
        Err(message) => return Err(message)
      }
    None => ()
  }
  match fields.get("source_repository") {
    Some(value) =>
      match object_fields(value, "Runtime Service /init source_repository") {
        Ok(source_fields) =>
          if allowed_fields_check(
              source_fields,
              ["url", "default_branch", "current_commit_sha"],
              "Runtime Service /init source_repository",
            )
            is Err(message) {
            return Err(message)
          }
        Err(message) => return Err(message)
      }
    None => ()
  }
  match fields.get("source_credential") {
    Some(value) =>
      match object_fields(value, "Runtime Service /init source_credential") {
        Ok(credential_fields) =>
          if allowed_fields_check(
              credential_fields,
              ["kind", "username", "password"],
              "Runtime Service /init source_credential",
            )
            is Err(message) {
            return Err(message)
          }
        Err(message) => return Err(message)
      }
    None => ()
  }
  match fields.get("secrets") {
    Some(Array(items)) =>
      for index, item in items {
        match object_fields(item, "Runtime Service /init secrets[\{index}]") {
          Ok(secret_fields) =>
            if allowed_fields_check(
                secret_fields,
                ["name", "value"],
                "Runtime Service /init secrets[\{index}]",
              )
              is Err(message) {
              return Err(message)
            }
          Err(message) => return Err(message)
        }
      }
    Some(_) => return Err("Runtime Service /init secrets must be an array.")
    None => ()
  }
  Ok(())
}

///|
pub fn runtime_service_init_request_validate(
  request : RuntimeServiceInitRequest,
) -> Result[RuntimeServiceInitRequest, String] {
  if request.project.id.trim() == "" {
    return Err("project.id is required.")
  }
  if request.source_repository.url.trim() == "" {
    return Err("source_repository.url is required.")
  }
  if request.source_repository.default_branch.trim() == "" {
    return Err("source_repository.default_branch is required.")
  }
  if request.source_credential.kind != "git_https_token" ||
    request.source_credential.username.trim() == "" ||
    request.source_credential.password.trim() == "" {
    return Err("source_credential must be a git_https_token credential.")
  }
  for secret in request.secrets {
    if secret.name.trim() == "" {
      return Err("secret.name is required.")
    }
  }
  Ok(request)
}

///|
pub fn runtime_service_exec_request_validate(
  request : RuntimeServiceExecRequest,
) -> Result[RuntimeServiceExecRequest, String] {
  if request.run_id.trim() == "" {
    return Err("run_id is required.")
  }
  if request.prompt.trim() == "" {
    return Err("prompt is required.")
  }
  Ok({ run_id: request.run_id.trim().to_owned(), prompt: request.prompt })
}

///|
pub fn runtime_service_init_request_from_json_text(
  body : String,
) -> Result[RuntimeServiceInitRequest, String] {
  let json = @json.parse(body) catch {
    _ => return Err("Invalid JSON request body.")
  }
  if validate_init_request_shape(json) is Err(message) {
    return Err(message)
  }
  let fields = match object_fields(json, "Runtime Service /init request") {
    Ok(fields) => fields
    Err(message) => return Err(message)
  }
  let project_fields = match fields.get("project") {
    Some(value) =>
      match object_fields(value, "Runtime Service /init project") {
        Ok(fields) => fields
        Err(message) => return Err(message)
      }
    None => return Err("project.id is required.")
  }
  let source_fields = match fields.get("source_repository") {
    Some(value) =>
      match object_fields(value, "Runtime Service /init source_repository") {
        Ok(fields) => fields
        Err(message) => return Err(message)
      }
    None => return Err("source_repository.url is required.")
  }
  let credential_fields = match fields.get("source_credential") {
    Some(value) =>
      match object_fields(value, "Runtime Service /init source_credential") {
        Ok(fields) => fields
        Err(message) => return Err(message)
      }
    None =>
      return Err("source_credential must be a git_https_token credential.")
  }
  let secrets : Array[RuntimeServiceSecret] = []
  match fields.get("secrets") {
    Some(Array(items)) =>
      for item in items {
        let secret_fields = match
          object_fields(item, "Runtime Service /init secret") {
          Ok(fields) => fields
          Err(message) => return Err(message)
        }
        let name = match
          json_string_field(
            secret_fields, "name", "Runtime Service /init secret",
          ) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        let value = match
          json_string_field(
            secret_fields, "value", "Runtime Service /init secret",
          ) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        secrets.push({ name, value })
      }
    Some(_) => return Err("Runtime Service /init secrets must be an array.")
    None => return Err("Runtime Service /init secrets must be an array.")
  }
  let request : RuntimeServiceInitRequest = {
    project: {
      id: match
        json_string_field(project_fields, "id", "Runtime Service /init project") {
        Ok(value) => value
        Err(message) => return Err(message)
      },
    },
    source_repository: {
      url: match
        json_string_field(
          source_fields, "url", "Runtime Service /init source_repository",
        ) {
        Ok(value) => value
        Err(message) => return Err(message)
      },
      default_branch: match
        json_string_field(
          source_fields, "default_branch", "Runtime Service /init source_repository",
        ) {
        Ok(value) => value
        Err(message) => return Err(message)
      },
      current_commit_sha: match
        json_optional_string_field(
          source_fields, "current_commit_sha", "Runtime Service /init source_repository",
        ) {
        Ok(value) => value
        Err(message) => return Err(message)
      },
    },
    source_credential: {
      kind: match
        json_string_field(
          credential_fields, "kind", "Runtime Service /init source_credential",
        ) {
        Ok(value) => value
        Err(message) => return Err(message)
      },
      username: match
        json_string_field(
          credential_fields, "username", "Runtime Service /init source_credential",
        ) {
        Ok(value) => value
        Err(message) => return Err(message)
      },
      password: match
        json_string_field(
          credential_fields, "password", "Runtime Service /init source_credential",
        ) {
        Ok(value) => value
        Err(message) => return Err(message)
      },
    },
    secrets,
  }
  runtime_service_init_request_validate(request)
}

///|
pub fn runtime_service_exec_request_from_json_text(
  body : String,
) -> Result[RuntimeServiceExecRequest, String] {
  let json = @json.parse(body) catch {
    _ => return Err("Invalid JSON request body.")
  }
  let fields = match object_fields(json, "Runtime Service /exec request") {
    Ok(fields) => fields
    Err(message) => return Err(message)
  }
  if allowed_fields_check(
      fields,
      ["run_id", "prompt"],
      "Runtime Service /exec request",
    )
    is Err(message) {
    return Err(message)
  }
  let request : RuntimeServiceExecRequest = {
    run_id: match
      json_string_field(fields, "run_id", "Runtime Service /exec request") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    prompt: match
      json_string_field(fields, "prompt", "Runtime Service /exec request") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
  }
  runtime_service_exec_request_validate(request)
}

///|
pub fn[T : @json.FromJson] runtime_service_json_decode(
  body : String,
  label : String,
) -> Result[T, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("\{label} returned invalid JSON.")
  }
  Ok(
    @json.from_json(parsed) catch {
      _ => return Err("\{label} returned an unexpected response shape.")
    },
  )
}

///|
pub fn runtime_service_error_message_from_body(
  body : String,
  fallback : String,
) -> String {
  let parsed = @json.parse(body) catch { _ => return fallback }
  let error : RuntimeServiceError = @json.from_json(parsed) catch {
    _ => return fallback
  }
  if error.message.trim() == "" {
    fallback
  } else {
    error.message
  }
}

///|
pub fn runtime_service_validate_run_id(
  run : RuntimeServiceRun,
  expected_run_id : String,
  label : String,
) -> Result[RuntimeServiceRun, String] {
  if run.run_id == expected_run_id {
    Ok(run)
  } else {
    Err("\{label} returned a different run id.")
  }
}

///|
pub fn runtime_service_ready_commit(
  run : RuntimeServiceRun,
) -> Result[String, String] {
  match run.ready_commit_sha {
    Some(commit) if commit.trim() != "" => Ok(commit.trim().to_owned())
    _ =>
      Err(
        "Runtime Service reported success without a ready_commit_sha. The project source was not marked ready.",
      )
  }
}

///|
pub fn runtime_service_run_status_route(path : String) -> String? {
  let segments = path.split("/").to_array()
  if segments.length() == 3 &&
    segments[0] == "" &&
    segments[1] == "runs" &&
    segments[2] != "" {
    Some(segments[2].to_owned())
  } else {
    None
  }
}

///|
pub fn runtime_service_run_events_route(path : String) -> String? {
  let segments = path.split("/").to_array()
  if segments.length() == 4 &&
    segments[0] == "" &&
    segments[1] == "runs" &&
    segments[2] != "" &&
    segments[3] == "events" {
    Some(segments[2].to_owned())
  } else {
    None
  }
}

///|
pub fn runtime_service_preview_path_matches(path : String) -> Bool {
  path == "/preview" || path.has_prefix("/preview/")
}

///|
pub fn runtime_service_preview_upstream_path(path : String) -> String {
  if path == "/preview" || path == "/preview/" {
    "/"
  } else if path.has_prefix("/preview/") {
    path["/preview".length():].to_owned()
  } else {
    "/"
  }
}
