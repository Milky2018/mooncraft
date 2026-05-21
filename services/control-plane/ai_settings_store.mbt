///|
struct AiRuntimeSettings {
  runtime_id : String
  runtime_name : String
  runtime_spec : @sdk.RuntimeSpec
  agent_session_id : String
  runtime_session_id : String?
  provider : String
  api_key : String
}

///|
fn default_agent_cli() -> String {
  "codex"
}

///|
fn default_openrouter_model() -> String {
  "openai/gpt-5.4-mini"
}

///|
fn normalize_agent_cli(value : String) -> Result[String, String] {
  match value.trim().to_owned().to_lower() {
    "" => Ok(default_agent_cli())
    "codex" => Ok("codex")
    "claude_code" => Ok("claude_code")
    "claude-code" => Ok("claude_code")
    "claude" => Ok("claude_code")
    "kimi_code" => Ok("kimi_code")
    "kimi-code" => Ok("kimi_code")
    "kimi" => Ok("kimi_code")
    _ => Err("Agent must be Codex, Claude Code, or Kimi Code.")
  }
}

///|
fn normalize_ai_key_status(status : String) -> Result[String, String] {
  match status.trim().to_owned().to_lower() {
    "active" => Ok("active")
    "disabled" => Ok("disabled")
    "exhausted" => Ok("exhausted")
    "error" => Ok("error")
    _ => Err("AI key status must be active, disabled, exhausted, or error.")
  }
}

///|
fn normalize_openrouter_model(model : String) -> String {
  let trimmed = model.trim().to_owned()
  if trimmed == "" {
    default_openrouter_model()
  } else {
    trimmed
  }
}

///|
fn normalize_allowed_models(models : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for model in models {
    let normalized = model.trim().to_owned()
    if normalized != "" && !result.contains(normalized) {
      result.push(normalized)
    }
  }
  result
}

///|
fn allowed_models_to_db(models : Array[String]) -> String {
  normalize_allowed_models(models).join("\n")
}

///|
fn allowed_models_from_db(value : String) -> Array[String] {
  normalize_allowed_models(
    value.split("\n").to_array().map(fn(line) { line.to_owned() }),
  )
}

///|
fn ai_key_hint(secret : String) -> String {
  let trimmed = secret.trim().to_owned()
  if trimmed.length() <= 4 {
    "saved key"
  } else {
    "**** " + trimmed[trimmed.length() - 4:].to_owned()
  }
}

///|
fn admin_ai_key_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AdminAiKeySummary {
  {
    id: row_text(row, "id"),
    provider: row_text(row, "provider"),
    label: row_text(row, "label"),
    key_hint: row_text(row, "key_hint"),
    status: row_text(row, "status"),
    priority: row_int(row, "priority"),
    last_used_at: empty_to_none(row_text(row, "last_used_at")),
    last_error: empty_to_none(row_text(row, "last_error")),
    created_at: row_text(row, "created_at"),
    updated_at: row_text(row, "updated_at"),
  }
}

///|
fn admin_ai_key_usage_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AdminAiKeyUsageSummary {
  {
    id: row_text(row, "id"),
    key_id: row_text(row, "key_id"),
    run_id: row_text(row, "run_id"),
    project_id: row_text(row, "project_id"),
    user_id: row_text(row, "user_id"),
    model: row_text(row, "model"),
    state: row_text(row, "state"),
    error_code: empty_to_none(row_text(row, "error_code")),
    started_at: row_text(row, "started_at"),
    finished_at: empty_to_none(row_text(row, "finished_at")),
  }
}

///|
async fn Store::get_admin_ai_config(
  self : Store,
) -> @sdk.AdminAiConfigResponse noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  COALESCE(default_model, '') AS default_model,
        #|  COALESCE(allowed_models, '') AS allowed_models,
        #|  updated_at
        #|FROM ai_runtime_config
        #|WHERE id = ?;
      ),
      params=[String("default")],
    ) {
    Some(row) => {
      let default_model = normalize_openrouter_model(
        row_text(row, "default_model"),
      )
      let allowed_models = allowed_models_from_db(
        row_text(row, "allowed_models"),
      )
      {
        default_model,
        allowed_models: if allowed_models.length() == 0 {
          [default_model]
        } else {
          allowed_models
        },
        updated_at: row_text(row, "updated_at"),
      }
    }
    None =>
      {
        default_model: default_openrouter_model(),
        allowed_models: [default_openrouter_model()],
        updated_at: now_string(),
      }
  }
}

