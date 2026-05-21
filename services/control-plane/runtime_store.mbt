///|
fn default_runtime_id() -> String {
  "agent-runtime-001"
}

///|
fn runtime_spec_to_json(spec : @sdk.RuntimeSpec) -> String {
  spec.to_json().stringify()
}

///|
fn default_runtime_spec(agent : String, model : String) -> @sdk.RuntimeSpec {
  {
    image: default_agent_runtime_image,
    agent,
    model,
    send: ["mooncraft-runtime-send"],
  }
}

///|
fn runtime_spec_from_json(text : String) -> Result[@sdk.RuntimeSpec, String] {
  let parsed = @json.parse(text) catch {
    _ => return Err("Runtime spec must be valid JSON.")
  }
  let spec : @sdk.RuntimeSpec = @json.from_json(parsed) catch {
    _ =>
      return Err(
        "Runtime spec must contain image, agent, model, and send fields.",
      )
  }
  let image = spec.image.trim().to_owned()
  if image == "" {
    return Err("Runtime image is required.")
  }
  let agent = match normalize_agent_cli(spec.agent) {
    Ok(agent) => agent
    Err(message) => return Err(message)
  }
  let model = normalize_openrouter_model(spec.model)
  if model == "" {
    return Err("Runtime model is required.")
  }
  let send : Array[String] = []
  for part in spec.send {
    let value = part.trim().to_owned()
    if value != "" {
      send.push(value)
    }
  }
  if send.length() == 0 {
    return Err("Runtime send command must contain at least one argv item.")
  }
  Ok({ image, agent, model, send })
}

///|
fn runtime_detail_from_row(row : Map[String, @db.Param]) -> @sdk.RuntimeDetail {
  let spec_json = row_text(row, "spec_json")
  let spec = match runtime_spec_from_json(spec_json) {
    Ok(spec) => spec
    Err(_) =>
      default_runtime_spec(row_text(row, "agent"), row_text(row, "model"))
  }
  {
    id: row_text(row, "id"),
    name: row_text(row, "name"),
    spec,
    spec_json,
    enabled: row_bool(row, "enabled"),
    is_default: row_bool(row, "is_default"),
    created_at: row_text(row, "created_at"),
    updated_at: row_text(row, "updated_at"),
  }
}

///|
fn runtime_summary_from_detail(
  runtime : @sdk.RuntimeDetail,
) -> @sdk.RuntimeSummary {
  {
    id: runtime.id,
    name: runtime.name,
    agent: runtime.spec.agent,
    model: runtime.spec.model,
    enabled: runtime.enabled,
    is_default: runtime.is_default,
    created_at: runtime.created_at,
    updated_at: runtime.updated_at,
  }
}

///|
fn runtime_snapshot_json(runtime : @sdk.RuntimeDetail) -> String {
  runtime_spec_to_json(runtime.spec)
}

///|
async fn Store::ensure_agent_runtime_tables(
  self : Store,
) -> Result[Unit, String] noraise {
  match
    self.exec_or_error(
      (
        #|CREATE TABLE IF NOT EXISTS agent_runtimes (
        #|  id TEXT PRIMARY KEY,
        #|  name TEXT NOT NULL,
        #|  spec_json TEXT NOT NULL,
        #|  agent TEXT NOT NULL,
        #|  model TEXT NOT NULL,
        #|  enabled INTEGER NOT NULL DEFAULT 1,
        #|  is_default INTEGER NOT NULL DEFAULT 0,
        #|  created_at TEXT NOT NULL,
        #|  updated_at TEXT NOT NULL
        #|);
      ),
      "create agent_runtimes table",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  let now = now_string()
  let builtins : Array[(String, String, @sdk.RuntimeSpec, Bool)] = [
    (
      "agent-runtime-001",
      "Agent001",
      default_runtime_spec("codex", default_openrouter_model()),
      true,
    ),
    (
      "agent-runtime-002",
      "Agent002",
      default_runtime_spec("claude_code", "anthropic/claude-sonnet-4.5"),
      false,
    ),
    (
      "agent-runtime-003",
      "Agent003",
      default_runtime_spec("kimi_code", "moonshotai/kimi-k2.6"),
      false,
    ),
  ]
  for item in builtins {
    let (id, name, spec, is_default) = item
    match
      self.exec_or_error(
        (
          #|INSERT INTO agent_runtimes (
          #|  id,
          #|  name,
          #|  spec_json,
          #|  agent,
          #|  model,
          #|  enabled,
          #|  is_default,
          #|  created_at,
          #|  updated_at
          #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          #|ON CONFLICT(id) DO NOTHING;
        ),
        "seed agent runtime",
        params=[
          String(id),
          String(name),
          String(runtime_spec_to_json(spec)),
          String(spec.agent),
          String(spec.model),
          Int(1),
          Int(if is_default { 1 } else { 0 }),
          String(now),
          String(now),
        ],
      ) {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
  }
  Ok(())
}

///|
async fn Store::list_admin_runtimes(
  self : Store,
) -> Array[@sdk.RuntimeDetail] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  name,
      #|  spec_json,
      #|  agent,
      #|  model,
      #|  enabled,
      #|  is_default,
      #|  created_at,
      #|  updated_at
      #|FROM agent_runtimes
      #|ORDER BY id ASC;
    ),
  )
  let items : Array[@sdk.RuntimeDetail] = []
  for row in rows {
    items.push(runtime_detail_from_row(row))
  }
  items
}

