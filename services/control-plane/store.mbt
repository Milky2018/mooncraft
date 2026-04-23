///|
let id_counter : Ref[Int] = @ref.new(0)

///|
enum BuildProfile {
  Debug
  Release
}

///|
struct Store {
  db : @sqlite.Database
}

///|
pub(all) struct PreviewRuntime {
  port : Int
  pid : Int
}

///|
struct PreviewManager {
  root : String
  runtimes : Map[String, PreviewRuntime]
  build_profile : BuildProfile
}

///|
struct AgentGateway {
  root : String
}

///|
struct AppContext {
  root : String
  build_profile : BuildProfile
  store : Store
  previews : PreviewManager
  agent_gateway : AgentGateway
}

///|
fn now_string() -> String {
  @env.now().to_string()
}

///|
fn next_id(prefix : String) -> String {
  id_counter.val = id_counter.val + 1
  "\{prefix}-\{now_string()}-\{id_counter.val}"
}

///|
fn bytes_to_string(bytes : Bytes) -> String {
  @utf8.decode(bytes) catch {
    _ => ""
  }
}

///|
#borrow(command)
extern "C" fn shell_status_ffi(command : Bytes) -> Int = "moonbitcloud_shell_status"

///|
fn shell_status(command : String) -> Int {
  shell_status_ffi(@utf8.encode(command))
}

///|
fn safe_create_dir(path : String) -> Unit {
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn safe_write_string(path : String, content : String) -> Unit {
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}

///|
fn safe_append_string(path : String, content : String) -> Unit {
  safe_write_string(path, safe_read_string_or(path, "") + content)
}

///|
fn safe_write_bytes(path : String, content : Bytes) -> Unit {
  @fs.write_bytes_to_file(path, content) catch {
    _ => ()
  }
}

///|
fn safe_remove_tree(path : String) -> Unit {
  ignore(shell_status("rm -rf '\{path}' >/dev/null 2>&1"))
}

///|
fn safe_read_string_or(path : String, fallback : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => fallback
  }
}

///|
fn safe_read_bytes_or(path : String, fallback : Bytes) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    _ => fallback
  }
}

///|
fn string_to_sql_text(text : String) -> @sqlite.SqlValue {
  @sqlite.SqlValue::Text(@utf8.encode(text))
}

