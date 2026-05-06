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
pub fn request_password_reset_route() -> RouteSpec {
  route(POST, "/api/auth/password-reset/request", Ok)
}

///|
pub fn request_password_reset_path() -> String {
  request_password_reset_route().path_pattern
}

///|
pub fn reset_password_route() -> RouteSpec {
  route(POST, "/api/auth/password-reset/confirm", Ok)
}

///|
pub fn reset_password_path() -> String {
  reset_password_route().path_pattern
}

///|
pub fn change_password_route() -> RouteSpec {
  route(POST, "/api/auth/password/change", Ok)
}

///|
pub fn change_password_path() -> String {
  change_password_route().path_pattern
}

///|
pub fn resend_email_verification_route() -> RouteSpec {
  route(POST, "/api/auth/email/verification/resend", Ok)
}

///|
pub fn resend_email_verification_path() -> String {
  resend_email_verification_route().path_pattern
}

///|
pub fn verify_email_route() -> RouteSpec {
  route(POST, "/api/auth/email/verification/confirm", Ok)
}

///|
pub fn verify_email_path() -> String {
  verify_email_route().path_pattern
}

///|
pub fn ai_settings_route() -> RouteSpec {
  route(GET, "/api/account/ai-settings", Ok)
}

///|
pub fn update_ai_settings_route() -> RouteSpec {
  route(PUT, "/api/account/ai-settings", Ok)
}

///|
pub fn ai_settings_path() -> String {
  ai_settings_route().path_pattern
}

///|
pub fn ai_model_options_route() -> RouteSpec {
  route(GET, "/api/account/ai-model-options/:provider", Ok)
}

///|
pub fn ai_model_options_path(provider : String) -> String {
  "/api/account/ai-model-options/\{provider}"
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
