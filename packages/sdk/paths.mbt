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
pub fn session_route() -> RouteSpec {
  route(GET, "/api/session", Ok)
}

///|
pub fn session_path() -> String {
  session_route().path_pattern
}

///|
pub fn signup_route() -> RouteSpec {
  route(POST, "/api/auth/signup", Created)
}

///|
pub fn signup_path() -> String {
  signup_route().path_pattern
}

///|
pub fn login_route() -> RouteSpec {
  route(POST, "/api/auth/login", Ok)
}

///|
pub fn login_path() -> String {
  login_route().path_pattern
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
pub fn preview_route_pattern() -> String {
  "/p/:preview_public_id/**"
}

///|
pub fn preview_public_path(preview_public_id : String) -> String {
  "/p/\{preview_public_id}/"
}
