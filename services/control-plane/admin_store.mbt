///|
fn admin_owner_from_row(row : Map[String, @db.Param]) -> @sdk.UserSummary? {
  let owner_id = row_text(row, "owner_id")
  if owner_id == "" {
    None
  } else {
    Some({
      id: owner_id,
      email: row_text(row, "owner_email"),
      email_verified: row_bool(row, "owner_email_verified"),
      display_name: row_text(row, "owner_display_name"),
      github_login: empty_to_none(row_text(row, "owner_github_login")),
      created_at: row_text(row, "owner_created_at"),
    })
  }
}

///|
fn admin_project_summary_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AdminProjectSummary {
  {
    project: project_detail_from_row(row),
    owner: admin_owner_from_row(row),
    message_count: row_int(row, "message_count"),
    run_count: row_int(row, "run_count"),
  }
}

///|
fn admin_project_select_sql() -> String {
  (
    #|SELECT
    #|  p.id,
    #|  p.preview_public_id,
    #|  p.display_name,
    #|  p.runtime_id,
    #|  p.runtime_name,
    #|  p.runtime_spec_json,
    #|  p.agent_session_id,
    #|  COALESCE(p.runtime_session_id, '') AS runtime_session_id,
    #|  p.agent_cli,
    #|  p.ai_model,
    #|  p.workspace_path,
    #|  COALESCE(p.codex_thread_id, '') AS codex_thread_id,
    #|  p.status,
    #|  COALESCE(p.preview_url, '') AS preview_url,
    #|  COALESCE(p.preview_port, 0) AS preview_port,
    #|  p.preview_healthy,
    #|  COALESCE(p.last_error, '') AS last_error,
    #|  COALESCE(p.current_run_id, '') AS current_run_id,
    #|  COALESCE(cr.phase, 'none') AS current_run_phase,
    #|  p.created_at,
    #|  p.updated_at,
    #|  COALESCE(u.id, '') AS owner_id,
    #|  COALESCE(u.email, '') AS owner_email,
    #|  COALESCE(u.email_verified, 0) AS owner_email_verified,
    #|  COALESCE(u.display_name, '') AS owner_display_name,
    #|  COALESCE(u.github_login, '') AS owner_github_login,
    #|  COALESCE(u.created_at, '') AS owner_created_at,
    #|  (
    #|    SELECT COUNT(*)
    #|    FROM messages m
    #|    WHERE m.project_id = p.id
    #|  ) AS message_count,
    #|  (
    #|    SELECT COUNT(*)
    #|    FROM runs r
    #|    WHERE r.project_id = p.id
    #|  ) AS run_count
    #|FROM projects p
    #|LEFT JOIN users u ON u.id = p.owner_user_id
    #|LEFT JOIN runs cr ON cr.id = p.current_run_id AND cr.project_id = p.id
  )
}

///|
fn admin_user_summary_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AdminUserSummary {
  {
    user: user_summary_from_row(row),
    project_count: row_int(row, "project_count"),
    running_project_count: row_int(row, "running_project_count"),
    latest_project_updated_at: empty_to_none(
      row_text(row, "latest_project_updated_at"),
    ),
    latest_run_started_at: empty_to_none(row_text(row, "latest_run_started_at")),
  }
}

///|
fn admin_user_detail_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AdminUserDetail {
  {
    user: user_summary_from_row(row),
    project_count: row_int(row, "project_count"),
    running_project_count: row_int(row, "running_project_count"),
    session_count: row_int(row, "session_count"),
    oauth_providers: [],
    latest_project_updated_at: empty_to_none(
      row_text(row, "latest_project_updated_at"),
    ),
    latest_run_started_at: empty_to_none(row_text(row, "latest_run_started_at")),
  }
}

