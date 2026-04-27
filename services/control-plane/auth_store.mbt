///|
fn nullable_text_value(value : String?) -> @sqlite.SqlValue {
  match value {
    Some(text) => string_to_sql_text(text)
    None => @sqlite.SqlValue::Null
  }
}

///|
fn user_summary_from_stmt(
  stmt : @sqlite.Statement,
  id_col : Int,
  email_col : Int,
  email_verified_col : Int,
  display_name_col : Int,
  github_login_col : Int,
  created_at_col : Int,
) -> @sdk.UserSummary {
  @sdk.UserSummary::{
    id: bytes_to_string(stmt.column_text(id_col)),
    email: bytes_to_string(stmt.column_text(email_col)),
    email_verified: stmt.column_int(email_verified_col) == 1,
    display_name: bytes_to_string(stmt.column_text(display_name_col)),
    github_login: empty_to_none(
      bytes_to_string(stmt.column_text(github_login_col)),
    ),
    created_at: bytes_to_string(stmt.column_text(created_at_col)),
  }
}

///|
fn Store::get_user_by_id(self : Store, user_id : String) -> @sdk.UserSummary? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT id, email, email_verified, display_name, COALESCE(github_login, ''), created_at
        #|FROM users
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(user_id)) |> ignore
  let result = if stmt.step() {
    Some(user_summary_from_stmt(stmt, 0, 1, 2, 3, 4, 5))
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::get_user_by_email(self : Store, email : String) -> @sdk.UserSummary? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT id, email, email_verified, display_name, COALESCE(github_login, ''), created_at
        #|FROM users
        #|WHERE email = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(email)) |> ignore
  let result = if stmt.step() {
    Some(user_summary_from_stmt(stmt, 0, 1, 2, 3, 4, 5))
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::get_user_with_password_hash(
  self : Store,
  email : String,
) -> (@sdk.UserSummary, String?)? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT id, email, email_verified, display_name, COALESCE(github_login, ''), created_at, COALESCE(password_hash, '')
        #|FROM users
        #|WHERE email = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(email)) |> ignore
  let result = if stmt.step() {
    Some(
      (
        user_summary_from_stmt(stmt, 0, 1, 2, 3, 4, 5),
        empty_to_none(bytes_to_string(stmt.column_text(6))),
      ),
    )
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::create_user(
  self : Store,
  email : String,
  password_hash : String?,
  display_name : String,
  github_login : String?,
  email_verified : Bool,
) -> Result[@sdk.UserSummary, String] {
  if self.get_user_by_email(email) is Some(_) {
    return Err("An account with this email already exists.")
  }
  let user_id = next_id("user")
  let now = now_string()
  let stmt = self.db
    .prepare(
      (
        #|INSERT INTO users (
        #|  id,
        #|  email,
        #|  email_verified,
        #|  email_verified_at,
        #|  password_hash,
        #|  display_name,
        #|  github_login,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(user_id),
    string_to_sql_text(email),
    @sqlite.SqlValue::Int(bool_to_int(email_verified)),
    nullable_text_value(if email_verified { Some(now) } else { None }),
    nullable_text_value(password_hash),
    string_to_sql_text(display_name),
    nullable_text_value(github_login),
    string_to_sql_text(now),
    string_to_sql_text(now),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
  Ok(self.get_user_by_id(user_id).unwrap())
}

///|
fn Store::set_user_email_verified(self : Store, user_id : String) -> Unit {
  let now = now_string()
  let stmt = self.db
    .prepare(
      (
        #|UPDATE users
        #|SET email_verified = 1,
        #|  email_verified_at = ?,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(now),
    string_to_sql_text(now),
    string_to_sql_text(user_id),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::update_user_password_hash(
  self : Store,
  user_id : String,
  password_hash : String,
) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|UPDATE users
        #|SET password_hash = ?, updated_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(password_hash),
    string_to_sql_text(now_string()),
    string_to_sql_text(user_id),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::delete_sessions_for_user(self : Store, user_id : String) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|DELETE FROM sessions
        #|WHERE user_id = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(user_id)) |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::delete_account_action_tokens(
  self : Store,
  user_id : String,
  purpose : String,
) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|DELETE FROM account_action_tokens
        #|WHERE user_id = ? AND purpose = ? AND consumed_at IS NULL;
      ),
    )
    .unwrap()
  stmt.bind_all([string_to_sql_text(user_id), string_to_sql_text(purpose)])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::save_account_action_token(
  self : Store,
  user_id : String,
  purpose : String,
  token_hash : String,
  expires_at : String,
) -> Unit {
  self.delete_account_action_tokens(user_id, purpose)
  let stmt = self.db
    .prepare(
      (
        #|INSERT INTO account_action_tokens (
        #|  id,
        #|  user_id,
        #|  purpose,
        #|  token_hash,
        #|  expires_at,
        #|  consumed_at,
        #|  created_at
        #|) VALUES (?, ?, ?, ?, ?, NULL, ?);
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(next_id("acctok")),
    string_to_sql_text(user_id),
    string_to_sql_text(purpose),
    string_to_sql_text(token_hash),
    string_to_sql_text(expires_at),
    string_to_sql_text(now_string()),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::consume_account_action_token(
  self : Store,
  purpose : String,
  token_hash : String,
) -> String? {
  let now = unix_millis_string()
  let select_stmt = self.db
    .prepare(
      (
        #|SELECT user_id
        #|FROM account_action_tokens
        #|WHERE purpose = ?
        #|  AND token_hash = ?
        #|  AND expires_at > ?
        #|  AND consumed_at IS NULL;
      ),
    )
    .unwrap()
  select_stmt.bind_all([
    string_to_sql_text(purpose),
    string_to_sql_text(token_hash),
    string_to_sql_text(now),
  ])
  |> ignore
  let result = if select_stmt.step() {
    Some(bytes_to_string(select_stmt.column_text(0)))
  } else {
    None
  }
  select_stmt.finalize()
  if result is Some(_) {
    let update_stmt = self.db
      .prepare(
        (
          #|UPDATE account_action_tokens
          #|SET consumed_at = ?
          #|WHERE purpose = ? AND token_hash = ?;
        ),
      )
      .unwrap()
    update_stmt.bind_all([
      string_to_sql_text(now_string()),
      string_to_sql_text(purpose),
      string_to_sql_text(token_hash),
    ])
    |> ignore
    update_stmt.execute() |> ignore
    update_stmt.finalize()
  }
  result
}

///|
fn Store::update_user_github_login(
  self : Store,
  user_id : String,
  github_login : String,
) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|UPDATE users
        #|SET github_login = ?, updated_at = ?
        #|WHERE id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(github_login),
    string_to_sql_text(now_string()),
    string_to_sql_text(user_id),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::find_user_by_oauth_account(
  self : Store,
  provider : String,
  provider_user_id : String,
) -> @sdk.UserSummary? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT u.id, u.email, u.email_verified, u.display_name, COALESCE(u.github_login, ''), u.created_at
        #|FROM oauth_accounts oa
        #|JOIN users u ON u.id = oa.user_id
        #|WHERE oa.provider = ? AND oa.provider_user_id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(provider),
    string_to_sql_text(provider_user_id),
  ])
  |> ignore
  let result = if stmt.step() {
    Some(user_summary_from_stmt(stmt, 0, 1, 2, 3, 4, 5))
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::link_oauth_account(
  self : Store,
  user_id : String,
  provider : String,
  provider_user_id : String,
) -> Unit {
  let now = now_string()
  let stmt = self.db
    .prepare(
      (
        #|INSERT OR IGNORE INTO oauth_accounts (
        #|  id,
        #|  user_id,
        #|  provider,
        #|  provider_user_id,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(next_id("oauth")),
    string_to_sql_text(user_id),
    string_to_sql_text(provider),
    string_to_sql_text(provider_user_id),
    string_to_sql_text(now),
    string_to_sql_text(now),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::create_session(
  self : Store,
  user_id : String,
  token_hash : String,
  expires_at : String,
) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|INSERT INTO sessions (
        #|  token_hash,
        #|  user_id,
        #|  expires_at,
        #|  created_at
        #|) VALUES (?, ?, ?, ?);
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(token_hash),
    string_to_sql_text(user_id),
    string_to_sql_text(expires_at),
    string_to_sql_text(now_string()),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::delete_session(self : Store, token_hash : String) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|DELETE FROM sessions
        #|WHERE token_hash = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(token_hash)) |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::get_user_by_session_token_hash(
  self : Store,
  token_hash : String,
) -> @sdk.UserSummary? {
  let now = unix_millis_string()
  let stmt = self.db
    .prepare(
      (
        #|SELECT u.id, u.email, u.email_verified, u.display_name, COALESCE(u.github_login, ''), u.created_at
        #|FROM sessions s
        #|JOIN users u ON u.id = s.user_id
        #|WHERE s.token_hash = ? AND s.expires_at > ?;
      ),
    )
    .unwrap()
  stmt.bind_all([string_to_sql_text(token_hash), string_to_sql_text(now)])
  |> ignore
  let result = if stmt.step() {
    Some(user_summary_from_stmt(stmt, 0, 1, 2, 3, 4, 5))
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::save_oauth_state(
  self : Store,
  provider : String,
  state : String,
  pkce_verifier : String,
  expires_at : String,
) -> Unit {
  let stmt = self.db
    .prepare(
      (
        #|INSERT INTO oauth_states (
        #|  state,
        #|  provider,
        #|  pkce_verifier,
        #|  expires_at,
        #|  created_at
        #|) VALUES (?, ?, ?, ?, ?);
      ),
    )
    .unwrap()
  stmt.bind_all([
    string_to_sql_text(state),
    string_to_sql_text(provider),
    string_to_sql_text(pkce_verifier),
    string_to_sql_text(expires_at),
    string_to_sql_text(now_string()),
  ])
  |> ignore
  stmt.execute() |> ignore
  stmt.finalize()
}

///|
fn Store::consume_oauth_state(
  self : Store,
  provider : String,
  state : String,
) -> String? {
  let now = unix_millis_string()
  let select_stmt = self.db
    .prepare(
      (
        #|SELECT pkce_verifier
        #|FROM oauth_states
        #|WHERE provider = ? AND state = ? AND expires_at > ?;
      ),
    )
    .unwrap()
  select_stmt.bind_all([
    string_to_sql_text(provider),
    string_to_sql_text(state),
    string_to_sql_text(now),
  ])
  |> ignore
  let result = if select_stmt.step() {
    Some(bytes_to_string(select_stmt.column_text(0)))
  } else {
    None
  }
  select_stmt.finalize()

  let delete_stmt = self.db
    .prepare(
      (
        #|DELETE FROM oauth_states
        #|WHERE provider = ? AND state = ?;
      ),
    )
    .unwrap()
  delete_stmt.bind_all([string_to_sql_text(provider), string_to_sql_text(state)])
  |> ignore
  delete_stmt.execute() |> ignore
  delete_stmt.finalize()
  result
}

///|
fn Store::project_owned_by_user(
  self : Store,
  project_id : String,
  user_id : String,
) -> Bool {
  let stmt = self.db
    .prepare(
      (
        #|SELECT 1
        #|FROM projects
        #|WHERE id = ? AND owner_user_id = ?;
      ),
    )
    .unwrap()
  stmt.bind_all([string_to_sql_text(project_id), string_to_sql_text(user_id)])
  |> ignore
  let owned = stmt.step()
  stmt.finalize()
  owned
}

///|
fn Store::list_projects_for_user(
  self : Store,
  user_id : String,
) -> Array[@sdk.ProjectSummary] {
  let stmt = self.db
    .prepare(
      (
        #|SELECT
        #|  id,
        #|  preview_public_id,
        #|  display_name,
        #|  template_id,
        #|  template_version,
        #|  status,
        #|  COALESCE(preview_url, ''),
        #|  COALESCE(preview_port, 0),
        #|  preview_healthy,
        #|  COALESCE(current_run_id, ''),
        #|  updated_at
        #|FROM projects
        #|WHERE owner_user_id = ?
        #|ORDER BY updated_at DESC;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(user_id)) |> ignore
  let items : Array[@sdk.ProjectSummary] = []
  while stmt.step() {
    let project_id = bytes_to_string(stmt.column_text(0))
    let preview = preview_from_columns(
      bytes_to_string(stmt.column_text(1)),
      bytes_to_string(stmt.column_text(6)),
      stmt.column_int(7),
      stmt.column_int(8),
    )
    items.push(@sdk.ProjectSummary::{
      id: project_id,
      display_name: bytes_to_string(stmt.column_text(2)),
      template_id: bytes_to_string(stmt.column_text(3)),
      template_version: bytes_to_string(stmt.column_text(4)),
      status: run_state_from_db(bytes_to_string(stmt.column_text(5))),
      preview,
      current_run_id: empty_to_none(bytes_to_string(stmt.column_text(9))),
      updated_at: bytes_to_string(stmt.column_text(10)),
    })
  }
  stmt.finalize()
  items
}

///|
fn Store::get_project_detail_for_user(
  self : Store,
  project_id : String,
  user_id : String,
) -> @sdk.ProjectDetail? {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  self.get_project_detail(project_id)
}

///|
fn Store::get_project_detail_by_preview_public_id(
  self : Store,
  preview_public_id : String,
) -> @sdk.ProjectDetail? {
  let stmt = self.db
    .prepare(
      (
        #|SELECT id
        #|FROM projects
        #|WHERE preview_public_id = ?;
      ),
    )
    .unwrap()
  stmt.bind(1, string_to_sql_text(preview_public_id)) |> ignore
  let result = if stmt.step() {
    let project_id = bytes_to_string(stmt.column_text(0))
    self.get_project_detail(project_id)
  } else {
    None
  }
  stmt.finalize()
  result
}

///|
fn Store::create_project_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  display_name : String?,
  workspace_path : String,
  template_id : String,
  template_version : String,
) -> @sdk.ProjectDetail {
  self.create_project(
    project_id,
    user_id,
    new_preview_public_id(),
    display_name,
    workspace_path,
    template_id,
    template_version,
  )
}

///|
fn Store::start_run_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  content : String,
) -> Result[@sdk.RunStatusResponse, String] {
  if !self.project_owned_by_user(project_id, user_id) {
    return Err("Project not found.")
  }
  self.start_run(project_id, content)
}

///|
fn Store::list_messages_for_user(
  self : Store,
  user_id : String,
  project_id : String,
) -> Array[@sdk.ChatMessage]? {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  Some(self.list_messages(project_id))
}

///|
fn Store::list_run_events_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  run_id : String,
  after_seq : Int,
) -> Array[@sdk.RunEvent]? {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  if self.get_run(project_id, run_id) is None {
    return None
  }
  Some(self.list_run_events(project_id, run_id, after_seq))
}

///|
fn Store::get_run_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  run_id : String,
) -> @sdk.RunStatusResponse? {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  self.get_run(project_id, run_id)
}
