///|
fn route(
  http_method : HttpMethod,
  path_pattern : String,
  success_status : SuccessStatus,
) -> RouteSpec {
  { http_method, path_pattern, success_status }
}

///|
pub fn health_route() -> RouteSpec {
  route(GET, "/api/health", Ok)
}

///|
pub fn health_path() -> String {
  health_route().path_pattern
}

///|
pub fn login_path() -> String {
  "/login"
}

///|
pub fn github_login_path() -> String {
  "/login/github"
}

///|
pub fn session_route() -> RouteSpec {
  route(GET, "/api/session", Ok)
}

///|
pub fn session_path() -> String {
  session_route().path_pattern
}

///|
pub fn logout_route() -> RouteSpec {
  route(POST, "/api/auth/logout", NoContent)
}

///|
pub fn logout_path() -> String {
  logout_route().path_pattern
}

///|
pub fn admin_ai_keys_route() -> RouteSpec {
  route(GET, "/api/admin/ai/keys", Ok)
}

///|
pub fn create_admin_ai_key_route() -> RouteSpec {
  route(POST, "/api/admin/ai/keys", Created)
}

///|
pub fn admin_ai_keys_path() -> String {
  admin_ai_keys_route().path_pattern
}

///|
pub fn admin_ai_key_route() -> RouteSpec {
  route(PATCH, "/api/admin/ai/keys/:id", Ok)
}

///|
pub fn admin_ai_key_path(id : String) -> String {
  "/api/admin/ai/keys/\{id}"
}

///|
pub fn admin_ai_key_usages_recent_route() -> RouteSpec {
  route(GET, "/api/admin/ai/usages/recent/:limit", Ok)
}

///|
pub fn admin_ai_key_usages_recent_path(limit : Int) -> String {
  "/api/admin/ai/usages/recent/\{limit}"
}

///|
pub fn admin_ai_config_route() -> RouteSpec {
  route(GET, "/api/admin/ai/config", Ok)
}

///|
pub fn admin_ai_config_path() -> String {
  admin_ai_config_route().path_pattern
}

///|
pub fn admin_ai_models_route() -> RouteSpec {
  route(GET, "/api/admin/ai/models", Ok)
}

///|
pub fn admin_ai_models_path() -> String {
  admin_ai_models_route().path_pattern
}

///|
pub fn list_projects_route() -> RouteSpec {
  route(GET, "/api/projects", Ok)
}

///|
pub fn create_project_route() -> RouteSpec {
  route(POST, "/api/projects", Created)
}

///|
pub fn projects_path() -> String {
  list_projects_route().path_pattern
}

///|
pub fn project_route() -> RouteSpec {
  route(GET, "/api/projects/:id", Ok)
}

///|
pub fn update_project_route() -> RouteSpec {
  route(PUT, "/api/projects/:id", Ok)
}

///|
pub fn delete_project_route() -> RouteSpec {
  route(DELETE, "/api/projects/:id", NoContent)
}

///|
pub fn project_path(project_id : String) -> String {
  "/api/projects/\{project_id}"
}

///|
pub fn list_messages_route() -> RouteSpec {
  route(GET, "/api/projects/:id/messages", Ok)
}

///|
pub fn messages_path(project_id : String) -> String {
  "/api/projects/\{project_id}/messages"
}

///|
pub fn create_run_route() -> RouteSpec {
  route(POST, "/api/projects/:id/runs", Created)
}

///|
pub fn create_run_path(project_id : String) -> String {
  "/api/projects/\{project_id}/runs"
}

///|
pub fn get_run_route() -> RouteSpec {
  route(GET, "/api/projects/:id/runs/:run_id", Ok)
}

///|
pub fn run_path(project_id : String, run_id : String) -> String {
  "/api/projects/\{project_id}/runs/\{run_id}"
}

///|
pub fn list_run_events_route() -> RouteSpec {
  route(GET, "/api/projects/:id/runs/:run_id/events/:after_seq", Ok)
}

///|
pub fn run_events_path(
  project_id : String,
  run_id : String,
  after_seq : Int,
) -> String {
  "/api/projects/\{project_id}/runs/\{run_id}/events/\{after_seq}"
}

///|
pub fn admin_run_logs_route() -> RouteSpec {
  route(GET, "/api/admin/runs/:run_id/logs", Ok)
}

///|
pub fn admin_run_logs_path(run_id : String) -> String {
  "/api/admin/runs/\{run_id}/logs"
}

///|
pub fn admin_recent_runs_route() -> RouteSpec {
  route(GET, "/api/admin/runs/recent/:limit", Ok)
}

///|
pub fn admin_recent_runs_path(limit : Int) -> String {
  "/api/admin/runs/recent/\{limit}"
}

///|
pub fn admin_run_route() -> RouteSpec {
  route(GET, "/api/admin/runs/:run_id", Ok)
}

///|
pub fn admin_run_path(run_id : String) -> String {
  "/api/admin/runs/\{run_id}"
}

///|
pub fn admin_run_events_route() -> RouteSpec {
  route(GET, "/api/admin/runs/:run_id/events/:after_seq", Ok)
}

///|
pub fn admin_run_events_path(run_id : String, after_seq : Int) -> String {
  "/api/admin/runs/\{run_id}/events/\{after_seq}"
}

///|
pub fn admin_recent_projects_route() -> RouteSpec {
  route(GET, "/api/admin/projects/recent/:limit", Ok)
}

///|
pub fn admin_recent_projects_path(limit : Int) -> String {
  "/api/admin/projects/recent/\{limit}"
}

///|
pub fn admin_project_route() -> RouteSpec {
  route(GET, "/api/admin/projects/:project_id", Ok)
}

///|
pub fn admin_project_path(project_id : String) -> String {
  "/api/admin/projects/\{project_id}"
}

///|
pub fn preview_route_pattern() -> String {
  "/p/:preview_public_id/**"
}

///|
pub fn preview_public_path(preview_public_id : String) -> String {
  "/p/\{preview_public_id}/"
}
