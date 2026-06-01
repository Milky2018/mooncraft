///|
priv struct GitHubCreateRepositoryRequest {
  name : String
  description : String
  private : Bool
  auto_init : Bool
} derive(ToJson)

///|
fn project_source_repository_name(project_id : String) -> String {
  "mooncraft-\{project_id}"
}

///|
fn github_create_repository_body(
  project_id : String,
  display_name : String,
) -> String {
  GitHubCreateRepositoryRequest::{
    name: project_source_repository_name(project_id),
    description: "MoonCraft project: \{display_name}",
    private: true,
    auto_init: false,
  }
  .to_json()
  .stringify()
}

///|
fn disconnected_project_source_repository(
  message : String,
) -> @sdk.ProjectSourceRepository {
  {
    host: "github",
    repository_id: "",
    owner: "",
    name: "",
    clone_url: "",
    default_branch: "main",
    ready_commit_sha: None,
    status: "source_disconnected",
    last_error: Some(message),
  }
}

///|
fn smoke_project_source_repository(
  project_id : String,
) -> @sdk.ProjectSourceRepository {
  {
    host: "smoke",
    repository_id: project_id,
    owner: "smoke",
    name: project_id,
    clone_url: "smoke://\{project_id}",
    default_branch: "main",
    ready_commit_sha: None,
    status: "connected",
    last_error: None,
  }
}

///|
fn github_repository_from_response(
  body : String,
) -> Result[@sdk.ProjectSourceRepository, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("GitHub returned an invalid repository response.")
  }
  match parsed {
    Object(fields) => {
      let repository_id = match github_id_field(fields) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let name = match github_required_string_field(fields, "name") {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let clone_url = match github_required_string_field(fields, "clone_url") {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let default_branch = match
        github_required_string_field(fields, "default_branch") {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let owner = match fields.get("owner") {
        Some(Object(owner_fields)) =>
          match github_required_string_field(owner_fields, "login") {
            Ok(value) => value
            Err(message) => return Err(message)
          }
        _ => return Err("GitHub returned a repository without an owner.")
      }
      Ok({
        host: "github",
        repository_id,
        owner,
        name,
        clone_url,
        default_branch,
        ready_commit_sha: None,
        status: "connected",
        last_error: None,
      })
    }
    _ => Err("GitHub returned an invalid repository response.")
  }
}

///|
async fn AppContext::create_project_source_repository(
  self : AppContext,
  user : @sdk.UserSummary,
  project_id : String,
  display_name : String,
) -> @sdk.ProjectSourceRepository noraise {
  if smoke_runtime_enabled() {
    return smoke_project_source_repository(project_id)
  }
  let access_token = match
    self.store.get_oauth_access_token(user.id, github_provider_name()) {
    Some(token) => token
    None =>
      return disconnected_project_source_repository(
        "GitHub repository access is not connected. Sign in with GitHub again.",
      )
  }
  let headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": "Bearer \{access_token}",
    "Content-Type": "application/json",
    "User-Agent": "mooncraft",
    "X-GitHub-Api-Version": "2022-11-28",
  }
  let response = match
    http_post(
      "https://api.github.com/user/repos",
      github_create_repository_body(project_id, display_name),
      headers~,
    ) {
    Ok(response) => response
    Err(message) => return disconnected_project_source_repository(message)
  }
  if !http_status_success(response.code) {
    return disconnected_project_source_repository(
      "GitHub Project Source Repository could not be created.",
    )
  }
  match github_repository_from_response(http_response_text(response)) {
    Ok(source) => source
    Err(message) => disconnected_project_source_repository(message)
  }
}

///|
async fn AppContext::refresh_project_source_repository(
  self : AppContext,
  user : @sdk.UserSummary,
  project : @sdk.ProjectDetail,
) -> Result[@sdk.ProjectSourceRepository, String] noraise {
  let current = match project.source_repository {
    Some(source) => source
    None => return Err("Project Source Repository is not configured.")
  }
  if current.status == "source_disconnected" {
    return Err("Project Source Repository is disconnected.")
  }
  if smoke_runtime_enabled() && current.host == "smoke" {
    return Ok(current)
  }
  let access_token = match
    self.store.get_oauth_access_token(user.id, github_provider_name()) {
    Some(token) => token
    None => {
      let disconnected = {
        ..current,
        status: "source_disconnected",
        last_error: Some(
          "GitHub repository access is not connected. Sign in with GitHub again.",
        ),
      }
      ignore(
        self.store.save_project_source_repository(project.id, disconnected),
      )
      return Err("Project Source Repository is disconnected.")
    }
  }
  let headers = github_api_headers(access_token)
  let owner = oauth_url_encode(current.owner)
  let name = oauth_url_encode(current.name)
  let response = match
    http_get("https://api.github.com/repos/\{owner}/\{name}", headers~) {
    Ok(response) => response
    Err(message) => {
      let disconnected = {
        ..current,
        status: "source_disconnected",
        last_error: Some(message),
      }
      ignore(
        self.store.save_project_source_repository(project.id, disconnected),
      )
      return Err("Project Source Repository is disconnected.")
    }
  }
  if !http_status_success(response.code) {
    let disconnected = {
      ..current,
      status: "source_disconnected",
      last_error: Some("GitHub Project Source Repository is unavailable."),
    }
    ignore(self.store.save_project_source_repository(project.id, disconnected))
    return Err("Project Source Repository is disconnected.")
  }
  let refreshed = match
    github_repository_from_response(http_response_text(response)) {
    Ok(source) => { ..source, ready_commit_sha: current.ready_commit_sha }
    Err(message) => {
      let disconnected = {
        ..current,
        status: "source_disconnected",
        last_error: Some(message),
      }
      ignore(
        self.store.save_project_source_repository(project.id, disconnected),
      )
      return Err("Project Source Repository is disconnected.")
    }
  }
  match self.store.save_project_source_repository(project.id, refreshed) {
    Ok(_) => Ok(refreshed)
    Err(message) => Err(message)
  }
}
