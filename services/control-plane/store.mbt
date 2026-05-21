///|
let id_counter : Ref[Int] = @ref.new(0)

///|
enum BuildProfile {
  Debug
  Release
}

///|
struct Store {
  engine : StoreEngine
  backend : StoreBackend
}

///|
priv enum StoreBackend {
  SQLite
  Postgres
}

///|
priv enum StoreEngine {
  SQLiteEngine(StoreSQLiteEngine)
  PostgresEngine(@pg.Config)
}

///|
priv struct StoreSQLiteEngine {
  conn : @morm_sqlite.Connection
}

///|
struct RunningRun {
  project_id : String
  run_id : String
  thread_id : String?
}

///|
struct RunningRunWorker {
  worker_pid : Int
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
extern "C" fn shell_status_ffi(command : Bytes) -> Int = "mooncraft_shell_status"

///|
#borrow(pid)
extern "C" fn process_alive_ffi(pid : Int) -> Int = "mooncraft_process_alive"

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
fn terminate_worker_process(pid : Int) -> Unit {
  if pid <= 0 {
    return
  }
  ignore(
    shell_status(
      "pkill -TERM -P \{pid} >/dev/null 2>&1 || true; kill -TERM \{pid} >/dev/null 2>&1 || true; sleep 1; pkill -KILL -P \{pid} >/dev/null 2>&1 || true; kill -KILL \{pid} >/dev/null 2>&1 || true",
    ),
  )
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
fn nullable_int_param(value : Int?) -> @db.Param {
  match value {
    Some(number) => Int(number)
    None => Null
  }
}

///|
fn nullable_text_param(value : String?) -> @db.Param {
  match value {
    Some(text) => String(text)
    None => Null
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
fn param_to_string(value : @db.Param) -> String {
  match value {
    Null => ""
    Bool(v) => if v { "1" } else { "0" }
    Byte(v) => v.to_int().to_string()
    Int(v) => v.to_string()
    Int16(v) => v.to_string()
    UInt16(v) => v.to_string()
    UInt(v) => v.to_string()
    UInt64(v) => v.to_string()
    Int64(v) => v.to_string()
    BigInt(v) => v.to_string()
    Float(v) => v.to_string()
    Double(v) => v.to_string()
    Decimal(v) => v
    Date(v, _) => v.to_string()
    Time(v, _) => v.to_string()
    DateTime(v, _) => v.to_string()
    Timestamp(v, _) => v.to_string()
    Uuid(v) => v
    Json(v) => v.stringify()
    String(v) => v
    Bytes(v) => bytes_to_string(v)
  }
}

///|
fn param_to_int(value : @db.Param) -> Int {
  match value {
    Bool(v) => if v { 1 } else { 0 }
    Byte(v) => v.to_int()
    Int(v) => v
    Int16(v) => v.to_int()
    UInt16(v) => v.to_int()
    UInt(v) => v.reinterpret_as_int()
    UInt64(v) => v.to_int()
    Int64(v) => v.to_int()
    Float(v) => v.to_int()
    Double(v) => v.to_int()
    String(v) => @string.parse_int(v) catch { _ => 0 }
    _ => 0
  }
}

///|
fn param_to_bool(value : @db.Param) -> Bool {
  match value {
    Bool(v) => v
    Int(v) => v != 0
    Int64(v) => v != 0L
    String(v) => v == "1" || v.to_lower() == "true"
    _ => false
  }
}

///|
fn param_to_bytes(value : @db.Param) -> Bytes? {
  match value {
    Bytes(v) => Some(v)
    String(v) => Some(@utf8.encode(v))
    _ => None
  }
}

///|
fn row_get(row : Map[String, @db.Param], key : String) -> @db.Param {
  row.get(key).unwrap_or(Null)
}

///|
fn row_text(row : Map[String, @db.Param], key : String) -> String {
  param_to_string(row_get(row, key))
}

///|
fn row_int(row : Map[String, @db.Param], key : String) -> Int {
  param_to_int(row_get(row, key))
}

///|
fn row_bool(row : Map[String, @db.Param], key : String) -> Bool {
  param_to_bool(row_get(row, key))
}

///|
fn build_profile_from_env() -> BuildProfile {
  match @env.get_env_var("MOONCRAFT_BUILD_PROFILE") {
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
fn run_state_to_db(state : @sdk.RunState) -> String {
  match state {
    Idle => "idle"
    Running => "running"
    Succeeded => "succeeded"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
fn run_state_from_db(value : String) -> @sdk.RunState {
  match value {
    "running" => Running
    "succeeded" => Succeeded
    "failed" => Failed
    "cancelled" => Cancelled
    _ => Idle
  }
}

///|
fn run_phase_to_db(phase : @sdk.RunPhase) -> String {
  match phase {
    NoPhase => "none"
    AgentRunning => "agent_running"
    Checking => "checking"
  }
}

///|
fn run_phase_from_db(value : String) -> @sdk.RunPhase {
  match value {
    "agent_running" => AgentRunning
    "checking" => Checking
    _ => NoPhase
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
    let piece = part.to_owned()
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
      directory_parts.push(parts[i].to_owned())
    }
    directory_parts.join("/")
  }
}

///|
fn project_root(root : String, project_id : String) -> String {
  root + "/data/runtime/projects/" + project_id
}

///|
fn legacy_project_workspaces_root(root : String) -> String {
  root + "/data/projects"
}

///|
fn clean_legacy_project_workspaces(root : String) -> Unit {
  safe_remove_tree(legacy_project_workspaces_root(root))
}

///|
fn project_workspace(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/workspace"
}

///|
fn preview_script_missing_message() -> String {
  "MoonCraft could not find `mooncraft-preview.sh` at the project root."
}

///|
fn preview_error_needs_startup_repair(message : String) -> Bool {
  message == preview_script_missing_message() ||
  message == "The preview process could not be started." ||
  message ==
  "The preview process started, but it did not become healthy in time."
}

///|
fn project_codex_session_root(root : String, project_id : String) -> String {
  root + "/data/codex-sessions/" + project_id
}

///|
fn project_codex_home(root : String, project_id : String) -> String {
  project_codex_session_root(root, project_id) + "/.codex"
}

///|
fn project_agent_session_root(root : String, project_id : String) -> String {
  root + "/data/agent-sessions/" + project_id
}

///|
fn project_agent_home(
  root : String,
  project_id : String,
  agent_cli : String,
) -> String {
  let normalized = match normalize_agent_cli(agent_cli) {
    Ok(value) => value
    Err(_) => default_agent_cli()
  }
  project_agent_session_root(root, project_id) + "/" + normalized
}

///|
fn project_runtime_agent_home(
  root : String,
  project_id : String,
  agent_cli : String,
) -> String {
  let normalized = match normalize_agent_cli(agent_cli) {
    Ok(value) => value
    Err(_) => default_agent_cli()
  }
  if normalized == "codex" &&
    @fs.path_exists(project_codex_home(root, project_id)) {
    project_codex_session_root(root, project_id)
  } else {
    project_agent_home(root, project_id, normalized)
  }
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
fn platform_web_build_output_path(
  root : String,
  build_profile : BuildProfile,
) -> String {
  root +
  "/_build/js/" +
  build_profile.build_dir() +
  "/build/mooncraft/web/web.js"
}

///|
fn control_plane_executable_path(
  root : String,
  build_profile : BuildProfile,
) -> String {
  root +
  "/_build/native/" +
  build_profile.build_dir() +
  "/build/mooncraft/control-plane/control-plane.exe"
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
    Some({ url: public_url, port, healthy: healthy != 0 })
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
    Some({
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
fn parse_database_url(url : String) -> Result[@pg.Config, String] {
  let raw = match url.strip_prefix("postgres://") {
    Some(rest) => rest.to_owned()
    None =>
      match url.strip_prefix("postgresql://") {
        Some(rest) => rest.to_owned()
        None => return Err("PostgreSQL URL must start with postgres://")
      }
  }
  let main = raw.split("?").to_array()[0].to_owned()
  let mut auth_host = main
  let mut database = "postgres"
  if main.find("/") is Some(index) {
    auth_host = main[:index].to_owned()
    database = main[index + 1:].to_owned()
  }
  let mut user = "postgres"
  let mut password : String? = None
  let mut host_port = auth_host
  if auth_host.find("@") is Some(index) {
    let auth = auth_host[:index].to_owned()
    host_port = auth_host[index + 1:].to_owned()
    if auth.find(":") is Some(colon) {
      user = auth[:colon].to_owned()
      password = Some(auth[colon + 1:].to_owned())
    } else if auth != "" {
      user = auth
    }
  }
  let mut host = host_port
  let mut port = 5432
  if host_port.find(":") is Some(index) {
    host = host_port[:index].to_owned()
    port = @string.parse_int(host_port[index + 1:].to_owned()) catch {
      _ => 5432
    }
  }
  if host == "" {
    host = "127.0.0.1"
  }
  let config = match password {
    Some(password) =>
      @pg.Config::new(
        host,
        user~,
        database~,
        password~,
        port~,
        ssl_mode=@pg.SslMode::disable(),
        application_name="mooncraft",
      )
    None =>
      @pg.Config::new(
        host,
        user~,
        database~,
        port~,
        ssl_mode=@pg.SslMode::disable(),
        application_name="mooncraft",
      )
  }
  Ok(config)
}

///|
fn postgres_quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="''") + "'"
}

///|
fn postgres_param_sql(param : @db.Param) -> String {
  match param {
    Null => "NULL"
    Bool(value) => if value { "TRUE" } else { "FALSE" }
    Byte(value) => value.to_int().to_string()
    Int(value) => value.to_string()
    Int16(value) => value.to_int().to_string()
    UInt16(value) => value.to_int().to_string()
    UInt(value) => value.to_string()
    UInt64(value) => value.to_string()
    Int64(value) => value.to_string()
    BigInt(value) => value.to_string()
    Float(value) => value.to_string()
    Double(value) => value.to_string()
    Decimal(value) => value
    Date(value, _) => postgres_quote(value.to_string())
    Time(value, _) => postgres_quote(value.to_string())
    DateTime(value, _) => postgres_quote(value.to_string())
    Timestamp(value, _) => postgres_quote(value.to_string())
    Uuid(value) => postgres_quote(value)
    Json(value) => postgres_quote(value.stringify())
    String(value) => postgres_quote(value)
    Bytes(value) => "decode('\{@crypto.bytes_to_hex_string(value)}', 'hex')"
  }
}

///|
fn inline_postgres_sql(sql : String, params : FixedArray[@db.Param]) -> String {
  let mut out = sql
  let mut index = params.length() - 1
  while index >= 0 {
    out = out.replace(
      old="$" + (index + 1).to_string(),
      new=postgres_param_sql(params[index]),
    )
    index = index - 1
  }
  out
}

///|
fn hex_nibble(byte : Byte) -> Int? {
  if byte >= b'0' && byte <= b'9' {
    Some(byte.to_int() - b'0'.to_int())
  } else if byte >= b'a' && byte <= b'f' {
    Some(byte.to_int() - b'a'.to_int() + 10)
  } else if byte >= b'A' && byte <= b'F' {
    Some(byte.to_int() - b'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn postgres_text_param(value : String?) -> @db.Param {
  match value {
    None => Null
    Some(text) =>
      if text.has_prefix("\\x") {
        let encoded = @utf8.encode(text[2:].to_owned())
        let bytes : Array[Byte] = []
        let mut index = 0
        while index + 1 < encoded.length() {
          match (hex_nibble(encoded[index]), hex_nibble(encoded[index + 1])) {
            (Some(high), Some(low)) => bytes.push(((high << 4) | low).to_byte())
            _ => return String(text)
          }
          index = index + 2
        }
        Bytes(Bytes::from_array(bytes))
      } else {
        String(text)
      }
  }
}

///|
fn Store::sql(self : Store, sql : String) -> String {
  match self.backend {
    SQLite => sql
    Postgres => {
      let out = @buffer.new()
      let mut index = 1
      for c in sql {
        if c == '?' {
          out.write_string("$")
          out.write_string(index.to_string())
          index = index + 1
        } else {
          out.write_char(c)
        }
      }
      out.to_string()
    }
  }
}

///|
fn open(db_path : String) -> Result[StoreSQLiteEngine, String] {
  Ok({ conn: @morm_sqlite.Connection::open(db_path) }) catch {
    SqliteError(err) => Err(@debug.to_string(err))
  }
}

///|
fn sqlite_bind_param(
  stmt : @morm_sqlite.Statement,
  index : Int,
  param : @db.Param,
) -> Unit raise @morm_sqlite.SqliteError {
  match param {
    Double(value) => stmt.bind(index~, val=value)
    Float(value) => stmt.bind(index~, val=value.to_double())
    Byte(value) => stmt.bind(index~, val=value.to_int())
    Int(value) => stmt.bind(index~, val=value)
    Int16(value) => stmt.bind(index~, val=value.to_int())
    UInt16(value) => stmt.bind(index~, val=value.to_int())
    UInt(value) => stmt.bind(index~, val=value.to_string())
    UInt64(value) => stmt.bind(index~, val=value.to_string())
    Int64(value) => stmt.bind(index~, val=value)
    BigInt(value) => stmt.bind(index~, val=value.to_string())
    Decimal(value) => stmt.bind(index~, val=value)
    Date(value, format) =>
      stmt.bind(index~, val=@db.format_plain_date(value, format))
    Time(value, format) =>
      stmt.bind(index~, val=@db.format_plain_time(value, format))
    DateTime(value, format) =>
      stmt.bind(index~, val=@db.format_plain_date_time(value, format))
    Timestamp(value, format) =>
      stmt.bind(index~, val=@db.format_zoned_date_time(value, format))
    Uuid(value) => stmt.bind(index~, val=value)
    Json(value) => stmt.bind(index~, val=value.stringify())
    String(value) => stmt.bind(index~, val=value)
    Bytes(value) => stmt.bind(index~, val=value)
    Bool(value) => stmt.bind(index~, val=if value { 1 } else { 0 })
    Null => stmt.bind_null(index~)
  }
}

///|
fn sqlite_row_param(stmt : @morm_sqlite.Statement, index : Int) -> @db.Param {
  match stmt.column_type(index~) {
    @morm_sqlite.SQLITE_NULL => Null
    @morm_sqlite.SQLITE_INTEGER => {
      let value : Int = stmt.column(index~)
      Int(value)
    }
    @morm_sqlite.SQLITE_FLOAT => {
      let value : Double = stmt.column(index~)
      Double(value)
    }
    @morm_sqlite.SQLITE_TEXT => {
      let value : String = stmt.column(index~)
      String(value)
    }
    @morm_sqlite.SQLITE_BLOB => {
      let value : Bytes = stmt.column(index~)
      Bytes(value)
    }
    _ => String(stmt.column_blob_as_string(index~))
  }
}

///|
fn StoreSQLiteEngine::exec_raw(
  self : StoreSQLiteEngine,
  sql : String,
  params : FixedArray[@db.Param],
) -> @db.QueryResult {
  let rows : Array[Map[String, @db.Param]] = []
  let mut error = None
  try {
    let stmt = self.conn.prepare(sql + ";")
    params.eachi((index, param) => sqlite_bind_param(stmt, index, param))
    while stmt.step() {
      let row : Map[String, @db.Param] = {}
      let column_count = stmt.column_count()
      let mut index = 0
      while index < column_count {
        row[stmt.column_name(index~)] = sqlite_row_param(stmt, index)
        index = index + 1
      }
      rows.push(row)
    }
    stmt.finalize()
  } catch {
    SqliteError(err) => error = Some(@debug.to_string(err))
  }
  {
    ok: error is None,
    rows_affected: 0,
    rows: FixedArray::from_array(rows),
    error,
  }
}

///|
async fn Store::exec_raw(
  self : Store,
  sql : String,
  params : FixedArray[@db.Param],
) -> @db.QueryResult noraise {
  let rendered = self.sql(sql)
  match self.engine {
    SQLiteEngine(engine) => engine.exec_raw(rendered, params)
    PostgresEngine(config) => exec_postgres_raw(config, rendered, params)
  }
}

///|
async fn exec_postgres_raw(
  config : @pg.Config,
  sql : String,
  params : FixedArray[@db.Param],
) -> @db.QueryResult noraise {
  try
    @async.with_task_group(group => {
      let (client, connection) = @pg.connect(config)
      group.spawn_bg(() => connection.run())
      let stream = client.simple_query(inline_postgres_sql(sql, params))
      let messages = stream.collect()
      client.close()
      let rows : Array[Map[String, @db.Param]] = []
      let mut rows_affected = 0
      for message in messages {
        match message {
          Row(row) => {
            let item : Map[String, @db.Param] = {}
            let columns = row.columns()
            for index, column in columns {
              item[column] = postgres_text_param(row.get(index))
            }
            rows.push(item)
          }
          CommandComplete(tag) => {
            let parts = tag.split(" ").to_array()
            if parts.length() > 1 {
              rows_affected = @string.parse_int(
                parts[parts.length() - 1].to_owned(),
              ) catch {
                _ => rows_affected
              }
            }
          }
          _ => ignore(())
        }
      }
      @db.QueryResult::{
        ok: true,
        rows_affected,
        rows: FixedArray::from_array(rows),
        error: None,
      }
    })
  catch {
    error =>
      return {
        ok: false,
        rows_affected: 0,
        rows: [],
        error: Some(error.to_string()),
      }
  } noraise {
    result => result
  }
}

///|
async fn Store::exec_or_error(
  self : Store,
  sql : String,
  label : String,
  params? : FixedArray[@db.Param] = [],
) -> Result[Unit, String] noraise {
  let result = self.exec_raw(sql, params)
  if result.ok {
    Ok(())
  } else {
    Err(
      "Database operation failed while trying to \{label}: " +
      result.error.unwrap_or("unknown database error"),
    )
  }
}

///|
async fn Store::query_rows(
  self : Store,
  sql : String,
  params? : FixedArray[@db.Param] = [],
) -> FixedArray[Map[String, @db.Param]] noraise {
  let result = self.exec_raw(sql, params)
  if result.ok {
    result.rows
  } else {
    []
  }
}

///|
async fn Store::query_one(
  self : Store,
  sql : String,
  params? : FixedArray[@db.Param] = [],
) -> Map[String, @db.Param]? noraise {
  let rows = self.query_rows(sql, params~)
  if rows.length() > 0 {
    Some(rows[0])
  } else {
    None
  }
}

///|
async fn Store::column_exists(
  self : Store,
  table_name : String,
  column_name : String,
) -> Result[Bool, String] noraise {
  match self.backend {
    SQLite => {
      let rows = self.query_rows("PRAGMA table_info(\{table_name});")
      for row in rows {
        if row_text(row, "name") == column_name {
          return Ok(true)
        }
      }
      Ok(false)
    }
    Postgres => {
      let row = self.query_one(
        (
          #|SELECT 1 AS found
          #|FROM information_schema.columns
          #|WHERE table_name = ?
          #|  AND column_name = ?
          #|LIMIT 1;
        ),
        params=[String(table_name), String(column_name)],
      )
      Ok(row is Some(_))
    }
  }
}

///|
async fn Store::ensure_column(
  self : Store,
  table_name : String,
  column_name : String,
  column_sql : String,
) -> Result[Unit, String] noraise {
  match self.column_exists(table_name, column_name) {
    Ok(true) => Ok(())
    Ok(false) =>
      self.exec_or_error(
        "ALTER TABLE \{table_name} ADD COLUMN \{column_name} \{column_sql};",
        "add column \{table_name}.\{column_name}",
      )
    Err(message) => Err(message)
  }
}

///|
async fn Store::backfill_initial_project_prompts(
  self : Store,
) -> Result[Unit, String] noraise {
  let role = chat_role_to_db(User)
  self.exec_or_error(
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
    "backfill initial project prompts",
    params=[String(role), String(role)],
  )
}

///|
async fn try_new_async(db_path : String) -> Result[Store, String] noraise {
  let store = match @env.get_env_var("MOONCRAFT_DATABASE_URL") {
    Some(url) if url.trim() != "" => {
      let config = match parse_database_url(url.trim().to_owned()) {
        Ok(config) => config
        Err(message) => return Err(message)
      }
      { engine: PostgresEngine(config), backend: Postgres }
    }
    _ => {
      if (@fs.is_dir(db_path) catch { _ => false }) {
        return Err("SQLite database path points to a directory: \{db_path}")
      }
      let engine = match open(db_path) {
        Ok(engine) => engine
        Err(message) => return Err(message)
      }
      { engine: SQLiteEngine(engine), backend: SQLite }
    }
  }
  match store.init_schema() {
    Ok(_) => Ok(store)
    Err(message) => Err(message)
  }
}

///|
fn try_new(db_path : String) -> Result[Store, String] {
  let result : Ref[Result[Store, String]] = @ref.new(
    Err("The database was not initialized."),
  )
  @async.run_async_main(async fn() { result.val = try_new_async(db_path) })
  result.val
}

///|
async fn Store::is_available(self : Store) -> Bool noraise {
  let result = self.exec_raw("SELECT 1 AS ok;", [])
  result.ok
}

///|
fn Store::blob_type(self : Store) -> String {
  match self.backend {
    SQLite => "BLOB"
    Postgres => "BYTEA"
  }
}

///|
async fn Store::init_schema(self : Store) -> Result[Unit, String] noraise {
  if self.backend is SQLite {
    match self.exec_or_error("PRAGMA journal_mode=WAL;", "enable WAL mode") {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
    match
      self.exec_or_error(
        "PRAGMA synchronous=NORMAL;", "configure SQLite sync mode",
      ) {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
  }
  match
    self.exec_or_error(
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
      "create users table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.ensure_column("users", "email_verified", "INTEGER NOT NULL DEFAULT 1") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("users", "email_verified_at", "TEXT") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  ignore(
    self.exec_or_error(
      "UPDATE users SET ai_api_key = NULL;", "clear legacy user AI keys",
    ),
  )
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS sessions (
        #|  token_hash TEXT PRIMARY KEY,
        #|  user_id TEXT NOT NULL,
        #|  expires_at TEXT NOT NULL,
        #|  created_at TEXT NOT NULL
        #|);
      ),
      "create sessions table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
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
      "create oauth_accounts table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE UNIQUE INDEX IF NOT EXISTS oauth_accounts_provider_user_id_idx
        #|ON oauth_accounts(provider, provider_user_id);
      ),
      "create oauth account provider index",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS oauth_states (
        #|  state TEXT PRIMARY KEY,
        #|  provider TEXT NOT NULL,
        #|  pkce_verifier TEXT NOT NULL,
        #|  expires_at TEXT NOT NULL,
        #|  created_at TEXT NOT NULL
        #|);
      ),
      "create oauth_states table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS projects (
        #|  id TEXT PRIMARY KEY,
        #|  owner_user_id TEXT NOT NULL,
        #|  preview_public_id TEXT NOT NULL UNIQUE,
        #|  display_name TEXT NOT NULL,
        #|  agent_cli TEXT NOT NULL DEFAULT 'codex',
        #|  ai_model TEXT NOT NULL DEFAULT '',
        #|  workspace_path TEXT NOT NULL,
        #|  initial_project_prompt TEXT,
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
      "create projects table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS project_workspace_snapshots (
        #|  project_id TEXT PRIMARY KEY,
        #|  archive 
      ) +
      self.blob_type() +
      (
        #| NOT NULL,
        #|  updated_at TEXT NOT NULL
        #|);
      ),
      "create project_workspace_snapshots table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
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
      "create messages table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("projects", "initial_project_prompt", "TEXT") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("projects", "ai_model", "TEXT NOT NULL DEFAULT ''") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.ensure_column("projects", "agent_cli", "TEXT NOT NULL DEFAULT 'codex'") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.backfill_initial_project_prompts() {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS runs (
        #|  id TEXT PRIMARY KEY,
        #|  project_id TEXT NOT NULL,
        #|  state TEXT NOT NULL,
        #|  phase TEXT NOT NULL DEFAULT 'none',
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
      "create runs table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "failure_stage", "TEXT") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "failure_command", "TEXT") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "failure_exit_code", "INTEGER") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "codex_log_path", "TEXT") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "validation_log_path", "TEXT") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "final_summary_path", "TEXT") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "worker_pid", "INTEGER") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("runs", "phase", "TEXT NOT NULL DEFAULT 'none'") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS run_events (
        #|  id TEXT PRIMARY KEY,
        #|  project_id TEXT NOT NULL,
        #|  run_id TEXT NOT NULL,
        #|  seq INTEGER NOT NULL,
        #|  kind TEXT NOT NULL,
        #|  content TEXT NOT NULL,
        #|  created_at TEXT NOT NULL,
        #|  UNIQUE(project_id, run_id, seq)
        #|);
      ),
      "create run_events table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE INDEX IF NOT EXISTS run_events_project_run_seq_idx
        #|ON run_events(project_id, run_id, seq);
      ),
      "create run events index",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
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
      "create account_action_tokens table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE INDEX IF NOT EXISTS account_action_tokens_user_purpose_idx
        #|ON account_action_tokens(user_id, purpose);
      ),
      "create account action token index",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS ai_keys (
        #|  id TEXT PRIMARY KEY,
        #|  provider TEXT NOT NULL,
        #|  label TEXT NOT NULL,
        #|  key_secret TEXT NOT NULL,
        #|  key_hint TEXT NOT NULL,
        #|  status TEXT NOT NULL,
        #|  priority INTEGER NOT NULL DEFAULT 0,
        #|  last_used_at TEXT,
        #|  last_error TEXT,
        #|  created_at TEXT NOT NULL,
        #|  updated_at TEXT NOT NULL
        #|);
      ),
      "create ai_keys table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.ensure_column("ai_keys", "key_secret", "TEXT NOT NULL DEFAULT ''") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.ensure_column("ai_keys", "key_hint", "TEXT NOT NULL DEFAULT ''") {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE INDEX IF NOT EXISTS ai_keys_provider_status_idx
        #|ON ai_keys(provider, status, priority);
      ),
      "create AI key status index",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS ai_key_usages (
        #|  id TEXT PRIMARY KEY,
        #|  key_id TEXT NOT NULL,
        #|  run_id TEXT NOT NULL,
        #|  project_id TEXT NOT NULL,
        #|  user_id TEXT NOT NULL,
        #|  model TEXT NOT NULL,
        #|  state TEXT NOT NULL,
        #|  error_code TEXT,
        #|  started_at TEXT NOT NULL,
        #|  finished_at TEXT
        #|);
      ),
      "create ai_key_usages table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE INDEX IF NOT EXISTS ai_key_usages_run_idx
        #|ON ai_key_usages(run_id);
      ),
      "create AI key usage run index",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS ai_runtime_config (
        #|  id TEXT PRIMARY KEY,
        #|  default_model TEXT NOT NULL,
        #|  allowed_models TEXT NOT NULL,
        #|  updated_at TEXT NOT NULL
        #|);
      ),
      "create ai_runtime_config table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    self.exec_or_error(
      (
        #|INSERT INTO ai_runtime_config (
        #|  id,
        #|  default_model,
        #|  allowed_models,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?)
        #|ON CONFLICT(id) DO NOTHING;
      ),
      "seed default AI runtime config",
      params=[
        String("default"),
        String(default_openrouter_model()),
        String(default_openrouter_model()),
        String(now_string()),
      ],
    ) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}

///|
fn project_detail_from_row(row : Map[String, @db.Param]) -> @sdk.ProjectDetail {
  let preview = preview_from_columns(
    row_text(row, "preview_public_id"),
    row_text(row, "preview_url"),
    row_int(row, "preview_port"),
    row_int(row, "preview_healthy"),
  )
  {
    id: row_text(row, "id"),
    preview_public_id: row_text(row, "preview_public_id"),
    display_name: row_text(row, "display_name"),
    agent_cli: row_text(row, "agent_cli"),
    model: row_text(row, "ai_model"),
    workspace_path: row_text(row, "workspace_path"),
    codex_thread_id: empty_to_none(row_text(row, "codex_thread_id")),
    status: run_state_from_db(row_text(row, "status")),
    current_run_phase: run_phase_from_db(row_text(row, "current_run_phase")),
    preview,
    current_run_id: empty_to_none(row_text(row, "current_run_id")),
    last_error: empty_to_none(row_text(row, "last_error")),
    created_at: row_text(row, "created_at"),
    updated_at: row_text(row, "updated_at"),
  }
}

///|
fn chat_message_from_row(row : Map[String, @db.Param]) -> @sdk.ChatMessage {
  {
    id: row_text(row, "id"),
    project_id: row_text(row, "project_id"),
    run_id: empty_to_none(row_text(row, "run_id")),
    role: chat_role_from_db(row_text(row, "role")),
    content: row_text(row, "content"),
    created_at: row_text(row, "created_at"),
  }
}

///|
fn run_status_from_row(row : Map[String, @db.Param]) -> @sdk.RunStatusResponse {
  let preview = preview_from_columns(
    row_text(row, "preview_public_id"),
    row_text(row, "preview_url"),
    row_int(row, "preview_port"),
    row_int(row, "preview_healthy"),
  )
  let failure_debug = run_failure_debug_from_columns(
    row_text(row, "failure_stage"),
    row_text(row, "failure_command"),
    row_int(row, "failure_exit_code"),
    row_text(row, "codex_log_path"),
    row_text(row, "validation_log_path"),
    row_text(row, "final_summary_path"),
  )
  {
    run_id: row_text(row, "id"),
    project_id: row_text(row, "project_id"),
    state: run_state_from_db(row_text(row, "state")),
    phase: run_phase_from_db(row_text(row, "phase")),
    summary: empty_to_none(row_text(row, "summary")),
    error_message: empty_to_none(row_text(row, "error_message")),
    failure_debug,
    preview,
    started_at: row_text(row, "started_at"),
    finished_at: empty_to_none(row_text(row, "finished_at")),
  }
}

///|
async fn Store::save_workspace_snapshot(
  self : Store,
  project_id : String,
  archive : Bytes,
) -> Result[Unit, String] noraise {
  self.exec_or_error(
    (
      #|INSERT INTO project_workspace_snapshots (
      #|  project_id,
      #|  archive,
      #|  updated_at
      #|) VALUES (?, ?, ?)
      #|ON CONFLICT(project_id) DO UPDATE SET
      #|  archive = excluded.archive,
      #|  updated_at = excluded.updated_at;
    ),
    "save workspace snapshot",
    params=[String(project_id), Bytes(archive), String(now_string())],
  )
}

///|
async fn Store::get_workspace_snapshot(
  self : Store,
  project_id : String,
) -> Bytes? noraise {
  match
    self.query_one(
      (
        #|SELECT archive
        #|FROM project_workspace_snapshots
        #|WHERE project_id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => param_to_bytes(row_get(row, "archive"))
    None => None
  }
}

///|
async fn Store::get_project_detail(
  self : Store,
  project_id : String,
) -> @sdk.ProjectDetail? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  p.id,
        #|  p.preview_public_id,
        #|  p.display_name,
        #|  COALESCE(p.agent_cli, 'codex') AS agent_cli,
        #|  COALESCE(p.ai_model, '') AS ai_model,
        #|  p.workspace_path,
        #|  COALESCE(p.codex_thread_id, '') AS codex_thread_id,
        #|  p.status,
        #|  COALESCE(p.preview_url, '') AS preview_url,
        #|  COALESCE(p.preview_port, 0) AS preview_port,
        #|  p.preview_healthy,
        #|  COALESCE(p.last_error, '') AS last_error,
        #|  COALESCE(p.current_run_id, '') AS current_run_id,
        #|  COALESCE(r.phase, 'none') AS current_run_phase,
        #|  p.created_at,
        #|  p.updated_at
        #|FROM projects p
        #|LEFT JOIN runs r ON r.id = p.current_run_id AND r.project_id = p.id
        #|WHERE p.id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => Some(project_detail_from_row(row))
    None => None
  }
}

///|
async fn Store::list_messages(
  self : Store,
  project_id : String,
) -> Array[@sdk.ChatMessage] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  project_id,
      #|  COALESCE(run_id, '') AS run_id,
      #|  role,
      #|  content,
      #|  created_at
      #|FROM messages
      #|WHERE project_id = ?
      #|ORDER BY created_at ASC;
    ),
    params=[String(project_id)],
  )
  let items : Array[@sdk.ChatMessage] = []
  for row in rows {
    items.push(chat_message_from_row(row))
  }
  items
}

///|
async fn Store::get_run(
  self : Store,
  project_id : String,
  run_id : String,
) -> @sdk.RunStatusResponse? noraise {
  self.recover_interrupted_runs()
  match
    self.query_one(
      (
        #|SELECT
        #|  r.id,
        #|  r.project_id,
        #|  r.state,
        #|  COALESCE(r.phase, 'none') AS phase,
        #|  COALESCE(r.summary, '') AS summary,
        #|  COALESCE(r.error_message, '') AS error_message,
        #|  COALESCE(r.failure_stage, '') AS failure_stage,
        #|  COALESCE(r.failure_command, '') AS failure_command,
        #|  COALESCE(r.failure_exit_code, -1) AS failure_exit_code,
        #|  COALESCE(r.codex_log_path, '') AS codex_log_path,
        #|  COALESCE(r.validation_log_path, '') AS validation_log_path,
        #|  COALESCE(r.final_summary_path, '') AS final_summary_path,
        #|  COALESCE(r.preview_url, '') AS preview_url,
        #|  COALESCE(r.preview_port, 0) AS preview_port,
        #|  r.preview_healthy,
        #|  r.started_at,
        #|  COALESCE(r.finished_at, '') AS finished_at,
        #|  p.preview_public_id
        #|FROM runs r
        #|JOIN projects p ON p.id = r.project_id
        #|WHERE r.id = ? AND r.project_id = ?;
      ),
      params=[String(run_id), String(project_id)],
    ) {
    Some(row) => Some(run_status_from_row(row))
    None => None
  }
}

///|
async fn Store::get_run_by_id(
  self : Store,
  run_id : String,
) -> @sdk.RunStatusResponse? noraise {
  self.recover_interrupted_runs()
  match
    self.query_one(
      (
        #|SELECT
        #|  r.id,
        #|  r.project_id,
        #|  r.state,
        #|  COALESCE(r.phase, 'none') AS phase,
        #|  COALESCE(r.summary, '') AS summary,
        #|  COALESCE(r.error_message, '') AS error_message,
        #|  COALESCE(r.failure_stage, '') AS failure_stage,
        #|  COALESCE(r.failure_command, '') AS failure_command,
        #|  COALESCE(r.failure_exit_code, -1) AS failure_exit_code,
        #|  COALESCE(r.codex_log_path, '') AS codex_log_path,
        #|  COALESCE(r.validation_log_path, '') AS validation_log_path,
        #|  COALESCE(r.final_summary_path, '') AS final_summary_path,
        #|  COALESCE(r.preview_url, '') AS preview_url,
        #|  COALESCE(r.preview_port, 0) AS preview_port,
        #|  r.preview_healthy,
        #|  r.started_at,
        #|  COALESCE(r.finished_at, '') AS finished_at,
        #|  p.preview_public_id
        #|FROM runs r
        #|JOIN projects p ON p.id = r.project_id
        #|WHERE r.id = ?;
      ),
      params=[String(run_id)],
    ) {
    Some(row) => Some(run_status_from_row(row))
    None => None
  }
}

///|
async fn Store::list_recent_runs(
  self : Store,
  limit : Int,
) -> Array[@sdk.RunStatusResponse] noraise {
  self.recover_interrupted_runs()
  let rows = self.query_rows(
    (
      #|SELECT
      #|  r.id,
      #|  r.project_id,
      #|  r.state,
      #|  COALESCE(r.phase, 'none') AS phase,
      #|  COALESCE(r.summary, '') AS summary,
      #|  COALESCE(r.error_message, '') AS error_message,
      #|  COALESCE(r.failure_stage, '') AS failure_stage,
      #|  COALESCE(r.failure_command, '') AS failure_command,
      #|  COALESCE(r.failure_exit_code, -1) AS failure_exit_code,
      #|  COALESCE(r.codex_log_path, '') AS codex_log_path,
      #|  COALESCE(r.validation_log_path, '') AS validation_log_path,
      #|  COALESCE(r.final_summary_path, '') AS final_summary_path,
      #|  COALESCE(r.preview_url, '') AS preview_url,
      #|  COALESCE(r.preview_port, 0) AS preview_port,
      #|  r.preview_healthy,
      #|  r.started_at,
      #|  COALESCE(r.finished_at, '') AS finished_at,
      #|  p.preview_public_id
      #|FROM runs r
      #|JOIN projects p ON p.id = r.project_id
      #|ORDER BY r.started_at DESC
      #|LIMIT ?;
    ),
    params=[Int(limit)],
  )
  let items : Array[@sdk.RunStatusResponse] = []
  for row in rows {
    items.push(run_status_from_row(row))
  }
  items
}

///|
async fn Store::list_project_runs(
  self : Store,
  project_id : String,
  limit : Int,
) -> Array[@sdk.RunStatusResponse] noraise {
  self.recover_interrupted_runs()
  let rows = self.query_rows(
    (
      #|SELECT
      #|  r.id,
      #|  r.project_id,
      #|  r.state,
      #|  COALESCE(r.phase, 'none') AS phase,
      #|  COALESCE(r.summary, '') AS summary,
      #|  COALESCE(r.error_message, '') AS error_message,
      #|  COALESCE(r.failure_stage, '') AS failure_stage,
      #|  COALESCE(r.failure_command, '') AS failure_command,
      #|  COALESCE(r.failure_exit_code, -1) AS failure_exit_code,
      #|  COALESCE(r.codex_log_path, '') AS codex_log_path,
      #|  COALESCE(r.validation_log_path, '') AS validation_log_path,
      #|  COALESCE(r.final_summary_path, '') AS final_summary_path,
      #|  COALESCE(r.preview_url, '') AS preview_url,
      #|  COALESCE(r.preview_port, 0) AS preview_port,
      #|  r.preview_healthy,
      #|  r.started_at,
      #|  COALESCE(r.finished_at, '') AS finished_at,
      #|  p.preview_public_id
      #|FROM runs r
      #|JOIN projects p ON p.id = r.project_id
      #|WHERE r.project_id = ?
      #|ORDER BY r.started_at DESC
      #|LIMIT ?;
    ),
    params=[String(project_id), Int(limit)],
  )
  let items : Array[@sdk.RunStatusResponse] = []
  for row in rows {
    items.push(run_status_from_row(row))
  }
  items
}

///|
async fn Store::append_run_event(
  self : Store,
  project_id : String,
  run_id : String,
  kind : String,
  content : String,
) -> Unit noraise {
  if content == "" {
    return
  }
  let seq = match
    self.query_one(
      (
        #|SELECT COALESCE(MAX(seq), 0) + 1 AS next_seq
        #|FROM run_events
        #|WHERE project_id = ? AND run_id = ?;
      ),
      params=[String(project_id), String(run_id)],
    ) {
    Some(row) => row_int(row, "next_seq")
    None => 1
  }
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO run_events (
        #|  id,
        #|  project_id,
        #|  run_id,
        #|  seq,
        #|  kind,
        #|  content,
        #|  created_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?);
      ),
      "append run event",
      params=[
        String(next_id("event")),
        String(project_id),
        String(run_id),
        Int(seq),
        String(kind),
        String(content),
        String(now_string()),
      ],
    ),
  )
}

