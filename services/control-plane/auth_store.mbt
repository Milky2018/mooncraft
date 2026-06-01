///|
fn user_summary_from_row(row : Map[String, @db.Param]) -> @sdk.UserSummary {
  {
    id: row_text(row, "id"),
    email: row_text(row, "email"),
    email_verified: row_bool(row, "email_verified"),
    display_name: row_text(row, "display_name"),
    github_login: empty_to_none(row_text(row, "github_login")),
    created_at: row_text(row, "created_at"),
  }
}

///|
async fn Store::get_user_by_id(
  self : Store,
  user_id : String,
) -> @sdk.UserSummary? noraise {
  match
    self.query_one(
      (
        #|SELECT id, email, email_verified, display_name, COALESCE(github_login, '') AS github_login, created_at
        #|FROM users
        #|WHERE id = ?;
      ),
      params=[String(user_id)],
    ) {
    Some(row) => Some(user_summary_from_row(row))
    None => None
  }
}

///|
async fn Store::get_user_by_email(
  self : Store,
  email : String,
) -> @sdk.UserSummary? noraise {
  match
    self.query_one(
      (
        #|SELECT id, email, email_verified, display_name, COALESCE(github_login, '') AS github_login, created_at
        #|FROM users
        #|WHERE email = ?;
      ),
      params=[String(email)],
    ) {
    Some(row) => Some(user_summary_from_row(row))
    None => None
  }
}

///|
async fn Store::create_user(
  self : Store,
  email : String,
  password_hash : String?,
  display_name : String,
  github_login : String?,
  email_verified : Bool,
) -> Result[@sdk.UserSummary, String] noraise {
  if self.get_user_by_email(email) is Some(_) {
    return Err("An account with this email already exists.")
  }
  let user_id = next_id("user")
  let now = now_string()
  match
    self.exec_or_error(
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
      "create user",
      params=[
        String(user_id),
        String(email),
        Int(bool_to_int(email_verified)),
        nullable_text_param(if email_verified { Some(now) } else { None }),
        nullable_text_param(password_hash),
        String(display_name),
        nullable_text_param(github_login),
        String(now),
        String(now),
      ],
    ) {
    Ok(_) =>
      match self.get_user_by_id(user_id) {
        Some(user) => Ok(user)
        None => Err("The user was created but could not be loaded.")
      }
    Err(message) => Err(message)
  }
}

///|
async fn Store::set_user_email_verified(
  self : Store,
  user_id : String,
) -> Unit noraise {
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|UPDATE users
        #|SET email_verified = 1,
        #|  email_verified_at = ?,
        #|  updated_at = ?
        #|WHERE id = ?;
      ),
      "set user email verified",
      params=[String(now), String(now), String(user_id)],
    ),
  )
}

///|
async fn Store::update_user_github_login(
  self : Store,
  user_id : String,
  github_login : String,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      (
        #|UPDATE users
        #|SET github_login = ?, updated_at = ?
        #|WHERE id = ?;
      ),
      "update user GitHub login",
      params=[String(github_login), String(now_string()), String(user_id)],
    ),
  )
}

///|
async fn Store::find_user_by_oauth_account(
  self : Store,
  provider : String,
  provider_user_id : String,
) -> @sdk.UserSummary? noraise {
  match
    self.query_one(
      (
        #|SELECT u.id, u.email, u.email_verified, u.display_name, COALESCE(u.github_login, '') AS github_login, u.created_at
        #|FROM oauth_accounts oa
        #|JOIN users u ON u.id = oa.user_id
        #|WHERE oa.provider = ? AND oa.provider_user_id = ?;
      ),
      params=[String(provider), String(provider_user_id)],
    ) {
    Some(row) => Some(user_summary_from_row(row))
    None => None
  }
}

///|
async fn Store::link_oauth_account(
  self : Store,
  user_id : String,
  provider : String,
  provider_user_id : String,
) -> Unit noraise {
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO oauth_accounts (
        #|  id,
        #|  user_id,
        #|  provider,
        #|  provider_user_id,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?)
        #|ON CONFLICT(provider, provider_user_id) DO NOTHING;
      ),
      "link OAuth account",
      params=[
        String(next_id("oauth")),
        String(user_id),
        String(provider),
        String(provider_user_id),
        String(now),
        String(now),
      ],
    ),
  )
}

