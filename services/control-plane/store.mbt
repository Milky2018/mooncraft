///|
let id_counter : Ref[Int] = @ref.new(0)

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
  runtimes : Map[String, PreviewRuntime]
}

///|
struct AgentGateway {
  root : String
}

///|
struct AppContext {
  root : String
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
fn safe_write_bytes(path : String, content : Bytes) -> Unit {
  @fs.write_bytes_to_file(path, content) catch {
    _ => ()
  }
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
fn platform_web_bundle_candidates(root : String) -> Array[String] {
  [
    root + "/_build/js/debug/build/moonbitcloud/web/web.js",
    root + "/_build/js/debug/build/web/web.js",
    root + "/_build/js/debug/build/apps/web/web.js",
    root + "/_build/js/debug/build/apps/web/apps/web.js",
  ]
}

///|
fn generated_web_bundle_candidates(workspace_path : String) -> Array[String] {
  [
    workspace_path + "/_build/js/debug/build/frontend/frontend.js",
    workspace_path + "/_build/js/debug/build/generated-app/frontend.js",
  ]
}

///|
fn first_existing_path(candidates : Array[String]) -> String? {
  for candidate in candidates {
    if @fs.path_exists(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
fn preview_from_columns(
  url : String,
  port : Int,
  healthy : Int,
) -> @sdk.PreviewTarget? {
  if url == "" {
    None
  } else {
    Some(@sdk.PreviewTarget::{ url, port, healthy: healthy != 0 })
  }
}

///|
fn Store::new(db_path : String) -> Store {
  let db = @sqlite.Database::open(db_path).unwrap()
  let store = Store::{ db, }
  store.init_schema()
  store
}

///|
fn Store::init_schema(self : Store) -> Unit {
  self.db.exec(
    (
      #|CREATE TABLE IF NOT EXISTS projects (
      #|  id TEXT PRIMARY KEY,
      #|  display_name TEXT NOT NULL,
      #|  workspace_path TEXT NOT NULL,
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
fn Store::list_projects(self : Store) -> Array[@sdk.ProjectSummary] {
  let stmt = self.db
    .prepare(
      (
        #|SELECT
        #|  id,
        #|  display_name,
        #|  status,
        #|  COALESCE(preview_url, ''),
        #|  COALESCE(preview_port, 0),
        #|  preview_healthy,
        #|  COALESCE(current_run_id, ''),
        #|  updated_at
        #|FROM projects
        #|ORDER BY updated_at DESC;
      ),
    )
    .unwrap()
  let items : Array[@sdk.ProjectSummary] = []
  while stmt.step() {
    let preview = preview_from_columns(
      bytes_to_string(stmt.column_text(3)),
      stmt.column_int(4),
      stmt.column_int(5),
    )
    items.push(@sdk.ProjectSummary::{
      id: bytes_to_string(stmt.column_text(0)),
      display_name: bytes_to_string(stmt.column_text(1)),
      status: run_state_from_db(bytes_to_string(stmt.column_text(2))),
      preview,
      current_run_id: empty_to_none(bytes_to_string(stmt.column_text(6))),
      updated_at: bytes_to_string(stmt.column_text(7)),
    })
  }
  stmt.finalize()
  items
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
        #|  display_name,
        #|  workspace_path,
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
      bytes_to_string(stmt.column_text(5)),
      stmt.column_int(6),
      stmt.column_int(7),
    )
    Some(@sdk.ProjectDetail::{
      id: bytes_to_string(stmt.column_text(0)),
      display_name: bytes_to_string(stmt.column_text(1)),
      workspace_path: bytes_to_string(stmt.column_text(2)),
      codex_thread_id: empty_to_none(bytes_to_string(stmt.column_text(3))),
      status: run_state_from_db(bytes_to_string(stmt.column_text(4))),
      preview,
      current_run_id: empty_to_none(bytes_to_string(stmt.column_text(9))),
      last_error: empty_to_none(bytes_to_string(stmt.column_text(8))),
      created_at: bytes_to_string(stmt.column_text(10)),
      updated_at: bytes_to_string(stmt.column_text(11)),
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
        #|  id,
        #|  project_id,
        #|  state,
        #|  COALESCE(summary, ''),
        #|  COALESCE(error_message, ''),
        #|  COALESCE(preview_url, ''),
        #|  COALESCE(preview_port, 0),
        #|  preview_healthy,
        #|  started_at,
        #|  COALESCE(finished_at, '')
        #|FROM runs
        #|WHERE id = ? AND project_id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([string_to_sql_text(run_id), string_to_sql_text(project_id)])
  |> ignore
  let result = if stmt.step() {
    let preview = preview_from_columns(
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
  display_name : String?,
  workspace_path : String,
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
        #|  display_name,
        #|  workspace_path,
        #|  status,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(project_id),
    string_to_sql_text(name),
    string_to_sql_text(workspace_path),
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
fn PreviewManager::new(root : String) -> PreviewManager {
  let _ = root
  { runtimes: {} }
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
fn PreviewManager::is_healthy(self : PreviewManager, port : Int) -> Bool {
  let _ = self
  shell_status(
    "curl --silent --fail http://127.0.0.1:\{port}/api/health >/dev/null 2>&1",
  ) ==
  0
}

///|
fn PreviewManager::wait_until_healthy(
  self : PreviewManager,
  port : Int,
  attempts : Int,
) -> Bool {
  for _ in 0..<attempts {
    if self.is_healthy(port) {
      return true
    }
    ignore(shell_status("sleep 1"))
  }
  false
}

///|
fn PreviewManager::copy_preview_assets(
  self : PreviewManager,
  workspace_path : String,
) -> Result[String, String] {
  let _ = self
  let preview_dir = preview_dist_dir(workspace_path)
  ensure_dir(preview_dir)

  let index_source = workspace_path + "/frontend/public/index.html"
  let style_source = workspace_path + "/frontend/public/styles.css"
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

  let bundle_source = match
    first_existing_path(generated_web_bundle_candidates(workspace_path)) {
    Some(path) => path
    None =>
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
  let workspace_path = project.workspace_path
  let build_code = shell_status(
    "cd '\{workspace_path}' && moon build frontend --target js >/dev/null 2>&1",
  )
  if build_code != 0 {
    return Err(
      "The updated app did not compile yet, so the preview could not be refreshed.",
    )
  }
  let preview_dir = match self.copy_preview_assets(workspace_path) {
    Ok(dir) => dir
    Err(message) => return Err(message)
  }
  let preferred_port = project.preview.map(fn(target) { target.port })
  let port = self.allocate_port(
    project.id,
    preferred=preferred_port.unwrap_or(0),
  )
  self.stop_port(port)
  let pid = shell_status(
    "cd '\{workspace_path}' && nohup moon run backend --target native -- \{port} '\{preview_dir}' >/tmp/moonbitcloud-preview-\{project.id}.log 2>&1 &",
  )
  if !self.wait_until_healthy(port, 12) {
    return Err(
      "The preview process started, but it did not become healthy in time.",
    )
  }
  self.runtimes[project.id] = { port, pid }
  Ok(@sdk.PreviewTarget::{
    url: "http://127.0.0.1:\{port}/",
    port,
    healthy: true,
  })
}

///|
fn AgentGateway::new(root : String) -> AgentGateway {
  AgentGateway::{ root, }
}

///|
fn agent_title(prompt : String) -> String {
  if prompt.contains("todo") || prompt.contains("task") {
    "Todo Workspace"
  } else if prompt.contains("dashboard") {
    "Insight Dashboard"
  } else if prompt.contains("shop") || prompt.contains("store") {
    "Storefront Studio"
  } else {
    "MoonBit Cloud App"
  }
}

///|
fn agent_subtitle(prompt : String) -> String {
  if prompt == "" {
    "Describe what you want, then let the agent reshape this project."
  } else {
    prompt.replace_all(old="\n", new=" ")
  }
}

///|
fn mbt_string_literal(value : String) -> String {
  "\"" +
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n") +
  "\""
}

///|
fn generated_custom_shared_model(title : String, subtitle : String) -> String {
  "///|\n" +
  "pub(all) struct AppInfo {\n" +
  "  title : String\n" +
  "  subtitle : String\n" +
  "} derive(Debug, ToJson, FromJson)\n\n" +
  "///|\n" +
  "pub(all) struct HealthStatus {\n" +
  "  ok : Bool\n" +
  "  title : String\n" +
  "  subtitle : String\n" +
  "} derive(Debug, ToJson, FromJson)\n\n" +
  "///|\n" +
  "pub fn default_info() -> AppInfo {\n" +
  "  {\n" +
  "    title: " +
  mbt_string_literal(title) +
  ",\n" +
  "    subtitle: " +
  mbt_string_literal(subtitle) +
  ",\n" +
  "  }\n" +
  "}\n"
}

///|
fn AgentGateway::run_turn(
  self : AgentGateway,
  project : @sdk.ProjectDetail,
  user_prompt : String,
) -> Result[(String, String?), String] {
  let _ = self.root
  let title = agent_title(user_prompt)
  let subtitle = agent_subtitle(user_prompt)
  safe_write_string(
    project.workspace_path + "/shared/model.mbt",
    generated_custom_shared_model(title, subtitle),
  )
  Ok(
    (
      "I refreshed the app around your latest request and rebuilt the preview.",
      Some("local-thread-" + project.id),
    ),
  )
}

///|
fn AppContext::new(root : String) -> AppContext {
  let data_dir = root + "/data/control-plane"
  ensure_dir(root + "/data")
  ensure_dir(data_dir)
  let db_path = data_dir + "/state.sqlite"
  {
    root,
    store: Store::new(db_path),
    previews: PreviewManager::new(root),
    agent_gateway: AgentGateway::new(root),
  }
}

///|
fn AppContext::run_project_turn(
  self : AppContext,
  project_id : String,
  run_id : String,
  prompt : String,
) -> Unit {
  let project = match self.store.get_project_detail(project_id) {
    Some(project) => project
    None => return
  }
  let agent_result = self.agent_gateway.run_turn(project, prompt)
  match agent_result {
    Ok((summary, thread_id)) => {
      let updated_project = match self.store.get_project_detail(project_id) {
        Some(project) => project
        None => return
      }
      let preview_result = self.previews.rebuild_and_restart(updated_project)
      match preview_result {
        Ok(preview) =>
          self.store.finish_run_success(
            project_id, run_id, summary, thread_id, preview,
          )
        Err(message) =>
          self.store.finish_run_failure(
            project_id,
            run_id,
            summary + "\n\nPreview status: " + message,
            message,
            thread_id,
          )
      }
    }
    Err(message) =>
      self.store.finish_run_failure(
        project_id,
        run_id,
        "I couldn't finish that update. The last working preview is still available.",
        message,
        None,
      )
  }
}