///|
async fn Store::list_run_events(
  self : Store,
  project_id : String,
  run_id : String,
  after_seq : Int,
) -> Array[@sdk.RunEvent] noraise {
  let rows = self.query_rows(
    (
      #|SELECT seq, kind, content, created_at
      #|FROM run_events
      #|WHERE project_id = ? AND run_id = ? AND seq > ?
      #|ORDER BY seq ASC
      #|LIMIT 200;
    ),
    params=[String(project_id), String(run_id), Int(after_seq)],
  )
  let items : Array[@sdk.RunEvent] = []
  for row in rows {
    items.push({
      seq: row_int(row, "seq"),
      kind: row_text(row, "kind"),
      content: row_text(row, "content"),
      created_at: row_text(row, "created_at"),
    })
  }
  items
}

///|
async fn Store::list_running_runs(self : Store) -> Array[RunningRun] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  r.project_id,
      #|  r.id AS run_id,
      #|  COALESCE(p.codex_thread_id, '') AS thread_id
      #|FROM runs r
      #|JOIN projects p ON p.id = r.project_id
      #|WHERE r.state = ?
      #|ORDER BY r.started_at ASC;
    ),
    params=[String(run_state_to_db(Running))],
  )
  let runs : Array[RunningRun] = []
  for row in rows {
    runs.push({
      project_id: row_text(row, "project_id"),
      run_id: row_text(row, "run_id"),
      thread_id: empty_to_none(row_text(row, "thread_id")),
    })
  }
  runs
}