///|
async fn Store::create_session(
  self : Store,
  user_id : String,
  token_hash : String,
  expires_at : String,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO sessions (
        #|  token_hash,
        #|  user_id,
        #|  expires_at,
        #|  created_at
        #|) VALUES (?, ?, ?, ?);
      ),
      "create session",
      params=[
        String(token_hash),
        String(user_id),
        String(expires_at),
        String(now_string()),
      ],
    ),
  )
}

///|
async fn Store::delete_session(
  self : Store,
  token_hash : String,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      "DELETE FROM sessions WHERE token_hash = ?;",
      "delete session",
      params=[String(token_hash)],
    ),
  )
}

///|
async fn Store::get_user_by_session_token_hash(
  self : Store,
  token_hash : String,
) -> @sdk.UserSummary? noraise {
  let now = unix_millis_string()
  match
    self.query_one(
      (
        #|SELECT u.id, u.email, u.email_verified, u.display_name, COALESCE(u.github_login, '') AS github_login, u.created_at
        #|FROM sessions s
        #|JOIN users u ON u.id = s.user_id
        #|WHERE s.token_hash = ? AND s.expires_at > ?;
      ),
      params=[String(token_hash), String(now)],
    ) {
    Some(row) => Some(user_summary_from_row(row))
    None => None
  }
}

///|
async fn Store::save_oauth_state(
  self : Store,
  provider : String,
  state : String,
  pkce_verifier : String,
  expires_at : String,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO oauth_states (
        #|  state,
        #|  provider,
        #|  pkce_verifier,
        #|  expires_at,
        #|  created_at
        #|) VALUES (?, ?, ?, ?, ?);
      ),
      "save OAuth state",
      params=[
        String(state),
        String(provider),
        String(pkce_verifier),
        String(expires_at),
        String(now_string()),
      ],
    ),
  )
}

///|
async fn Store::consume_oauth_state(
  self : Store,
  provider : String,
  state : String,
) -> String? noraise {
  let now = unix_millis_string()
  let result = match
    self.query_one(
      (
        #|SELECT pkce_verifier
        #|FROM oauth_states
        #|WHERE provider = ? AND state = ? AND expires_at > ?;
      ),
      params=[String(provider), String(state), String(now)],
    ) {
    Some(row) => Some(row_text(row, "pkce_verifier"))
    None => None
  }
  ignore(
    self.exec_or_error(
      (
        #|DELETE FROM oauth_states
        #|WHERE provider = ? AND state = ?;
      ),
      "delete OAuth state",
      params=[String(provider), String(state)],
    ),
  )
  result
}

///|
async fn Store::project_owned_by_user(
  self : Store,
  project_id : String,
  user_id : String,
) -> Bool noraise {
  self.query_one(
    (
      #|SELECT 1 AS owned
      #|FROM projects
      #|WHERE id = ? AND owner_user_id = ?;
    ),
    params=[String(project_id), String(user_id)],
  )
  is Some(_)
}

///|
fn project_summary_from_row(
  row : Map[String, @db.Param],
) -> @sdk.ProjectSummary {
  let preview = preview_from_columns(
    row_text(row, "preview_public_id"),
    row_text(row, "preview_url"),
    row_int(row, "preview_port"),
    row_int(row, "preview_healthy"),
  )
  let activity = project_activity_from_row(row)
  {
    id: row_text(row, "id"),
    display_name: row_text(row, "display_name"),
    runtime_id: row_text(row, "runtime_id"),
    runtime_name: row_text(row, "runtime_name"),
    agent_session_id: row_text(row, "agent_session_id"),
    agent_cli: row_text(row, "agent_cli"),
    model: row_text(row, "ai_model"),
    status: project_status_from_row(row),
    is_processing: activity is Some(_),
    activity,
    current_run_phase: run_phase_from_db(row_text(row, "current_run_phase")),
    preview,
    current_run_id: empty_to_none(row_text(row, "current_run_id")),
    updated_at: row_text(row, "updated_at"),
  }
}