///|
async fn Store::update_admin_ai_config(
  self : Store,
  default_model_input : String,
  allowed_models_input : Array[String],
) -> Result[@sdk.AdminAiConfigResponse, String] noraise {
  let default_model = normalize_openrouter_model(default_model_input)
  let allowed_models = normalize_allowed_models(allowed_models_input)
  let persisted_allowed = if allowed_models.length() == 0 {
    [default_model]
  } else if allowed_models.contains(default_model) {
    allowed_models
  } else {
    let next = [default_model]
    for model in allowed_models {
      next.push(model)
    }
    next
  }
  let now = now_string()
  match
    self.exec_or_error(
      (
        #|INSERT INTO ai_runtime_config (
        #|  id,
        #|  default_model,
        #|  allowed_models,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?)
        #|ON CONFLICT(id) DO UPDATE SET
        #|  default_model = excluded.default_model,
        #|  allowed_models = excluded.allowed_models,
        #|  updated_at = excluded.updated_at;
      ),
      "update AI runtime config",
      params=[
        String("default"),
        String(default_model),
        String(allowed_models_to_db(persisted_allowed)),
        String(now),
      ],
    ) {
    Ok(_) =>
      Ok({ default_model, allowed_models: persisted_allowed, updated_at: now })
    Err(message) => Err(message)
  }
}

///|
async fn Store::list_admin_ai_keys(
  self : Store,
) -> Array[@sdk.AdminAiKeySummary] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  provider,
      #|  label,
      #|  COALESCE(key_hint, '') AS key_hint,
      #|  status,
      #|  priority,
      #|  COALESCE(last_used_at, '') AS last_used_at,
      #|  COALESCE(last_error, '') AS last_error,
      #|  created_at,
      #|  updated_at
      #|FROM ai_keys
      #|ORDER BY priority DESC, created_at ASC;
    ),
  )
  let items : Array[@sdk.AdminAiKeySummary] = []
  for row in rows {
    items.push(admin_ai_key_from_row(row))
  }
  items
}

///|
async fn Store::get_active_openrouter_api_key(
  self : Store,
) -> Result[String, String] noraise {
  match
    self.query_one(
      (
        #|SELECT COALESCE(key_secret, '') AS key_secret
        #|FROM ai_keys
        #|WHERE provider = ? AND status = ?
        #|  AND COALESCE(key_secret, '') <> ''
        #|ORDER BY priority DESC, COALESCE(last_used_at, '') ASC, created_at ASC
        #|LIMIT 1;
      ),
      params=[String("openrouter"), String("active")],
    ) {
    Some(row) => {
      let api_key = row_text(row, "key_secret").trim().to_owned()
      if api_key == "" {
        Err("No active OpenRouter key is available.")
      } else {
        Ok(api_key)
      }
    }
    None => Err("Add an active OpenRouter key before loading models.")
  }
}

///|
async fn Store::create_admin_ai_key(
  self : Store,
  label_input : String,
  api_key_input : String,
  priority : Int,
) -> Result[@sdk.AdminAiKeySummary, String] noraise {
  let label = label_input.trim().to_owned()
  let api_key = api_key_input.trim().to_owned()
  if label == "" {
    return Err("AI key label is required.")
  }
  if api_key == "" {
    return Err("OpenRouter API key is required.")
  }
  let id = next_id("ai-key")
  let now = now_string()
  let insert_result = match self.column_exists("ai_keys", "key_env_ref") {
    Ok(true) =>
      self.exec_or_error(
        (
          #|INSERT INTO ai_keys (
          #|  id,
          #|  provider,
          #|  label,
          #|  key_secret,
          #|  key_hint,
          #|  key_env_ref,
          #|  status,
          #|  priority,
          #|  created_at,
          #|  updated_at
          #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        ),
        "create AI key",
        params=[
          String(id),
          String("openrouter"),
          String(label),
          String(api_key),
          String(ai_key_hint(api_key)),
          String(id),
          String("active"),
          Int(priority),
          String(now),
          String(now),
        ],
      )
    _ =>
      self.exec_or_error(
        (
          #|INSERT INTO ai_keys (
          #|  id,
          #|  provider,
          #|  label,
          #|  key_secret,
          #|  key_hint,
          #|  status,
          #|  priority,
          #|  created_at,
          #|  updated_at
          #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        ),
        "create AI key",
        params=[
          String(id),
          String("openrouter"),
          String(label),
          String(api_key),
          String(ai_key_hint(api_key)),
          String("active"),
          Int(priority),
          String(now),
          String(now),
        ],
      )
  }
  match insert_result {
    Ok(_) =>
      match self.get_admin_ai_key(id) {
        Some(key) => Ok(key)
        None => Err("The AI key was saved but could not be loaded.")
      }
    Err(message) => Err(message)
  }
}

///|
async fn Store::get_admin_ai_key(
  self : Store,
  id : String,
) -> @sdk.AdminAiKeySummary? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  id,
        #|  provider,
        #|  label,
        #|  COALESCE(key_hint, '') AS key_hint,
        #|  status,
        #|  priority,
        #|  COALESCE(last_used_at, '') AS last_used_at,
        #|  COALESCE(last_error, '') AS last_error,
        #|  created_at,
        #|  updated_at
        #|FROM ai_keys
        #|WHERE id = ?;
      ),
      params=[String(id)],
    ) {
    Some(row) => Some(admin_ai_key_from_row(row))
    None => None
  }
}