///|
async fn Store::fail_orphaned_running_projects_on_startup(
  self : Store,
) -> Unit noraise {
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|UPDATE projects
        #|SET
        #|  status = ?,
        #|  current_run_id = NULL,
        #|  last_error = ?,
        #|  updated_at = ?
        #|WHERE status = ?;
      ),
      "fail orphaned running projects",
      params=[
        String(run_state_to_db(Failed)),
        String(interrupted_worker_summary()),
        String(now),
        String(run_state_to_db(Running)),
      ],
    ),
  )
}

///|
async fn Store::fail_stale_running_runs_on_startup(self : Store) -> Int noraise {
  let runs = self.list_running_runs()
  for run in runs {
    self.finish_run_failure_with_debug(
      run.project_id,
      run.run_id,
      interrupted_worker_summary(),
      interrupted_worker_error(),
      run.thread_id,
      Some({
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
async fn Store::create_project(
  self : Store,
  project_id : String,
  owner_user_id : String,
  preview_public_id : String,
  display_name : String,
  agent_cli : String,
  model : String,
  workspace_path : String,
) -> @sdk.ProjectDetail noraise {
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO projects (
        #|  id,
        #|  owner_user_id,
        #|  preview_public_id,
        #|  display_name,
        #|  agent_cli,
        #|  ai_model,
        #|  workspace_path,
        #|  status,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ),
      "create project",
      params=[
        String(project_id),
        String(owner_user_id),
        String(preview_public_id),
        String(display_name),
        String(agent_cli),
        String(model),
        String(workspace_path),
        String(run_state_to_db(Idle)),
        String(now),
        String(now),
      ],
    ),
  )
  self.get_project_detail(project_id).unwrap()
}

///|
async fn Store::update_project_settings(
  self : Store,
  project_id : String,
  display_name : String?,
  model : String?,
) -> @sdk.ProjectDetail? noraise {
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|UPDATE projects
        #|SET
        #|  display_name = COALESCE(?, display_name),
        #|  ai_model = COALESCE(?, ai_model),
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
      "update project settings",
      params=[
        nullable_text_param(display_name),
        nullable_text_param(model),
        String(now),
        String(project_id),
      ],
    ),
  )
  self.get_project_detail(project_id)
}

///|
async fn Store::delete_project(
  self : Store,
  project_id : String,
) -> Result[Unit, String] noraise {
  if self.get_project_detail(project_id) is None {
    return Err("Project not found.")
  }
  ignore(
    self.exec_or_error(
      "DELETE FROM messages WHERE project_id = ?;",
      "delete project messages",
      params=[String(project_id)],
    ),
  )
  ignore(
    self.exec_or_error(
      "DELETE FROM run_events WHERE project_id = ?;",
      "delete project run events",
      params=[String(project_id)],
    ),
  )
  ignore(
    self.exec_or_error(
      "DELETE FROM runs WHERE project_id = ?;",
      "delete project runs",
      params=[String(project_id)],
    ),
  )
  ignore(
    self.exec_or_error(
      "DELETE FROM project_workspace_snapshots WHERE project_id = ?;",
      "delete project workspace snapshot",
      params=[String(project_id)],
    ),
  )
  self.exec_or_error("DELETE FROM projects WHERE id = ?;", "delete project", params=[
    String(project_id),
  ])
}

///|
async fn Store::start_run(
  self : Store,
  project_id : String,
  content : String,
) -> Result[@sdk.RunStatusResponse, String] noraise {
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
  ignore(
    self.exec_or_error(
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
      "create user message",
      params=[
        String(message_id),
        String(project_id),
        String(run_id),
        String(chat_role_to_db(User)),
        String(content),
        String(now),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO runs (
        #|  id,
        #|  project_id,
        #|  state,
        #|  phase,
        #|  started_at
        #|) VALUES (?, ?, ?, ?, ?);
      ),
      "create run",
      params=[
        String(run_id),
        String(project_id),
        String(run_state_to_db(Running)),
        String(run_phase_to_db(AgentRunning)),
        String(now),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
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
      "mark project running",
      params=[
        String(run_state_to_db(Running)),
        String(run_id),
        String(content),
        String(now),
        String(project_id),
      ],
    ),
  )
  Ok({
    run_id,
    project_id,
    state: Running,
    phase: AgentRunning,
    summary: None,
    error_message: None,
    failure_debug: None,
    preview: project.preview,
    started_at: now,
    finished_at: None,
  })
}

///|
async fn Store::set_run_phase(
  self : Store,
  project_id : String,
  run_id : String,
  phase : @sdk.RunPhase,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      (
        #|UPDATE runs
        #|SET phase = ?
        #|WHERE id = ? AND project_id = ? AND state = ?;
      ),
      "set run phase",
      params=[
        String(run_phase_to_db(phase)),
        String(run_id),
        String(project_id),
        String(run_state_to_db(Running)),
      ],
    ),
  )
}

///|
async fn Store::set_run_worker_pid(
  self : Store,
  project_id : String,
  run_id : String,
  worker_pid : Int,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      "UPDATE runs SET worker_pid = ? WHERE id = ? AND project_id = ?;",
      "set run worker pid",
      params=[Int(worker_pid), String(run_id), String(project_id)],
    ),
  )
}