///|
async fn Store::list_admin_users(
  self : Store,
  limit : Int,
) -> Array[@sdk.AdminUserSummary] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  u.id,
      #|  u.email,
      #|  u.email_verified,
      #|  u.display_name,
      #|  COALESCE(u.github_login, '') AS github_login,
      #|  u.created_at,
      #|  COUNT(DISTINCT p.id) AS project_count,
      #|  SUM(CASE WHEN p.status = 'running' THEN 1 ELSE 0 END) AS running_project_count,
      #|  COALESCE(MAX(p.updated_at), '') AS latest_project_updated_at,
      #|  COALESCE(MAX(r.started_at), '') AS latest_run_started_at
      #|FROM users u
      #|LEFT JOIN projects p ON p.owner_user_id = u.id
      #|LEFT JOIN runs r ON r.project_id = p.id
      #|GROUP BY u.id, u.email, u.email_verified, u.display_name, u.github_login, u.created_at
      #|ORDER BY COALESCE(MAX(p.updated_at), u.created_at) DESC
      #|LIMIT ?;
    ),
    params=[Int(limit)],
  )
  let items : Array[@sdk.AdminUserSummary] = []
  for row in rows {
    items.push(admin_user_summary_from_row(row))
  }
  items
}

///|
async fn Store::get_admin_user_detail(
  self : Store,
  user_id : String,
) -> @sdk.AdminUserDetail? noraise {
  let detail = match
    self.query_one(
      (
        #|SELECT
        #|  u.id,
        #|  u.email,
        #|  u.email_verified,
        #|  u.display_name,
        #|  COALESCE(u.github_login, '') AS github_login,
        #|  u.created_at,
        #|  COUNT(DISTINCT p.id) AS project_count,
        #|  SUM(CASE WHEN p.status = 'running' THEN 1 ELSE 0 END) AS running_project_count,
        #|  COUNT(DISTINCT s.token_hash) AS session_count,
        #|  COALESCE(MAX(p.updated_at), '') AS latest_project_updated_at,
        #|  COALESCE(MAX(r.started_at), '') AS latest_run_started_at
        #|FROM users u
        #|LEFT JOIN projects p ON p.owner_user_id = u.id
        #|LEFT JOIN runs r ON r.project_id = p.id
        #|LEFT JOIN sessions s ON s.user_id = u.id
        #|WHERE u.id = ?
        #|GROUP BY u.id, u.email, u.email_verified, u.display_name, u.github_login, u.created_at;
      ),
      params=[String(user_id)],
    ) {
    Some(row) => admin_user_detail_from_row(row)
    None => return None
  }
  let provider_rows = self.query_rows(
    (
      #|SELECT DISTINCT provider
      #|FROM oauth_accounts
      #|WHERE user_id = ?
      #|ORDER BY provider ASC;
    ),
    params=[String(user_id)],
  )
  let providers : Array[String] = []
  for row in provider_rows {
    providers.push(row_text(row, "provider"))
  }
  Some({ ..detail, oauth_providers: providers })
}

///|
async fn Store::list_admin_project_summaries_for_user(
  self : Store,
  user_id : String,
) -> Array[@sdk.AdminProjectSummary] noraise {
  let rows = self.query_rows(
    admin_project_select_sql() +
    (
      #|
      #|WHERE p.owner_user_id = ?
      #|ORDER BY p.updated_at DESC;
    ),
    params=[String(user_id)],
  )
  let items : Array[@sdk.AdminProjectSummary] = []
  for row in rows {
    items.push(admin_project_summary_from_row(row))
  }
  items
}

///|
async fn Store::list_recent_admin_project_summaries(
  self : Store,
  limit : Int,
) -> Array[@sdk.AdminProjectSummary] noraise {
  let rows = self.query_rows(
    admin_project_select_sql() +
    (
      #|
      #|ORDER BY p.updated_at DESC
      #|LIMIT ?;
    ),
    params=[Int(limit)],
  )
  let items : Array[@sdk.AdminProjectSummary] = []
  for row in rows {
    items.push(admin_project_summary_from_row(row))
  }
  items
}

///|
async fn Store::get_admin_project_summary(
  self : Store,
  project_id : String,
) -> @sdk.AdminProjectSummary? noraise {
  match
    self.query_one(
      admin_project_select_sql() +
      (
        #|
        #|WHERE p.id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => Some(admin_project_summary_from_row(row))
    None => None
  }
}
