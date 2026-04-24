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
struct RunningRun {
  project_id : String
  run_id : String
  thread_id : String?
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
#borrow(pid)
extern "C" fn process_alive_ffi(pid : Int) -> Int = "moonbitcloud_process_alive"

///|
fn shell_status(command : String) -> Int {
  shell_status_ffi(@utf8.encode(command))
}

///|
fn shell_quote(value : String) -> String {
  "'" + value.split("'").to_array().join("'\\''") + "'"
}

///|
fn process_alive(pid : Int) -> Bool {
  process_alive_ffi(pid) == 1
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
fn nullable_int_value(value : Int?) -> @sqlite.SqlValue {
  match value {
    Some(number) => @sqlite.SqlValue::Int(number)
    None => @sqlite.SqlValue::Null
  }
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
fn int_to_none_if_negative(value : Int) -> Int? {
  if value < 0 {
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
fn parent_dir(path : String) -> String {
  let parts = path.split("/").to_array()
  if parts.length() <= 1 {
    ""
  } else {
    let directory_parts : Array[String] = []
    let last_index = parts.length() - 1
    for i in 0..<last_index {
      directory_parts.push(parts[i].to_string())
    }
    directory_parts.join("/")
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
fn control_plane_executable_path(
  root : String,
  build_profile : BuildProfile,
) -> String {
  root +
  "/_build/native/" +
  build_profile.build_dir() +
  "/build/moonbitcloud/control-plane/control-plane.exe"
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
fn run_failure_debug_from_columns(
  stage : String,
  command : String,
  exit_code : Int,
  codex_log_path : String,
  validation_log_path : String,
  final_summary_path : String,
) -> @sdk.RunFailureDebug? {
  if stage == "" &&
    command == "" &&
    exit_code < 0 &&
    codex_log_path == "" &&
    validation_log_path == "" &&
    final_summary_path == "" {
    None
  } else {
    Some(@sdk.RunFailureDebug::{
      stage,
      command: empty_to_none(command),
      exit_code: int_to_none_if_negative(exit_code),
      codex_log_path: empty_to_none(codex_log_path),
      validation_log_path: empty_to_none(validation_log_path),
      final_summary_path: empty_to_none(final_summary_path),
    })
  }
}

///|
fn interrupted_worker_summary() -> String {
  "The previous worker was interrupted before it could finish. Send another message to retry this project."
}

///|
fn interrupted_worker_error() -> String {
  "The run was still marked Running when the control plane started. It was marked failed so the project can accept a new run."
}

///|
fn Store::column_exists(
  self : Store,
  table_name : String,
  column_name : String,
) -> Bool {
  let stmt = self.db.prepare("PRAGMA table_info(\{table_name});").unwrap()
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
fn Store::ensure_column(
  self : Store,
  table_name : String,
  column_name : String,
  column_sql : String,
) -> Unit {
  if !self.column_exists(table_name, column_name) {
    ignore(
      self.db.exec(
        "ALTER TABLE \{table_name} ADD COLUMN \{column_name} \{column_sql};",
      ),
    )
  }
}

///|
fn Store::backfill_initial_project_prompts(self : Store) -> Unit {
  let role = chat_role_to_db(User)
  let stmt = self.db
    .prepare(
      (
        #|UPDATE projects
        #|SET initial_project_prompt = (
        #|  SELECT content
        #|  FROM messages
        #|  WHERE messages.project_id = projects.id
        #|    AND messages.role = ?
        #|  ORDER BY messages.created_at ASC
        #|  LIMIT 1
        #|)
        #|WHERE (initial_project_prompt IS NULL OR initial_project_prompt = '')
        #|  AND EXISTS (
        #|    SELECT 1
        #|    FROM messages
        #|    WHERE messages.project_id = projects.id
        #|      AND messages.role = ?
        #|  );
      ),
    )
    .unwrap()
  stmt.bind_all([string_to_sql_text(role), string_to_sql_text(role)]) |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
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
      #|  email_verified INTEGER NOT NULL DEFAULT 1,
      #|  email_verified_at TEXT,
      #|  password_hash TEXT,
      #|  display_name TEXT NOT NULL,
      #|  github_login TEXT,
      #|  created_at TEXT NOT NULL,
      #|  updated_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.ensure_column("users", "email_verified", "INTEGER NOT NULL DEFAULT 1")
  self.ensure_column("users", "email_verified_at", "TEXT")
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
      #|  initial_project_prompt TEXT,
      #|  template_id TEXT NOT NULL DEFAULT 'web-app-todolist',
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
    "UPDATE projects SET template_id = '" +
    default_template_id() +
    "' WHERE template_id = 'bootstrap-app';",
  )
  |> ignore
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
  self.ensure_column("projects", "initial_project_prompt", "TEXT")
  self.backfill_initial_project_prompts()
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS runs (
      #|  id TEXT PRIMARY KEY,
      #|  project_id TEXT NOT NULL,
      #|  state TEXT NOT NULL,
      #|  summary TEXT,
      #|  error_message TEXT,
      #|  failure_stage TEXT,
      #|  failure_command TEXT,
      #|  failure_exit_code INTEGER,
      #|  codex_log_path TEXT,
      #|  validation_log_path TEXT,
      #|  final_summary_path TEXT,
      #|  preview_url TEXT,
      #|  preview_port INTEGER,
      #|  preview_healthy INTEGER NOT NULL DEFAULT 0,
      #|  started_at TEXT NOT NULL,
      #|  finished_at TEXT
      #|);
    ),
  )
  |> ignore
  self.ensure_column("runs", "failure_stage", "TEXT")
  self.ensure_column("runs", "failure_command", "TEXT")
  self.ensure_column("runs", "failure_exit_code", "INTEGER")
  self.ensure_column("runs", "codex_log_path", "TEXT")
  self.ensure_column("runs", "validation_log_path", "TEXT")
  self.ensure_column("runs", "final_summary_path", "TEXT")
  self.ensure_column("runs", "worker_pid", "INTEGER")
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS account_action_tokens (
      #|  id TEXT PRIMARY KEY,
      #|  user_id TEXT NOT NULL,
      #|  purpose TEXT NOT NULL,
      #|  token_hash TEXT NOT NULL UNIQUE,
      #|  expires_at TEXT NOT NULL,
      #|  consumed_at TEXT,
      #|  created_at TEXT NOT NULL
      #|);
    ),
  )
  |> ignore
  self.db.exec(
    (
      #|CREATE INDEX IF NOT EXISTS account_action_tokens_user_purpose_idx
      #|ON account_action_tokens(user_id, purpose);
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
  self.recover_interrupted_runs()
  let stmt = self.db
    .prepare(
      (
        #|SELECT
        #|  r.id,
        #|  r.project_id,
        #|  r.state,
        #|  COALESCE(r.summary, ''),
        #|  COALESCE(r.error_message, ''),
        #|  COALESCE(r.failure_stage, ''),
        #|  COALESCE(r.failure_command, ''),
        #|  COALESCE(r.failure_exit_code, -1),
        #|  COALESCE(r.codex_log_path, ''),
        #|  COALESCE(r.validation_log_path, ''),
        #|  COALESCE(r.final_summary_path, ''),
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
      bytes_to_string(stmt.column_text(16)),
      bytes_to_string(stmt.column_text(11)),
      stmt.column_int(12),
      stmt.column_int(13),
    )
    let failure_debug = run_failure_debug_from_columns(
      bytes_to_string(stmt.column_text(5)),
      bytes_to_string(stmt.column_text(6)),
      stmt.column_int(7),
      bytes_to_string(stmt.column_text(8)),
      bytes_to_string(stmt.column_text(9)),
      bytes_to_string(stmt.column_text(10)),
    )
    Some(@sdk.RunStatusResponse::{
      run_id: bytes_to_string(stmt.column_text(0)),
      project_id: bytes_to_string(stmt.column_text(1)),
      state: run_state_from_db(bytes_to_string(stmt.column_text(2))),
      summary: empty_to_none(bytes_to_string(stmt.column_text(3))),
      error_message: empty_to_none(bytes_to_string(stmt.column_text(4))),
      failure_debug,
      preview,
      started_at: bytes_to_string(stmt.column_text(14)),
      finished_at: empty_to_none(bytes_to_string(stmt.column_text(15))),
    })
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::list_running_runs(self : Store) -> Array[RunningRun] {
  let stmt = self.db
    .prepare(
      (
        #|SELECT
        #|  r.project_id,
        #|  r.id,
        #|  COALESCE(p.codex_thread_id, '')
        #|FROM runs r
        #|JOIN projects p ON p.id = r.project_id
        #|WHERE r.state = ?
        #|ORDER BY r.started_at ASC;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(run_state_to_db(Running))) |> ignore
  let runs : Array[RunningRun] = []
  while stmt.step() {
    runs.push({
      project_id: bytes_to_string(stmt.column_text(0)),
      run_id: bytes_to_string(stmt.column_text(1)),
      thread_id: empty_to_none(bytes_to_string(stmt.column_text(2))),
    })
  }
  stmt.finalize()
  runs
}

///|
fn Store::fail_orphaned_running_projects_on_startup(self : Store) -> Unit {
  let now = now_string()
  let stmt = self.db
    .prepare(
      (
        #|UPDATE projects
        #|SET
        #|  status = ?,
        #|  current_run_id = NULL,
        #|  last_error = ?,
        #|  updated_at = ?
        #|WHERE status = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(run_state_to_db(Failed)),
    string_to_sql_text(interrupted_worker_summary()),
    string_to_sql_text(now),
    string_to_sql_text(run_state_to_db(Running)),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::fail_stale_running_runs_on_startup(self : Store) -> Int {
  let runs = self.list_running_runs()
  for run in runs {
    self.finish_run_failure_with_debug(
      run.project_id,
      run.run_id,
      interrupted_worker_summary(),
      interrupted_worker_error(),
      run.thread_id,
      Some(@sdk.RunFailureDebug::{
        stage: "Worker recovery",
        command: None,
        exit_code: None,
        codex_log_path: None,
        validation_log_path: None,
        final_summary_path: None,
      }),
    )
  }
  self.fail_orphaned_running_projects_on_startup()
  runs.length()
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
  self.recover_interrupted_runs()
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
        #|  initial_project_prompt = CASE
        #|    WHEN initial_project_prompt IS NULL OR initial_project_prompt = '' THEN ?
        #|    ELSE initial_project_prompt
        #|  END,
        #|  last_error = NULL,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  project_stmt.bind_all([
    string_to_sql_text(run_state_to_db(Running)),
    string_to_sql_text(run_id),
    string_to_sql_text(content),
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
    failure_debug: None,
    preview: project.preview,
    started_at: now,
    finished_at: None,
  })
}

///|
fn Store::set_run_worker_pid(
  self : Store,
  project_id : String,
  run_id : String,
  worker_pid : Int,
) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|UPDATE runs
        #|SET worker_pid = ?
        #|WHERE id = ? AND project_id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([
    @sqlite.SqlValue::Int(worker_pid),
    string_to_sql_text(run_id),
    string_to_sql_text(project_id),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
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
        #|SELECT COALESCE(initial_project_prompt, '')
        #|FROM projects
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(project_id)) |> ignore
  let result = if stmt.step() {
    empty_to_none(bytes_to_string(stmt.column_text(0)))
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
        #|  failure_stage = NULL,
        #|  failure_command = NULL,
        #|  failure_exit_code = NULL,
        #|  codex_log_path = NULL,
        #|  validation_log_path = NULL,
        #|  final_summary_path = NULL,
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
  self.finish_run_failure_with_debug(
    project_id,
    run_id,
    assistant_message,
    error_message,
    thread_id,
    None,
  )
}

///|
fn Store::finish_run_failure_with_debug(
  self : Store,
  project_id : String,
  run_id : String,
  assistant_message : String,
  error_message : String,
  thread_id : String?,
  failure_debug : @sdk.RunFailureDebug?,
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
  let failure_stage = failure_debug.map(fn(debug) { debug.stage })
  let failure_command = failure_debug.bind(fn(debug) { debug.command })
  let failure_exit_code = failure_debug.bind(fn(debug) { debug.exit_code })
  let codex_log_path = failure_debug.bind(fn(debug) { debug.codex_log_path })
  let validation_log_path = failure_debug.bind(fn(debug) {
    debug.validation_log_path
  })
  let final_summary_path = failure_debug.bind(fn(debug) {
    debug.final_summary_path
  })
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
        #|  failure_stage = ?,
        #|  failure_command = ?,
        #|  failure_exit_code = ?,
        #|  codex_log_path = ?,
        #|  validation_log_path = ?,
        #|  final_summary_path = ?,
        #|  finished_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  run_stmt.bind_all([
    string_to_sql_text(run_state_to_db(Failed)),
    string_to_sql_text(message_text),
    string_to_sql_text(error_message),
    nullable_text_value(failure_stage),
    nullable_text_value(failure_command),
    nullable_int_value(failure_exit_code),
    nullable_text_value(codex_log_path),
    nullable_text_value(validation_log_path),
    nullable_text_value(final_summary_path),
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
    string_to_sql_text(message_text),
    string_to_sql_text(now),
    string_to_sql_text(project_id),
  ])
  |> ignore
  project_stmt.execute() |> ignore
  project_stmt.finalize()
}

///|
fn Store::recover_interrupted_runs(self : Store) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|SELECT id, project_id, COALESCE(worker_pid, 0)
        #|FROM runs
        #|WHERE state = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(run_state_to_db(Running))) |> ignore
  let interrupted : Array[(String, String)] = []
  while stmt.step() {
    let run_id = bytes_to_string(stmt.column_text(0))
    let project_id = bytes_to_string(stmt.column_text(1))
    let worker_pid = stmt.column_int(2)
    if worker_pid <= 0 || !process_alive(worker_pid) {
      interrupted.push((project_id, run_id))
    }
  }
  stmt.finalize()
  for item in interrupted {
    let (project_id, run_id) = item
    self.finish_run_failure(
      project_id,
      run_id,
      "The background worker stopped before finishing this update.",
      "The background worker stopped unexpectedly. Please send the request again.",
      None,
    )
  }
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
  safe_remove_tree(preview_dir)
  ensure_dir(preview_dir)

  let public_dir = workspace_relative_path(
    workspace_path,
    manifest.preview.public_dir,
  )
  let copy_status = shell_status(
    "cp -R " + shell_quote(public_dir + "/.") + " " + shell_quote(preview_dir),
  )
  if copy_status != 0 {
    return Err("The preview public assets could not be copied.")
  }
  let index_target = preview_dir + "/index.html"
  let style_target = preview_dir + "/styles.css"
  if !@fs.path_exists(index_target) {
    safe_write_string(index_target, preview_fallback_index_html(self.root))
  }
  if !@fs.path_exists(style_target) {
    safe_write_string(style_target, preview_fallback_styles(self.root))
  }

  let build_artifacts = template_preview_build_artifacts(manifest)
  for artifact in build_artifacts {
    let source_module = template_preview_artifact_source_module(
      manifest, artifact,
    )
    let encoding = template_preview_artifact_encoding(artifact)
    let source = template_build_output_path(
      workspace_path,
      self.build_profile,
      source_module,
      artifact.backend,
    )
    if !@fs.path_exists(source) {
      return Err(
        "The generated preview artifact '\{artifact.target_path}' was not found after build.",
      )
    }
    let target = preview_dir + "/" + artifact.target_path
    let target_directory = parent_dir(target)
    if target_directory != "" {
      ensure_dir(target_directory)
    }
    let copy_code = match encoding {
      "base64" =>
        shell_status(
          "base64 < " + shell_quote(source) + " > " + shell_quote(target),
        )
      _ => shell_status("cp " + shell_quote(source) + " " + shell_quote(target))
    }
    if copy_code != 0 {
      return Err(
        "The generated preview artifact '\{artifact.target_path}' could not be staged.",
      )
    }
    if encoding == "base64" {
      if safe_read_string_or(target, "") == "" {
        return Err(
          "The generated preview artifact '\{artifact.target_path}' could not be copied.",
        )
      }
    } else if safe_read_bytes_or(target, b"").length() == 0 {
      return Err(
        "The generated preview artifact '\{artifact.target_path}' could not be copied.",
      )
    }
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
  let preferred_port = project.preview.map(fn(target) { target.port })
  let port = self.allocate_port(
    project.id,
    preferred=preferred_port.unwrap_or(0),
  )
  self.stop_port(port)
  let pid = match template_preview_kind(manifest) {
    "static" =>
      shell_status(
        "cd " +
        shell_quote(self.root) +
        " && nohup moon run --manifest-path " +
        shell_quote(self.root + "/moon.work") +
        " --target native " +
        self.build_profile.cli_flag() +
        "services/control-plane -- run-static-preview \{port} " +
        shell_quote(preview_dir) +
        " >/tmp/moonbitcloud-preview-\{project.id}.log 2>&1 &",
      )
    _ => {
      let backend_module = match manifest.preview.backend_module {
        Some(module_name) => module_name
        None =>
          return Err(
            "The template preview manifest is missing a backend module.",
          )
      }
      let backend_executable = template_native_executable_path(
        workspace_path,
        self.build_profile,
        backend_module,
      )
      if !@fs.path_exists(backend_executable) {
        return Err(
          "The generated backend executable was not found after build.",
        )
      }
      shell_status(
        "cd '\{workspace_path}' && nohup '\{backend_executable}' \{port} '\{preview_dir}' >/tmp/moonbitcloud-preview-\{project.id}.log 2>&1 &",
      )
    }
  }
  if !self.wait_until_healthy(port, template_preview_health_path(manifest), 12) {
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
  AppContext::new_with_recovery(root, true)
}

///|
fn AppContext::new_for_worker(root : String) -> AppContext {
  AppContext::new_with_recovery(root, false)
}

///|
fn AppContext::new_with_recovery(
  root : String,
  recover_interrupted : Bool,
) -> AppContext {
  let build_profile = build_profile_from_env()
  let data_dir = root + "/data/control-plane"
  ensure_dir(root + "/data")
  ensure_dir(data_dir)
  let db_path = data_dir + "/state-v2.sqlite"
  let ctx = {
    root,
    build_profile,
    store: Store::new(db_path),
    previews: PreviewManager::new(root, build_profile),
    agent_gateway: AgentGateway::new(root),
  }
  if recover_interrupted {
    ctx.store.recover_interrupted_runs()
  }
  ctx
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