///|
async fn Store::get_running_run_worker(
  self : Store,
  project_id : String,
  run_id : String,
) -> RunningRunWorker? noraise {
  match
    self.query_one(
      (
        #|SELECT COALESCE(worker_pid, 0) AS worker_pid
        #|FROM runs
        #|WHERE id = ? AND project_id = ? AND state = ?;
      ),
      params=[
        String(run_id),
        String(project_id),
        String(run_state_to_db(Running)),
      ],
    ) {
    Some(row) => Some({ worker_pid: row_int(row, "worker_pid") })
    None => None
  }
}

///|
async fn Store::set_project_thread_id(
  self : Store,
  project_id : String,
  thread_id : String,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      "UPDATE projects SET codex_thread_id = ? WHERE id = ?;",
      "set project thread id",
      params=[String(thread_id), String(project_id)],
    ),
  )
}

///|
async fn Store::set_project_preview(
  self : Store,
  project_id : String,
  preview : @sdk.PreviewTarget,
) -> @sdk.ProjectDetail? noraise {
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|UPDATE projects
        #|SET
        #|  preview_url = ?,
        #|  preview_port = ?,
        #|  preview_healthy = ?,
        #|  last_preview_url = ?,
        #|  last_preview_port = ?,
        #|  last_preview_healthy = ?,
        #|  last_error = NULL,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
      "set project preview",
      params=[
        String(preview.url),
        Int(preview.port),
        Int(bool_to_int(preview.healthy)),
        String(preview.url),
        Int(preview.port),
        Int(bool_to_int(preview.healthy)),
        String(now),
        String(project_id),
      ],
    ),
  )
  self.get_project_detail(project_id)
}