///|
fn bool_to_int(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
fn empty_to_none(value : String) -> String? {
  if value == "" {
    None
  } else {
    Some(value)
  }
}

///|
fn build_profile_from_env() -> BuildProfile {
  match @env.get_env_var("MOONBITCLOUD_BUILD_PROFILE") {
    Some(value) if value.to_lower() == "release" => Release
    _ => Debug
  }
}

///|
fn BuildProfile::build_dir(self : BuildProfile) -> String {
  match self {
    Debug => "debug"
    Release => "release"
  }
}

///|
fn BuildProfile::cli_flag(self : BuildProfile) -> String {
  match self {
    Debug => ""
    Release => "--release "
  }
}

///|
fn run_state_to_db(state : @sdk.RunState) -> String {
  match state {
    Idle => "idle"
    Running => "running"
    Succeeded => "succeeded"
    Failed => "failed"
  }
}

///|
fn run_state_from_db(value : String) -> @sdk.RunState {
  match value {
    "running" => Running
    "succeeded" => Succeeded
    "failed" => Failed
    _ => Idle
  }
}

///|
fn chat_role_to_db(role : @sdk.ChatRole) -> String {
  match role {
    User => "user"
    Assistant => "assistant"
    System => "system"
  }
}

///|
fn chat_role_from_db(value : String) -> @sdk.ChatRole {
  match value {
    "assistant" => Assistant
    "system" => System
    _ => User
  }
}

///|
fn ensure_dir(path : String) -> Unit {
  let parts = path.split("/").to_array()
  let mut current = if path.has_prefix("/") { "/" } else { "" }
  for part in parts {
    let piece = part.to_string()
    if piece == "" {
      continue
    }
    current = if current == "" || current == "/" {
      current + piece
    } else {
      current + "/" + piece
    }
    if !@fs.path_exists(current) {
      safe_create_dir(current)
    }
  }
}

///|
fn project_root(root : String, project_id : String) -> String {
  root + "/data/projects/" + project_id
}

///|
fn project_workspace(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/workspace"
}

///|
fn preview_dist_dir(workspace_path : String) -> String {
  workspace_path + "/preview-dist"
}

///|
fn public_preview_url(preview_public_id : String) -> String {
  @sdk.preview_public_path(preview_public_id)
}

///|
fn project_artifacts_root(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/artifacts"
}

///|
fn run_artifacts_dir(
  root : String,
  project_id : String,
  run_id : String,
) -> String {
  project_artifacts_root(root, project_id) + "/runs/" + run_id
}

///|
fn platform_web_dist_dir(root : String) -> String {
  root + "/data/platform/web"
}

///|
fn platform_web_staged_bundle_path(root : String) -> String {
  platform_web_dist_dir(root) + "/app.js"
}

///|
fn platform_web_build_output_path(
  root : String,
  build_profile : BuildProfile,
) -> String {
  root +
  "/_build/js/" +
  build_profile.build_dir() +
  "/build/moonbitcloud/web/web.js"
}

///|
fn preview_from_columns(
  preview_public_id : String,
  url : String,
  port : Int,
  healthy : Int,
) -> @sdk.PreviewTarget? {
  if url == "" {
    None
  } else {
    let public_url = if url.has_prefix("http://127.0.0.1:") {
      public_preview_url(preview_public_id)
    } else {
      url
    }
    Some(@sdk.PreviewTarget::{ url: public_url, port, healthy: healthy != 0 })
  }
}

///|
fn Store::new(db_path : String) -> Store {
  let db = @sqlite.Database::open(db_path).unwrap()
  ignore(db.busy_timeout(5000))
  ignore(db.exec("PRAGMA journal_mode=WAL;"))
  ignore(db.exec("PRAGMA synchronous=NORMAL;"))
  let store = Store::{ db, }
  store.init_schema()
  store
}

///|
fn Store::init_schema(self : Store) -> Unit {
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS users (
      #|  id TEXT PRIMARY KEY,
      #|  email TEXT NOT NULL UNIQUE,
      #|  password_hash TEXT,
      #|  display_name TEXT NOT NULL,
      #|  github_login TEXT,
      #|  created_at TEXT NOT NULL,
      #|  updated_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS sessions (
      #|  token_hash TEXT PRIMARY KEY,
      #|  user_id TEXT NOT NULL,
      #|  expires_at TEXT NOT NULL,
      #|  created_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS oauth_accounts (
      #|  id TEXT PRIMARY KEY,
      #|  user_id TEXT NOT NULL,
      #|  provider TEXT NOT NULL,
      #|  provider_user_id TEXT NOT NULL,
      #|  created_at TEXT NOT NULL,
      #|  updated_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.db.exec(
    (
      #|CREATE UNIQUE INDEX IF NOT EXISTS oauth_accounts_provider_user_id_idx
      #|ON oauth_accounts(provider, provider_user_id);
    ),
  )
  |> ignore
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS oauth_states (
      #|  state TEXT PRIMARY KEY,
      #|  provider TEXT NOT NULL,
      #|  pkce_verifier TEXT NOT NULL,
      #|  expires_at TEXT NOT NULL,
      #|  created_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS projects (
      #|  id TEXT PRIMARY KEY,
      #|  owner_user_id TEXT NOT NULL,
      #|  preview_public_id TEXT NOT NULL UNIQUE,
      #|  display_name TEXT NOT NULL,
      #|  workspace_path TEXT NOT NULL,
      #|  template_id TEXT NOT NULL DEFAULT 'bootstrap-app',
      #|  template_version TEXT NOT NULL DEFAULT '0.1.0',
      #|  codex_thread_id TEXT,
      #|  status TEXT NOT NULL,
      #|  preview_url TEXT,
      #|  preview_port INTEGER,
      #|  preview_healthy INTEGER NOT NULL DEFAULT 0,
      #|  last_preview_url TEXT,
      #|  last_preview_port INTEGER,
      #|  last_preview_healthy INTEGER NOT NULL DEFAULT 0,
      #|  last_error TEXT,
      #|  current_run_id TEXT,
      #|  created_at TEXT NOT NULL,
      #|  updated_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.ensure_project_column(
    "template_id",
    "TEXT NOT NULL DEFAULT '" + default_template_id() + "'",
  )
  self.ensure_project_column(
    "template_version",
    "TEXT NOT NULL DEFAULT '" + default_template_version() + "'",
  )
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS messages (
      #|  id TEXT PRIMARY KEY,
      #|  project_id TEXT NOT NULL,
      #|  run_id TEXT,
      #|  role TEXT NOT NULL,
      #|  content TEXT NOT NULL,
      #|  created_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS runs (
      #|  id TEXT PRIMARY KEY,
      #|  project_id TEXT NOT NULL,
      #|  state TEXT NOT NULL,
      #|  summary TEXT,
      #|  error_message TEXT,
      #|  preview_url TEXT,
      #|  preview_port INTEGER,
      #|  preview_healthy INTEGER NOT NULL DEFAULT 0,
      #|  started_at TEXT NOT NULL,
      #|  finished_at TEXT
      #|);
    ),
  )
  |> ignore
}