///|
async fn Store::list_projects_for_user(
  self : Store,
  user_id : String,
) -> Array[@sdk.ProjectSummary] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  p.id,
      #|  p.preview_public_id,
      #|  p.display_name,
      #|  p.runtime_id,
      #|  p.runtime_name,
      #|  p.agent_session_id,
      #|  p.agent_cli,
      #|  p.ai_model,
      #|  p.status,
      #|  COALESCE(p.preview_url, '') AS preview_url,
      #|  COALESCE(p.preview_port, 0) AS preview_port,
      #|  p.preview_healthy,
      #|  COALESCE(p.current_run_id, '') AS current_run_id,
      #|  COALESCE(r.phase, 'none') AS current_run_phase,
      #|  COALESCE((
      #|    SELECT re.code
      #|    FROM run_events re
      #|    WHERE re.project_id = p.id AND re.run_id = p.current_run_id
      #|    ORDER BY re.seq DESC
      #|    LIMIT 1
      #|  ), '') AS current_run_activity_code,
      #|  COALESCE((
      #|    SELECT re.content
      #|    FROM run_events re
      #|    WHERE re.project_id = p.id AND re.run_id = p.current_run_id
      #|    ORDER BY re.seq DESC
      #|    LIMIT 1
      #|  ), '') AS current_run_activity_text,
      #|  p.updated_at
      #|FROM projects p
      #|LEFT JOIN runs r ON r.id = p.current_run_id AND r.project_id = p.id
      #|WHERE p.owner_user_id = ?
      #|ORDER BY p.updated_at DESC;
    ),
    params=[String(user_id)],
  )
  let items : Array[@sdk.ProjectSummary] = []
  for row in rows {
    items.push(project_summary_from_row(row))
  }
  items
}

///|
async fn Store::get_project_detail_for_user(
  self : Store,
  project_id : String,
  user_id : String,
) -> @sdk.ProjectDetail? noraise {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  self.get_project_detail(project_id)
}

///|
async fn Store::get_project_detail_by_preview_public_id(
  self : Store,
  preview_public_id : String,
) -> @sdk.ProjectDetail? noraise {
  match
    self.query_one(
      (
        #|SELECT id
        #|FROM projects
        #|WHERE preview_public_id = ?;
      ),
      params=[String(preview_public_id)],
    ) {
    Some(row) => self.get_project_detail(row_text(row, "id"))
    None => None
  }
}

///|
async fn Store::create_project_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  display_name : String,
  runtime_id : String,
  runtime_name : String,
  runtime_config_json : String,
  agent_session_id : String,
  agent_cli : String,
  model : String,
  workspace_path : String,
) -> @sdk.ProjectDetail noraise {
  self.create_project_with_runtime(
    project_id,
    user_id,
    new_preview_public_id(),
    display_name,
    runtime_id,
    runtime_name,
    runtime_config_json,
    agent_session_id,
    agent_cli,
    model,
    workspace_path,
  )
}

///|
async fn Store::update_project_settings_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  display_name : String?,
  model : String?,
) -> @sdk.ProjectDetail? noraise {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  self.update_project_settings(project_id, display_name, model)
}

///|
async fn Store::start_run_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  content : String,
) -> Result[@sdk.RunStatusResponse, String] noraise {
  if !self.project_owned_by_user(project_id, user_id) {
    return Err("Project not found.")
  }
  self.start_run(project_id, content)
}

///|
async fn Store::list_messages_for_user(
  self : Store,
  user_id : String,
  project_id : String,
) -> Array[@sdk.ChatMessage]? noraise {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  Some(self.list_messages(project_id))
}

///|
async fn Store::get_run_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  run_id : String,
) -> @sdk.RunStatusResponse? noraise {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  self.get_run(project_id, run_id)
}

///|
async fn Store::list_run_events_for_user(
  self : Store,
  user_id : String,
  project_id : String,
  run_id : String,
  after_seq : Int,
) -> Array[@sdk.RunEvent]? noraise {
  if !self.project_owned_by_user(project_id, user_id) {
    return None
  }
  if self.get_run(project_id, run_id) is None {
    return None
  }
  Some(self.list_run_events(project_id, run_id, after_seq))
}