///|
async fn Store::mark_project_preview_unreachable(
  self : Store,
  project_id : String,
  message : String,
) -> @sdk.ProjectDetail? noraise {
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|UPDATE projects
        #|SET
        #|  preview_healthy = ?,
        #|  last_error = ?,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
      "mark project preview unreachable",
      params=[Int(0), String(message), String(now), String(project_id)],
    ),
  )
  self.get_project_detail(project_id)
}

///|
async fn Store::get_run_prompt(
  self : Store,
  project_id : String,
  run_id : String,
) -> String? noraise {
  match
    self.query_one(
      (
        #|SELECT content
        #|FROM messages
        #|WHERE project_id = ?
        #|  AND run_id = ?
        #|  AND role = ?
        #|ORDER BY created_at DESC
        #|LIMIT 1;
      ),
      params=[String(project_id), String(run_id), String(chat_role_to_db(User))],
    ) {
    Some(row) => Some(row_text(row, "content"))
    None => None
  }
}

///|
async fn Store::get_initial_project_prompt(
  self : Store,
  project_id : String,
) -> String? noraise {
  match
    self.query_one(
      (
        #|SELECT COALESCE(initial_project_prompt, '') AS prompt
        #|FROM projects
        #|WHERE id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => empty_to_none(row_text(row, "prompt"))
    None => None
  }
}

///|
async fn Store::finish_run_success(
  self : Store,
  project_id : String,
  run_id : String,
  summary : String,
  thread_id : String?,
  preview : @sdk.PreviewTarget,
) -> Unit noraise {
  let now = now_string()
  match thread_id {
    Some(value) => self.set_project_thread_id(project_id, value)
    None => ignore(())
  }
  let assistant_message = if summary == "" {
    successful_preview_assistant_message()
  } else {
    summary
  }
  self.finish_ai_key_usage(run_id, "succeeded", None)
  ignore(
    self.exec_or_error(
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
      "create assistant success message",
      params=[
        String(next_id("message")),
        String(project_id),
        String(run_id),
        String(chat_role_to_db(Assistant)),
        String(assistant_message),
        String(now),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
      (
        #|UPDATE runs
        #|SET
        #|  state = ?,
        #|  phase = ?,
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
      "finish run successfully",
      params=[
        String(run_state_to_db(Succeeded)),
        String(run_phase_to_db(NoPhase)),
        String(assistant_message),
        String(preview.url),
        Int(preview.port),
        Int(bool_to_int(preview.healthy)),
        String(now),
        String(run_id),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
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
      "mark project succeeded",
      params=[
        String(run_state_to_db(Succeeded)),
        String(preview.url),
        Int(preview.port),
        Int(bool_to_int(preview.healthy)),
        String(preview.url),
        Int(preview.port),
        Int(bool_to_int(preview.healthy)),
        String(now),
        String(project_id),
      ],
    ),
  )
}

///|
async fn Store::finish_run_failure(
  self : Store,
  project_id : String,
  run_id : String,
  assistant_message : String,
  error_message : String,
  thread_id : String?,
) -> Unit noraise {
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
async fn Store::finish_run_failure_with_debug(
  self : Store,
  project_id : String,
  run_id : String,
  assistant_message : String,
  error_message : String,
  thread_id : String?,
  failure_debug : @sdk.RunFailureDebug?,
) -> Unit noraise {
  let now = now_string()
  match thread_id {
    Some(value) => self.set_project_thread_id(project_id, value)
    None => ignore(())
  }
  let message_text = if assistant_message == "" {
    "The change could not be completed. The last working preview is still available."
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
  self.finish_ai_key_usage(run_id, "failed", failure_stage)
  ignore(
    self.exec_or_error(
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
      "create assistant failure message",
      params=[
        String(next_id("message")),
        String(project_id),
        String(run_id),
        String(chat_role_to_db(Assistant)),
        String(message_text),
        String(now),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
      (
        #|UPDATE runs
        #|SET
        #|  state = ?,
        #|  phase = ?,
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
      "finish run with failure",
      params=[
        String(run_state_to_db(Failed)),
        String(run_phase_to_db(NoPhase)),
        String(message_text),
        String(error_message),
        nullable_text_param(failure_stage),
        nullable_text_param(failure_command),
        nullable_int_param(failure_exit_code),
        nullable_text_param(codex_log_path),
        nullable_text_param(validation_log_path),
        nullable_text_param(final_summary_path),
        String(now),
        String(run_id),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
      (
        #|UPDATE projects
        #|SET
        #|  status = ?,
        #|  current_run_id = NULL,
        #|  last_error = ?,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
      "mark project failed",
      params=[
        String(run_state_to_db(Failed)),
        String(message_text),
        String(now),
        String(project_id),
      ],
    ),
  )
}

///|
async fn Store::finish_run_cancelled(
  self : Store,
  project_id : String,
  run_id : String,
) -> Unit noraise {
  let now = now_string()
  let message_text = "Stopped."
  self.finish_ai_key_usage(run_id, "cancelled", Some("User stop"))
  ignore(
    self.exec_or_error(
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
      "create assistant cancellation message",
      params=[
        String(next_id("message")),
        String(project_id),
        String(run_id),
        String(chat_role_to_db(Assistant)),
        String(message_text),
        String(now),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
      (
        #|UPDATE runs
        #|SET
        #|  state = ?,
        #|  phase = ?,
        #|  summary = ?,
        #|  error_message = NULL,
        #|  failure_stage = NULL,
        #|  failure_command = NULL,
        #|  failure_exit_code = NULL,
        #|  codex_log_path = NULL,
        #|  validation_log_path = NULL,
        #|  final_summary_path = NULL,
        #|  finished_at = ?
        #|WHERE id = ? AND project_id = ? AND state = ?;
      ),
      "finish run as cancelled",
      params=[
        String(run_state_to_db(Cancelled)),
        String(run_phase_to_db(NoPhase)),
        String(message_text),
        String(now),
        String(run_id),
        String(project_id),
        String(run_state_to_db(Running)),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
      (
        #|UPDATE projects
        #|SET
        #|  status = ?,
        #|  current_run_id = NULL,
        #|  last_error = NULL,
        #|  updated_at = ?
        #|WHERE id = ? AND current_run_id = ?;
      ),
      "mark project cancelled",
      params=[
        String(run_state_to_db(Cancelled)),
        String(now),
        String(project_id),
        String(run_id),
      ],
    ),
  )
}

///|
async fn AppContext::cancel_project_run(
  self : AppContext,
  project_id : String,
  run_id : String,
  worker_pid : Int,
) -> @sdk.RunStatusResponse? noraise {
  self.store.append_run_event(
    project_id, run_id, "status", "Stopping the builder session.",
  )
  ignore(
    shell_status(
      "docker rm -f " +
      shell_quote(agent_runtime_container_name(project_id, run_id)) +
      " >/dev/null 2>&1 || true",
    ),
  )
  terminate_worker_process(worker_pid)
  self.store.finish_run_cancelled(project_id, run_id)
  self.store.get_run(project_id, run_id)
}

///|
async fn Store::recover_interrupted_runs(self : Store) -> Unit noraise {
  let rows = self.query_rows(
    (
      #|SELECT id, project_id, COALESCE(worker_pid, 0) AS worker_pid
      #|FROM runs
      #|WHERE state = ?;
    ),
    params=[String(run_state_to_db(Running))],
  )
  let interrupted : Array[(String, String)] = []
  for row in rows {
    let run_id = row_text(row, "id")
    let project_id = row_text(row, "project_id")
    let worker_pid = row_int(row, "worker_pid")
    if worker_pid <= 0 || !process_alive(worker_pid) {
      interrupted.push((project_id, run_id))
    }
  }
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
fn PreviewManager::new(root : String) -> PreviewManager {
  { root, runtimes: {} }
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
fn PreviewManager::is_preview_reachable(
  self : PreviewManager,
  port : Int,
) -> Bool {
  self.is_healthy(port, preview_health_path()) || self.is_healthy(port, "/")
}

///|
fn PreviewManager::wait_until_preview_reachable(
  self : PreviewManager,
  port : Int,
  attempts : Int,
) -> Bool {
  for _ in 0..<attempts {
    if self.is_preview_reachable(port) {
      return true
    }
    ignore(shell_status("sleep 1"))
  }
  false
}

///|
fn preview_health_attempts() -> Int {
  match @env.get_env_var("MOONCRAFT_PREVIEW_HEALTH_ATTEMPTS") {
    Some(value) => {
      let attempts = @string.parse_int(value.trim().to_owned()) catch {
        _ => 60
      }
      if attempts > 0 {
        attempts
      } else {
        60
      }
    }
    None => 60
  }
}

///|
fn preview_script_relative_path() -> String {
  "./mooncraft-preview.sh"
}

///|
fn preview_script_log_path(project_id : String) -> String {
  "/tmp/mooncraft-preview-\{project_id}.log"
}

///|
fn PreviewManager::rebuild_and_restart(
  self : PreviewManager,
  project : @sdk.ProjectDetail,
) -> Result[@sdk.PreviewTarget, String] {
  let workspace_path = project_workspace(self.root, project.id)
  match fetch_user_project_dependencies(workspace_path) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  let script_probe_code = shell_status(
    "cd " +
    shell_quote(workspace_path) +
    " && test -f " +
    shell_quote(preview_script_relative_path()),
  )
  if script_probe_code != 0 {
    return Err(preview_script_missing_message())
  }
  let preferred_port = project.preview.map(fn(target) { target.port })
  let port = self.allocate_port(
    project.id,
    preferred=preferred_port.unwrap_or(0),
  )
  self.stop_port(port)
  let start_code = shell_status(
    "cd " +
    shell_quote(workspace_path) +
    " && chmod +x " +
    shell_quote(preview_script_relative_path()) +
    " && nohup " +
    shell_quote(preview_script_relative_path()) +
    " \{port} >" +
    shell_quote(preview_script_log_path(project.id)) +
    " 2>&1 &",
  )
  if start_code != 0 {
    return Err("The preview process could not be started.")
  }
  if !self.wait_until_preview_reachable(port, preview_health_attempts()) {
    return Err(
      "The preview process started, but it did not become healthy in time.",
    )
  }
  self.runtimes[project.id] = { port, pid: 0 }
  Ok({ url: public_preview_url(project.preview_public_id), port, healthy: true })
}

///|
async fn AppContext::ensure_project_preview_running(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[@sdk.ProjectDetail, String] noraise {
  if project.status is Running {
    return Ok(project)
  }
  let preview = match project.preview {
    Some(preview) => preview
    None => return Ok(project)
  }
  if preview.healthy && self.previews.is_preview_reachable(preview.port) {
    return Ok(project)
  }
  let workspace_path = project_workspace(self.root, project.id)
  match
    restore_workspace_snapshot(
      self.store,
      self.root,
      project.id,
      workspace_path,
    ) {
    Ok(_) => ignore(())
    Err(message) => {
      let _ = self.store.mark_project_preview_unreachable(
        project.id,
        "Preview restart failed: " + message,
      )
      return Err(message)
    }
  }
  match self.previews.rebuild_and_restart(project) {
    Ok(next_preview) =>
      match self.store.set_project_preview(project.id, next_preview) {
        Some(updated_project) => Ok(updated_project)
        None => Err("Project not found.")
      }
    Err(message) => {
      let _ = self.store.mark_project_preview_unreachable(
        project.id,
        "Preview restart failed: " + message,
      )
      Err(message)
    }
  }
}

///|
fn new(root : String) -> AgentGateway {
  { root, }
}

///|
fn AppContext::try_new(root : String) -> Result[AppContext, String] {
  AppContext::try_new_with_recovery(root, true)
}

///|
async fn AppContext::try_new_for_worker_async(
  root : String,
) -> Result[AppContext, String] noraise {
  let build_profile = build_profile_from_env()
  let data_dir = root + "/data/control-plane"
  ensure_dir(root + "/data")
  ensure_dir(data_dir)
  clean_legacy_project_workspaces(root)
  let db_path = data_dir + "/state-v2.sqlite"
  let store = match try_new_async(db_path) {
    Ok(store) => store
    Err(message) => return Err(message)
  }
  Ok({
    root,
    build_profile,
    store,
    previews: PreviewManager::new(root),
    agent_gateway: new(root),
  })
}

///|
fn AppContext::try_new_with_recovery(
  root : String,
  recover_interrupted : Bool,
) -> Result[AppContext, String] {
  let build_profile = build_profile_from_env()
  let data_dir = root + "/data/control-plane"
  ensure_dir(root + "/data")
  ensure_dir(data_dir)
  clean_legacy_project_workspaces(root)
  let db_path = data_dir + "/state-v2.sqlite"
  let store = match try_new(db_path) {
    Ok(store) => store
    Err(message) => return Err(message)
  }
  let ctx = {
    root,
    build_profile,
    store,
    previews: PreviewManager::new(root),
    agent_gateway: new(root),
  }
  ignore(recover_interrupted)
  Ok(ctx)
}

///|
async fn AppContext::delete_project(
  self : AppContext,
  project_id : String,
) -> Result[Unit, String] noraise {
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
  safe_remove_tree(project_codex_session_root(self.root, project_id))
  safe_remove_tree(project_agent_session_root(self.root, project_id))
  self.store.delete_project(project_id)
}
