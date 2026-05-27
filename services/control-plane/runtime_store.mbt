///|
fn runtime_detail_from_row(
  row : Map[String, @db.Param],
) -> Result[@sdk.RuntimeDetail, String] {
  let spec_json = row_text(row, "spec_json")
  let spec = match @sdk.runtime_spec_from_json(spec_json) {
    Ok(spec) => spec
    Err(message) =>
      return Err("Stored Runtime \{row_text(row, "id")} is invalid: \{message}")
  }
  Ok({
    id: row_text(row, "id"),
    name: row_text(row, "name"),
    spec,
    spec_json: @sdk.runtime_spec_to_json(spec),
    enabled: row_bool(row, "enabled"),
    is_default: row_bool(row, "is_default"),
    created_at: row_text(row, "created_at"),
    updated_at: row_text(row, "updated_at"),
  })
}

///|
fn runtime_summary_from_detail(
  runtime : @sdk.RuntimeDetail,
) -> @sdk.RuntimeSummary {
  {
    id: runtime.id,
    name: runtime.name,
    image: runtime.spec.image,
    enabled: runtime.enabled,
    is_default: runtime.is_default,
    created_at: runtime.created_at,
    updated_at: runtime.updated_at,
  }
}

///|
fn runtime_snapshot_json(runtime : @sdk.RuntimeDetail) -> String {
  @sdk.runtime_spec_to_json(runtime.spec)
}

///|
async fn Store::delete_invalid_agent_runtime_rows(
  self : Store,
) -> Result[Unit, String] noraise {
  let rows = self.query_rows(
    (
      #|SELECT id, spec_json
      #|FROM agent_runtimes;
    ),
  )
  for row in rows {
    let id = row_text(row, "id")
    if @sdk.runtime_spec_from_json(row_text(row, "spec_json")) is Err(_) {
      if self.exec_or_error(
          "DELETE FROM agent_runtimes WHERE id = ?;",
          "delete invalid agent runtime",
          params=[String(id)],
        )
        is Err(message) {
        return Err(message)
      }
    }
  }
  Ok(())
}

///|
async fn Store::delete_retired_seed_runtime_rows(
  self : Store,
) -> Result[Unit, String] noraise {
  let rows = self.query_rows(
    (
      #|SELECT id
      #|FROM agent_runtimes
      #|WHERE id LIKE 'agent-runtime-___';
    ),
  )
  for row in rows {
    let id = row_text(row, "id")
    match
      self.exec_or_error(
        "DELETE FROM agent_runtimes WHERE id = ?;",
        "remove retired seed agent runtime",
        params=[String(id)],
      ) {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
  }
  Ok(())
}

///|
async fn Store::ensure_agent_runtime_default(
  self : Store,
) -> Result[Unit, String] noraise {
  match
    self.query_one(
      (
        #|SELECT id
        #|FROM agent_runtimes
        #|WHERE enabled = 1 AND is_default = 1
        #|LIMIT 1;
      ),
    ) {
    Some(_) => Ok(())
    None => {
      let row = match
        self.query_one(
          (
            #|SELECT id
            #|FROM agent_runtimes
            #|WHERE enabled = 1
            #|ORDER BY id ASC
            #|LIMIT 1;
          ),
        ) {
        Some(row) => row
        None => return Ok(())
      }
      let id = row_text(row, "id")
      match
        self.exec_or_error(
          (
            #|UPDATE agent_runtimes
            #|SET is_default = CASE WHEN id = ? THEN 1 ELSE 0 END;
          ),
          "repair default agent runtime",
          params=[String(id)],
        ) {
        Ok(_) => Ok(())
        Err(message) => Err(message)
      }
    }
  }
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
  if self.delete_retired_seed_runtime_rows() is Err(message) {
    return Err(message)
  }
  if self.delete_invalid_agent_runtime_rows() is Err(message) {
    return Err(message)
  }
  if self.ensure_agent_runtime_default() is Err(message) {
    return Err(message)
  }
  Ok(())
}

///|
async fn Store::list_admin_runtimes(
  self : Store,
) -> Result[Array[@sdk.RuntimeDetail], String] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  name,
      #|  spec_json,
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
    match runtime_detail_from_row(row) {
      Ok(runtime) => items.push(runtime)
      Err(message) => return Err(message)
    }
  }
  Ok(items)
}

///|
async fn Store::list_enabled_runtimes(
  self : Store,
) -> Result[Array[@sdk.RuntimeSummary], String] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  name,
      #|  spec_json,
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
    let runtime = match runtime_detail_from_row(row) {
      Ok(runtime) => runtime
      Err(message) => return Err(message)
    }
    items.push(runtime_summary_from_detail(runtime))
  }
  Ok(items)
}

///|
async fn Store::get_runtime_detail(
  self : Store,
  runtime_id : String,
) -> Result[@sdk.RuntimeDetail?, String] noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  id,
        #|  name,
        #|  spec_json,
        #|  enabled,
        #|  is_default,
        #|  created_at,
        #|  updated_at
        #|FROM agent_runtimes
        #|WHERE id = ?;
      ),
      params=[String(runtime_id)],
    ) {
    Some(row) =>
      match runtime_detail_from_row(row) {
        Ok(runtime) => Ok(Some(runtime))
        Err(message) => Err(message)
      }
    None => Ok(None)
  }
}

///|
async fn Store::get_default_runtime_id(
  self : Store,
) -> Result[String, String] noraise {
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
    Some(row) => Ok(row_text(row, "id"))
    None => Err("No enabled Runtime is configured.")
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
  let spec = match @sdk.runtime_spec_from_json(spec_json_input) {
    Ok(spec) => spec
    Err(message) => return Err(message)
  }
  let normalized_spec_json = @sdk.runtime_spec_to_json(spec)
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
        #|  enabled,
        #|  is_default,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?)
        #|ON CONFLICT(id) DO UPDATE SET
        #|  name = excluded.name,
        #|  spec_json = excluded.spec_json,
        #|  enabled = excluded.enabled,
        #|  is_default = excluded.is_default,
        #|  updated_at = excluded.updated_at;
      ),
      "save agent runtime",
      params=[
        String(id),
        String(name),
        String(normalized_spec_json),
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
    Ok(Some(runtime)) => Ok(runtime)
    Ok(None) => Err("Runtime could not be loaded after saving.")
    Err(message) => Err(message)
  }
}