///|
fn Store::project_column_exists(self : Store, column_name : String) -> Bool {
  let stmt = self.db.prepare("PRAGMA table_info(projects);").unwrap()
  let mut exists = false
  while stmt.step() {
    if bytes_to_string(stmt.column_text(1)) == column_name {
      exists = true
    }
  }
  stmt.finalize()
  exists
}

///|
fn Store::ensure_project_column(
  self : Store,
  column_name : String,
  definition : String,
) -> Unit {
  if self.project_column_exists(column_name) {
    return
  }
  self.db.exec(
    "ALTER TABLE projects ADD COLUMN " + column_name + " " + definition + ";",
  )
  |> ignore
}

///|
fn Store::count_projects(self : Store) -> Int {
  let stmt = self.db.prepare("SELECT COUNT(*) FROM projects").unwrap()
  let mut count = 0
  if stmt.step() {
    count = stmt.column_int(0)
  }
  stmt.finalize()
  count
}

///|
fn Store::get_project_detail(
  self : Store,
  project_id : String,
) -> @sdk.ProjectDetail? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT
        #|  id,
        #|  preview_public_id,
        #|  display_name,
        #|  workspace_path,
        #|  template_id,
        #|  template_version,
        #|  COALESCE(codex_thread_id, ''),
        #|  status,
        #|  COALESCE(preview_url, ''),
        #|  COALESCE(preview_port, 0),
        #|  preview_healthy,
        #|  COALESCE(last_error, ''),
        #|  COALESCE(current_run_id, ''),
        #|  created_at,
        #|  updated_at
        #|FROM projects
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(project_id)) |> ignore
  let result = if stmt.step() {
    let preview = preview_from_columns(
      bytes_to_string(stmt.column_text(1)),
      bytes_to_string(stmt.column_text(8)),
      stmt.column_int(9),
      stmt.column_int(10),
    )
    Some(@sdk.ProjectDetail::{
      id: bytes_to_string(stmt.column_text(0)),
      preview_public_id: bytes_to_string(stmt.column_text(1)),
      display_name: bytes_to_string(stmt.column_text(2)),
      workspace_path: bytes_to_string(stmt.column_text(3)),
      template_id: bytes_to_string(stmt.column_text(4)),
      template_version: bytes_to_string(stmt.column_text(5)),
      codex_thread_id: empty_to_none(bytes_to_string(stmt.column_text(6))),
      status: run_state_from_db(bytes_to_string(stmt.column_text(7))),
      preview,
      current_run_id: empty_to_none(bytes_to_string(stmt.column_text(12))),
      last_error: empty_to_none(bytes_to_string(stmt.column_text(11))),
      created_at: bytes_to_string(stmt.column_text(13)),
      updated_at: bytes_to_string(stmt.column_text(14)),
    })
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::list_messages(
  self : Store,
  project_id : String,
) -> Array[@sdk.ChatMessage] {
  let stmt = self.db
    .prepare(
      (
        #|SELECT
        #|  id,
        #|  project_id,
        #|  COALESCE(run_id, ''),
        #|  role,
        #|  content,
        #|  created_at
        #|FROM messages
        #|WHERE project_id = ?
        #|ORDER BY created_at ASC;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(project_id)) |> ignore
  let items : Array[@sdk.ChatMessage] = []
  while stmt.step() {
    items.push(@sdk.ChatMessage::{
      id: bytes_to_string(stmt.column_text(0)),
      project_id: bytes_to_string(stmt.column_text(1)),
      run_id: empty_to_none(bytes_to_string(stmt.column_text(2))),
      role: chat_role_from_db(bytes_to_string(stmt.column_text(3))),
      content: bytes_to_string(stmt.column_text(4)),
      created_at: bytes_to_string(stmt.column_text(5)),
    })
  }
  stmt.finalize()
  items
}

///|
fn Store::get_run(
  self : Store,
  project_id : String,
  run_id : String,
) -> @sdk.RunStatusResponse? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT
        #|  r.id,
        #|  r.project_id,
        #|  r.state,
        #|  COALESCE(r.summary, ''),
        #|  COALESCE(r.error_message, ''),
        #|  COALESCE(r.preview_url, ''),
        #|  COALESCE(r.preview_port, 0),
        #|  r.preview_healthy,
        #|  r.started_at,
        #|  COALESCE(r.finished_at, ''),
        #|  p.preview_public_id
        #|FROM runs r
        #|JOIN projects p ON p.id = r.project_id
        #|WHERE r.id = ? AND r.project_id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([string_to_sql_text(run_id), string_to_sql_text(project_id)])
  |> ignore
  let result = if stmt.step() {
    let preview = preview_from_columns(
      bytes_to_string(stmt.column_text(10)),
      bytes_to_string(stmt.column_text(5)),
      stmt.column_int(6),
      stmt.column_int(7),
    )
    Some(@sdk.RunStatusResponse::{
      run_id: bytes_to_string(stmt.column_text(0)),
      project_id: bytes_to_string(stmt.column_text(1)),
      state: run_state_from_db(bytes_to_string(stmt.column_text(2))),
      summary: empty_to_none(bytes_to_string(stmt.column_text(3))),
      error_message: empty_to_none(bytes_to_string(stmt.column_text(4))),
      preview,
      started_at: bytes_to_string(stmt.column_text(8)),
      finished_at: empty_to_none(bytes_to_string(stmt.column_text(9))),
    })
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::create_project(
  self : Store,
  project_id : String,
  owner_user_id : String,
  preview_public_id : String,
  display_name : String?,
  workspace_path : String,
  template_id : String,
  template_version : String,
) -> @sdk.ProjectDetail {
  let now = now_string()
  let name = match display_name {
    Some(value) if value != "" => value
    _ => "Project \{self.count_projects() + 1}"
  }
  let stmt = self.db
    .prepare(
      (
        #|INSERT INTO projects (
        #|  id,
        #|  owner_user_id,
        #|  preview_public_id,
        #|  display_name,
        #|  workspace_path,
        #|  template_id,
        #|  template_version,
        #|  status,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(project_id),
    string_to_sql_text(owner_user_id),
    string_to_sql_text(preview_public_id),
    string_to_sql_text(name),
    string_to_sql_text(workspace_path),
    string_to_sql_text(template_id),
    string_to_sql_text(template_version),
    string_to_sql_text(run_state_to_db(Idle)),
    string_to_sql_text(now),
    string_to_sql_text(now),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
  self.get_project_detail(project_id).unwrap()
}

///|
fn Store::delete_project(
  self : Store,
  project_id : String,
) -> Result[Unit, String] {
  if self.get_project_detail(project_id) is None {
    return Err("Project not found.")
  }

  let delete_messages_stmt = self.db
    .prepare(
      (
        #|DELETE FROM messages
        #|WHERE project_id = ?;
      ),
    )
    .unwrap()
  delete_messages_stmt.bind(1, string_to_sql_text(project_id)) |> ignore
  delete_messages_stmt.execute() |> ignore
  delete_messages_stmt.finalize()

  let delete_runs_stmt = self.db
    .prepare(
      (
        #|DELETE FROM runs
        #|WHERE project_id = ?;
      ),
    )
    .unwrap()
  delete_runs_stmt.bind(1, string_to_sql_text(project_id)) |> ignore
  delete_runs_stmt.execute() |> ignore
  delete_runs_stmt.finalize()

  let delete_project_stmt = self.db
    .prepare(
      (
        #|DELETE FROM projects
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  delete_project_stmt.bind(1, string_to_sql_text(project_id)) |> ignore
  delete_project_stmt.execute() |> ignore
  delete_project_stmt.finalize()
  Ok(())
}

///|
fn Store::start_run(
  self : Store,
  project_id : String,
  content : String,
) -> Result[@sdk.RunStatusResponse, String] {
  let project = match self.get_project_detail(project_id) {
    Some(project) => project
    None => return Err("Project not found.")
  }
  if project.status is Running {
    return Err(
      "This project is already being updated. Wait for the current run to finish.",
    )
  }
  let run_id = next_id("run")
  let message_id = next_id("message")
  let now = now_string()
  let message_stmt = self.db
    .prepare(
      (
        #|INSERT INTO messages (
        #|  id,
        #|  project_id,
        #|  run_id,
        #|  role,
        #|  content,
        #|  created_at
        #|) VALUES (?, ?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  message_stmt.bind_all([
    string_to_sql_text(message_id),
    string_to_sql_text(project_id),
    string_to_sql_text(run_id),
    string_to_sql_text(chat_role_to_db(User)),
    string_to_sql_text(content),
    string_to_sql_text(now),
  ])
  |> ignore
  message_stmt.execute() |> ignore
  message_stmt.finalize()

  let run_stmt = self.db
    .prepare(
      (
        #|INSERT INTO runs (
        #|  id,
        #|  project_id,
        #|  state,
        #|  started_at
        #|) VALUES (?, ?, ?, ?);
      ),
    )
    .unwrap()
  run_stmt.bind_all([
    string_to_sql_text(run_id),
    string_to_sql_text(project_id),
    string_to_sql_text(run_state_to_db(Running)),
    string_to_sql_text(now),
  ])
  |> ignore
  run_stmt.execute() |> ignore
  run_stmt.finalize()

  let project_stmt = self.db
    .prepare(
      (
        #|UPDATE projects
        #|SET
        #|  status = ?,
        #|  current_run_id = ?,
        #|  last_error = NULL,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  project_stmt.bind_all([
    string_to_sql_text(run_state_to_db(Running)),
    string_to_sql_text(run_id),
    string_to_sql_text(now),
    string_to_sql_text(project_id),
  ])
  |> ignore
  project_stmt.execute() |> ignore
  project_stmt.finalize()

  Ok(@sdk.RunStatusResponse::{
    run_id,
    project_id,
    state: @sdk.Running,
    summary: None,
    error_message: None,
    preview: project.preview,
    started_at: now,
    finished_at: None,
  })
}

///|
fn Store::set_project_thread_id(
  self : Store,
  project_id : String,
  thread_id : String,
) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|UPDATE projects
        #|SET codex_thread_id = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([string_to_sql_text(thread_id), string_to_sql_text(project_id)])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::get_run_prompt(
  self : Store,
  project_id : String,
  run_id : String,
) -> String? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT content
        #|FROM messages
        #|WHERE project_id = ?
        #|  AND run_id = ?
        #|  AND role = ?
        #|ORDER BY created_at DESC
        #|LIMIT 1;
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(project_id),
    string_to_sql_text(run_id),
    string_to_sql_text(chat_role_to_db(User)),
  ])
  |> ignore
  let result = if stmt.step() {
    Some(bytes_to_string(stmt.column_text(0)))
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::get_initial_project_prompt(
  self : Store,
  project_id : String,
) -> String? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT content
        #|FROM messages
        #|WHERE project_id = ?
        #|  AND role = ?
        #|ORDER BY created_at ASC
        #|LIMIT 1;
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(project_id),
    string_to_sql_text(chat_role_to_db(User)),
  ])
  |> ignore
  let result = if stmt.step() {
    Some(bytes_to_string(stmt.column_text(0)))
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::finish_run_success(
  self : Store,
  project_id : String,
  run_id : String,
  summary : String,
  thread_id : String?,
  preview : @sdk.PreviewTarget,
) -> Unit {
  let now = now_string()
  match thread_id {
    Some(value) => self.set_project_thread_id(project_id, value)
    None => ignore(())
  }
  let assistant_message = if summary == "" {
    "The app is updated and the preview is ready."
  } else {
    summary
  }
  let message_stmt = self.db
    .prepare(
      (
        #|INSERT INTO messages (
        #|  id,
        #|  project_id,
        #|  run_id,
        #|  role,
        #|  content,
        #|  created_at
        #|) VALUES (?, ?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  message_stmt.bind_all([
    string_to_sql_text(next_id("message")),
    string_to_sql_text(project_id),
    string_to_sql_text(run_id),
    string_to_sql_text(chat_role_to_db(Assistant)),
    string_to_sql_text(assistant_message),
    string_to_sql_text(now),
  ])
  |> ignore
  message_stmt.execute() |> ignore
  message_stmt.finalize()

  let run_stmt = self.db
    .prepare(
      (
        #|UPDATE runs
        #|SET
        #|  state = ?,
        #|  summary = ?,
        #|  error_message = NULL,
        #|  preview_url = ?,
        #|  preview_port = ?,
        #|  preview_healthy = ?,
        #|  finished_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  run_stmt.bind_all([
    string_to_sql_text(run_state_to_db(Succeeded)),
    string_to_sql_text(assistant_message),
    string_to_sql_text(preview.url),
    @sqlite.SqlValue::Int(preview.port),
    @sqlite.SqlValue::Int(bool_to_int(preview.healthy)),
    string_to_sql_text(now),
    string_to_sql_text(run_id),
  ])
  |> ignore
  run_stmt.execute() |> ignore
  run_stmt.finalize()

  let project_stmt = self.db
    .prepare(
      (
        #|UPDATE projects
        #|SET
        #|  status = ?,
        #|  preview_url = ?,
        #|  preview_port = ?,
        #|  preview_healthy = ?,
        #|  last_preview_url = ?,
        #|  last_preview_port = ?,
        #|  last_preview_healthy = ?,
        #|  current_run_id = NULL,
        #|  last_error = NULL,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  project_stmt.bind_all([
    string_to_sql_text(run_state_to_db(Succeeded)),
    string_to_sql_text(preview.url),
    @sqlite.SqlValue::Int(preview.port),
    @sqlite.SqlValue::Int(bool_to_int(preview.healthy)),
    string_to_sql_text(preview.url),
    @sqlite.SqlValue::Int(preview.port),
    @sqlite.SqlValue::Int(bool_to_int(preview.healthy)),
    string_to_sql_text(now),
    string_to_sql_text(project_id),
  ])
  |> ignore
  project_stmt.execute() |> ignore
  project_stmt.finalize()
}

///|
fn Store::finish_run_failure(
  self : Store,
  project_id : String,
  run_id : String,
  assistant_message : String,
  error_message : String,
  thread_id : String?,
) -> Unit {
  let now = now_string()
  match thread_id {
    Some(value) => self.set_project_thread_id(project_id, value)
    None => ignore(())
  }
  let message_text = if assistant_message == "" {
    "I couldn't complete that change. The last working preview is still available."
  } else {
    assistant_message
  }
  let message_stmt = self.db
    .prepare(
      (
        #|INSERT INTO messages (
        #|  id,
        #|  project_id,
        #|  run_id,
        #|  role,
        #|  content,
        #|  created_at
        #|) VALUES (?, ?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  message_stmt.bind_all([
    string_to_sql_text(next_id("message")),
    string_to_sql_text(project_id),
    string_to_sql_text(run_id),
    string_to_sql_text(chat_role_to_db(Assistant)),
    string_to_sql_text(message_text),
    string_to_sql_text(now),
  ])
  |> ignore
  message_stmt.execute() |> ignore
  message_stmt.finalize()

  let run_stmt = self.db
    .prepare(
      (
        #|UPDATE runs
        #|SET
        #|  state = ?,
        #|  summary = ?,
        #|  error_message = ?,
        #|  finished_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  run_stmt.bind_all([
    string_to_sql_text(run_state_to_db(Failed)),
    string_to_sql_text(message_text),
    string_to_sql_text(error_message),
    string_to_sql_text(now),
    string_to_sql_text(run_id),
  ])
  |> ignore
  run_stmt.execute() |> ignore
  run_stmt.finalize()

  let project_stmt = self.db
    .prepare(
      (
        #|UPDATE projects
        #|SET
        #|  status = ?,
        #|  current_run_id = NULL,
        #|  last_error = ?,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  project_stmt.bind_all([
    string_to_sql_text(run_state_to_db(Failed)),
    string_to_sql_text(error_message),
    string_to_sql_text(now),
    string_to_sql_text(project_id),
  ])
  |> ignore
  project_stmt.execute() |> ignore
  project_stmt.finalize()
}

///|
fn PreviewManager::new(
  root : String,
  build_profile : BuildProfile,
) -> PreviewManager {
  { root, runtimes: {}, build_profile }
}

///|
fn PreviewManager::allocate_port(
  self : PreviewManager,
  project_id : String,
  preferred? : Int,
) -> Int {
  if preferred.unwrap_or(0) > 0 {
    return preferred.unwrap_or(0)
  }
  let mut hash = 0
  for byte in @utf8.encode(project_id) {
    hash = (hash * 33 + byte.to_int()) % 1000
  }
  let mut port = 4200 + hash
  while self.is_port_in_use(port, project_id) {
    port = port + 1
  }
  port
}

///|
fn PreviewManager::is_port_in_use(
  self : PreviewManager,
  port : Int,
  project_id : String,
) -> Bool {
  for id, runtime in self.runtimes {
    if id != project_id && runtime.port == port {
      return true
    }
  }
  false
}

///|
fn PreviewManager::stop_port(self : PreviewManager, port : Int) -> Unit {
  let _ = self
  ignore(
    shell_status("lsof -ti tcp:\{port} | xargs kill >/dev/null 2>&1 || true"),
  )
}

///|
fn PreviewManager::remove_project_runtime(
  self : PreviewManager,
  project_id : String,
  preview : @sdk.PreviewTarget?,
) -> Unit {
  match self.runtimes.get(project_id) {
    Some(runtime) => self.stop_port(runtime.port)
    None => ignore(())
  }
  match preview {
    Some(target) => self.stop_port(target.port)
    None => ignore(())
  }
  ignore(self.runtimes.remove(project_id))
}

///|
fn PreviewManager::is_healthy(
  self : PreviewManager,
  port : Int,
  health_path : String,
) -> Bool {
  let _ = self
  shell_status(
    "curl --silent --fail http://127.0.0.1:\{port}\{health_path} >/dev/null 2>&1",
  ) ==
  0
}

///|
fn PreviewManager::wait_until_healthy(
  self : PreviewManager,
  port : Int,
  health_path : String,
  attempts : Int,
) -> Bool {
  for _ in 0..<attempts {
    if self.is_healthy(port, health_path) {
      return true
    }
    ignore(shell_status("sleep 1"))
  }
  false
}

///|
fn PreviewManager::copy_preview_assets(
  self : PreviewManager,
  project : @sdk.ProjectDetail,
  manifest : TemplateManifest,
) -> Result[String, String] {
  let workspace_path = project.workspace_path
  let preview_dir = preview_dist_dir(workspace_path)
  ensure_dir(preview_dir)

  let public_dir = workspace_relative_path(
    workspace_path,
    manifest.preview.public_dir,
  )
  let index_source = public_dir + "/index.html"
  let style_source = public_dir + "/styles.css"
  let index_target = preview_dir + "/index.html"
  let style_target = preview_dir + "/styles.css"
  let bundle_target = preview_dir + "/app.js"

  if @fs.path_exists(index_source) {
    safe_write_string(
      index_target,
      safe_read_string_or(index_source, generated_preview_index_html()),
    )
  } else {
    safe_write_string(index_target, generated_preview_index_html())
  }

  if @fs.path_exists(style_source) {
    safe_write_string(
      style_target,
      safe_read_string_or(style_source, generated_preview_styles()),
    )
  } else {
    safe_write_string(style_target, generated_preview_styles())
  }

  let bundle_source = template_build_output_path(
    workspace_path,
    self.build_profile,
    manifest.preview.frontend_module,
  )
  if !@fs.path_exists(bundle_source) {
    return Err("The generated frontend bundle was not found after build.")
  }
  safe_write_bytes(bundle_target, safe_read_bytes_or(bundle_source, b""))
  if safe_read_bytes_or(bundle_target, b"").length() == 0 {
    return Err("The generated frontend bundle could not be copied.")
  }
  Ok(preview_dir)
}

///|
fn PreviewManager::rebuild_and_restart(
  self : PreviewManager,
  project : @sdk.ProjectDetail,
) -> Result[@sdk.PreviewTarget, String] {
  let manifest = match load_template_manifest(self.root, project.template_id) {
    Ok(manifest) => manifest
    Err(message) => return Err(message)
  }
  let workspace_path = project.workspace_path
  let build_code = shell_status(
    "cd '\{workspace_path}' && moon build \{self.build_profile.cli_flag()}>/dev/null 2>&1",
  )
  if build_code != 0 {
    return Err(
      "The updated app did not compile yet, so the preview could not be refreshed.",
    )
  }
  let preview_dir = match self.copy_preview_assets(project, manifest) {
    Ok(dir) => dir
    Err(message) => return Err(message)
  }
  let backend_executable = template_native_executable_path(
    workspace_path,
    self.build_profile,
    manifest.preview.backend_module,
  )
  if !@fs.path_exists(backend_executable) {
    return Err("The generated backend executable was not found after build.")
  }
  let preferred_port = project.preview.map(fn(target) { target.port })
  let port = self.allocate_port(
    project.id,
    preferred=preferred_port.unwrap_or(0),
  )
  self.stop_port(port)
  let pid = shell_status(
    "cd '\{workspace_path}' && nohup '\{backend_executable}' \{port} '\{preview_dir}' >/tmp/moonbitcloud-preview-\{project.id}.log 2>&1 &",
  )
  if !self.wait_until_healthy(port, manifest.preview.health_path, 12) {
    return Err(
      "The preview process started, but it did not become healthy in time.",
    )
  }
  self.runtimes[project.id] = { port, pid }
  Ok(@sdk.PreviewTarget::{
    url: public_preview_url(project.preview_public_id),
    port,
    healthy: true,
  })
}

///|
fn AgentGateway::new(root : String) -> AgentGateway {
  AgentGateway::{ root, }
}

///|
fn AppContext::new(root : String) -> AppContext {
  let build_profile = build_profile_from_env()
  let data_dir = root + "/data/control-plane"
  ensure_dir(root + "/data")
  ensure_dir(data_dir)
  let db_path = data_dir + "/state-v2.sqlite"
  {
    root,
    build_profile,
    store: Store::new(db_path),
    previews: PreviewManager::new(root, build_profile),
    agent_gateway: AgentGateway::new(root),
  }
}

///|
fn AppContext::delete_project(
  self : AppContext,
  project_id : String,
) -> Result[Unit, String] {
  let project = match self.store.get_project_detail(project_id) {
    Some(project) => project
    None => return Err("Project not found.")
  }
  if project.status is Running {
    return Err(
      "This project is currently updating. Wait for the current run to finish before deleting it.",
    )
  }
  self.previews.remove_project_runtime(project_id, project.preview)
  safe_remove_tree(project_root(self.root, project_id))
  self.store.delete_project(project_id)
}