///|
async fn Store::update_admin_ai_key(
  self : Store,
  id : String,
  label_input : String,
  api_key_input : String,
  status_input : String,
  priority : Int,
) -> Result[@sdk.AdminAiKeySummary, String] noraise {
  let existing = match self.get_admin_ai_key(id) {
    Some(key) => key
    None => return Err("AI key not found.")
  }
  let label = if label_input.trim() == "" {
    existing.label
  } else {
    label_input.trim().to_owned()
  }
  let api_key = api_key_input.trim().to_owned()
  let status = match normalize_ai_key_status(status_input) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let update_result = if api_key == "" {
    self.exec_or_error(
      (
        #|UPDATE ai_keys
        #|SET label = ?,
        #|    status = ?,
        #|    priority = ?,
        #|    updated_at = ?
        #|WHERE id = ?;
      ),
      "update AI key",
      params=[
        String(label),
        String(status),
        Int(priority),
        String(now_string()),
        String(id),
      ],
    )
  } else {
    self.exec_or_error(
      (
        #|UPDATE ai_keys
        #|SET label = ?,
        #|    key_secret = ?,
        #|    key_hint = ?,
        #|    status = ?,
        #|    priority = ?,
        #|    last_error = NULL,
        #|    updated_at = ?
        #|WHERE id = ?;
      ),
      "update AI key",
      params=[
        String(label),
        String(api_key),
        String(ai_key_hint(api_key)),
        String(status),
        Int(priority),
        String(now_string()),
        String(id),
      ],
    )
  }
  match update_result {
    Ok(_) =>
      match self.get_admin_ai_key(id) {
        Some(key) => Ok(key)
        None => Err("The AI key was updated but could not be loaded.")
      }
    Err(message) => Err(message)
  }
}

///|
async fn Store::delete_admin_ai_key(
  self : Store,
  id : String,
) -> Result[Unit, String] noraise {
  if self.get_admin_ai_key(id) is None {
    return Err("AI key not found.")
  }
  self.exec_or_error("DELETE FROM ai_keys WHERE id = ?;", "delete AI key", params=[
    String(id),
  ])
}

///|
async fn Store::list_recent_ai_key_usages(
  self : Store,
  limit : Int,
) -> Array[@sdk.AdminAiKeyUsageSummary] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  key_id,
      #|  run_id,
      #|  project_id,
      #|  user_id,
      #|  model,
      #|  state,
      #|  COALESCE(error_code, '') AS error_code,
      #|  started_at,
      #|  COALESCE(finished_at, '') AS finished_at
      #|FROM ai_key_usages
      #|ORDER BY started_at DESC
      #|LIMIT ?;
    ),
    params=[Int(limit)],
  )
  let items : Array[@sdk.AdminAiKeyUsageSummary] = []
  for row in rows {
    items.push(admin_ai_key_usage_from_row(row))
  }
  items
}

///|
async fn Store::finish_ai_key_usage(
  self : Store,
  run_id : String,
  state : String,
  error_code : String?,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      (
        #|UPDATE ai_key_usages
        #|SET state = ?,
        #|    error_code = ?,
        #|    finished_at = ?
        #|WHERE run_id = ? AND finished_at IS NULL;
      ),
      "finish AI key usage",
      params=[
        String(state),
        nullable_text_param(error_code),
        String(now_string()),
        String(run_id),
      ],
    ),
  )
}