///|
async fn Store::list_enabled_runtimes(
  self : Store,
) -> Array[@sdk.RuntimeSummary] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  name,
      #|  spec_json,
      #|  agent,
      #|  model,
      #|  enabled,
      #|  is_default,
      #|  created_at,
      #|  updated_at
      #|FROM agent_runtimes
      #|WHERE enabled = 1
      #|ORDER BY is_default DESC, id ASC;
    ),
  )
  let items : Array[@sdk.RuntimeSummary] = []
  for row in rows {
    items.push(runtime_summary_from_detail(runtime_detail_from_row(row)))
  }
  items
}

///|
async fn Store::get_runtime_detail(
  self : Store,
  runtime_id : String,
) -> @sdk.RuntimeDetail? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  id,
        #|  name,
        #|  spec_json,
        #|  agent,
        #|  model,
        #|  enabled,
        #|  is_default,
        #|  created_at,
        #|  updated_at
        #|FROM agent_runtimes
        #|WHERE id = ?;
      ),
      params=[String(runtime_id)],
    ) {
    Some(row) => Some(runtime_detail_from_row(row))
    None => None
  }
}

///|
async fn Store::get_default_runtime_id(self : Store) -> String noraise {
  match
    self.query_one(
      (
        #|SELECT id
        #|FROM agent_runtimes
        #|WHERE enabled = 1
        #|ORDER BY is_default DESC, id ASC
        #|LIMIT 1;
      ),
    ) {
    Some(row) => row_text(row, "id")
    None => default_runtime_id()
  }
}

///|
async fn Store::save_admin_runtime(
  self : Store,
  id : String,
  name_input : String,
  spec_json_input : String,
  enabled : Bool,
  is_default : Bool,
) -> Result[@sdk.RuntimeDetail, String] noraise {
  let name = name_input.trim().to_owned()
  if name == "" {
    return Err("Runtime name is required.")
  }
  if id.trim() == "" || id.length() > 80 {
    return Err("Runtime id is required and must be 80 characters or fewer.")
  }
  let spec = match runtime_spec_from_json(spec_json_input) {
    Ok(spec) => spec
    Err(message) => return Err(message)
  }
  let normalized_spec_json = runtime_spec_to_json(spec)
  let now = now_string()
  if is_default {
    ignore(
      self.exec_or_error(
        "UPDATE agent_runtimes SET is_default = 0;", "clear default agent runtime",
      ),
    )
  }
  match
    self.exec_or_error(
      (
        #|INSERT INTO agent_runtimes (
        #|  id,
        #|  name,
        #|  spec_json,
        #|  agent,
        #|  model,
        #|  enabled,
        #|  is_default,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        #|ON CONFLICT(id) DO UPDATE SET
        #|  name = excluded.name,
        #|  spec_json = excluded.spec_json,
        #|  agent = excluded.agent,
        #|  model = excluded.model,
        #|  enabled = excluded.enabled,
        #|  is_default = excluded.is_default,
        #|  updated_at = excluded.updated_at;
      ),
      "save agent runtime",
      params=[
        String(id),
        String(name),
        String(normalized_spec_json),
        String(spec.agent),
        String(spec.model),
        Int(if enabled { 1 } else { 0 }),
        Int(if is_default { 1 } else { 0 }),
        String(now),
        String(now),
      ],
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match self.get_runtime_detail(id) {
    Some(runtime) => Ok(runtime)
    None => Err("Runtime could not be loaded after saving.")
  }
}