///|
async fn Store::lease_ai_runtime_settings_for_project(
  self : Store,
  project_id : String,
  run_id : String,
) -> Result[AiRuntimeSettings, String] noraise {
  let project = match
    self.query_one(
      (
        #|SELECT
        #|  owner_user_id,
        #|  COALESCE(runtime_id, 'agent-runtime-001') AS runtime_id,
        #|  COALESCE(runtime_name, 'Agent001') AS runtime_name,
        #|  COALESCE(runtime_spec_json, '') AS runtime_spec_json,
        #|  COALESCE(agent_session_id, '') AS agent_session_id,
        #|  COALESCE(runtime_session_id, '') AS runtime_session_id,
        #|  COALESCE(agent_cli, '') AS agent_cli,
        #|  COALESCE(ai_model, '') AS ai_model
        #|FROM projects
        #|WHERE id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => row
    None => return Err("The project owner could not be loaded for this run.")
  }
  let fallback_agent_cli = match
    normalize_agent_cli(row_text(project, "agent_cli")) {
    Ok(agent_cli) => agent_cli
    Err(_) => default_agent_cli()
  }
  let fallback_model = {
    let project_model = row_text(project, "ai_model").trim().to_owned()
    if project_model == "" {
      self.get_admin_ai_config().default_model
    } else {
      project_model
    }
  }
  let runtime_spec = match
    runtime_spec_from_json(row_text(project, "runtime_spec_json")) {
    Ok(spec) => spec
    Err(_) => default_runtime_spec(fallback_agent_cli, fallback_model)
  }
  let row = match
    self.query_one(
      (
        #|SELECT
        #|  id,
        #|  COALESCE(key_secret, '') AS key_secret
        #|FROM ai_keys
        #|WHERE provider = ? AND status = ?
        #|  AND COALESCE(key_secret, '') <> ''
        #|ORDER BY priority DESC, COALESCE(last_used_at, '') ASC, created_at ASC
        #|LIMIT 1;
      ),
      params=[String("openrouter"), String("active")],
    ) {
    Some(row) => row
    None => return Err("MoonCraft's app builder is temporarily unavailable.")
  }
  let selected_model = runtime_spec.model
  let key_id = row_text(row, "id")
  let api_key = row_text(row, "key_secret").trim().to_owned()
  if api_key == "" {
    ignore(self.mark_ai_key_error(key_id, "Stored OpenRouter key is missing."))
    return Err("MoonCraft's app builder is temporarily unavailable.")
  }
  let usage_id = next_id("ai-usage")
  let now = now_string()
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO ai_key_usages (
        #|  id,
        #|  key_id,
        #|  run_id,
        #|  project_id,
        #|  user_id,
        #|  model,
        #|  state,
        #|  started_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
      ),
      "record AI key usage",
      params=[
        String(usage_id),
        String(key_id),
        String(run_id),
        String(project_id),
        String(row_text(project, "owner_user_id")),
        String(selected_model),
        String("started"),
        String(now),
      ],
    ),
  )
  ignore(
    self.exec_or_error(
      (
        #|UPDATE ai_keys
        #|SET last_used_at = ?,
        #|    last_error = NULL,
        #|    updated_at = ?
        #|WHERE id = ?;
      ),
      "mark AI key usage",
      params=[String(now), String(now), String(key_id)],
    ),
  )
  Ok({
    runtime_id: row_text(project, "runtime_id"),
    runtime_name: row_text(project, "runtime_name"),
    runtime_spec,
    agent_session_id: row_text(project, "agent_session_id"),
    runtime_session_id: empty_to_none(row_text(project, "runtime_session_id")),
    provider: "openrouter",
    api_key,
  })
}

///|
async fn Store::mark_ai_key_error(
  self : Store,
  key_id : String,
  message : String,
) -> Result[Unit, String] noraise {
  self.exec_or_error(
    (
      #|UPDATE ai_keys
      #|SET status = ?,
      #|    last_error = ?,
      #|    updated_at = ?
      #|WHERE id = ?;
    ),
    "mark AI key error",
    params=[
      String("error"),
      String(message),
      String(now_string()),
      String(key_id),
    ],
  )
}
