///|
struct BuiltinRuntimeDefinition {
  name : String
  spec : @sdk.RuntimeSpec
  enabled : Bool
  is_default : Bool
} derive(FromJson)

///|
fn builtin_runtime_dir() -> String {
  "runtime/builtin"
}

///|
fn builtin_runtime_suffix(index : Int) -> String {
  let value = index + 1
  if value < 10 {
    "00" + value.to_string()
  } else if value < 100 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn builtin_runtime_id(index : Int) -> String {
  "agent-runtime-" + builtin_runtime_suffix(index)
}

///|
fn builtin_runtime_definitions() -> Result[
  Array[BuiltinRuntimeDefinition],
  String,
] {
  let dir = builtin_runtime_dir()
  let names = @fs.read_dir(dir) catch {
    _ => return Err("Built-in Runtime directory is missing: \{dir}")
  }
  names.sort()
  let builtins : Array[BuiltinRuntimeDefinition] = []
  for name in names {
    if name.has_suffix(".json") {
      let path = dir + "/" + name
      let text = @fs.read_file_to_string(path) catch {
        _ => return Err("Built-in Runtime file could not be read: \{path}")
      }
      let parsed = @json.parse(text) catch {
        _ => return Err("Built-in Runtime file must be valid JSON: \{path}")
      }
      let definition : BuiltinRuntimeDefinition = @json.from_json(parsed) catch {
        _ =>
          return Err(
            "Built-in Runtime file must contain name, spec, enabled, and is_default: \{path}",
          )
      }
      let name_from_file = name
        .strip_suffix(".json")
        .unwrap_or(name[:])
        .to_owned()
      if definition.name.trim() == "" {
        return Err("Built-in Runtime name is required: \{path}")
      }
      if definition.name != name_from_file {
        return Err(
          "Built-in Runtime file name must match its name field: \{path}",
        )
      }
      let spec = match @sdk.normalize_runtime_spec(definition.spec) {
        Ok(spec) => spec
        Err(message) => return Err("\{path}: \{message}")
      }
      builtins.push({ ..definition, spec, })
    }
  }
  if builtins.length() == 0 {
    Err("At least one built-in Runtime JSON file is required.")
  } else {
    let ordered : Array[BuiltinRuntimeDefinition] = []
    for item in builtins {
      if item.is_default {
        ordered.push(item)
      }
    }
    for item in builtins {
      if !item.is_default {
        ordered.push(item)
      }
    }
    Ok(ordered)
  }
}

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
    match @sdk.runtime_spec_from_json(row_text(row, "spec_json")) {
      Ok(_) => ()
      Err(_) =>
        match
          self.exec_or_error(
            "DELETE FROM agent_runtimes WHERE id = ?;",
            "delete invalid agent runtime",
            params=[String(id)],
          ) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
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
        None => return Err("At least one enabled Runtime is required.")
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
  let builtins = match builtin_runtime_definitions() {
    Ok(builtins) => builtins
    Err(message) => return Err(message)
  }
  let now = now_string()
  let builtin_ids : Array[String] = []
  for index, item in builtins {
    let id = builtin_runtime_id(index)
    builtin_ids.push(id)
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
          #|  updated_at = excluded.updated_at;
        ),
        "seed agent runtime",
        params=[
          String(id),
          String(item.name),
          String(@sdk.runtime_spec_to_json(item.spec)),
          String(item.spec.agent),
          String(item.spec.model),
          Int(if item.enabled { 1 } else { 0 }),
          Int(if item.is_default { 1 } else { 0 }),
          String(now),
          String(now),
        ],
      ) {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
  }
  let seeded_id_rows = self.query_rows(
    (
      #|SELECT id
      #|FROM agent_runtimes
      #|WHERE id LIKE 'agent-runtime-___';
    ),
  )
  for row in seeded_id_rows {
    let id = row_text(row, "id")
    if !builtin_ids.any(fn(current) { current == id }) {
      match
        self.exec_or_error(
          "DELETE FROM agent_runtimes WHERE id = ?;",
          "remove retired built-in agent runtime",
          params=[String(id)],
        ) {
        Ok(_) => ignore(())
        Err(message) => return Err(message)
      }
    }
  }
  match self.delete_invalid_agent_runtime_rows() {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  match self.ensure_agent_runtime_default() {
    Ok(_) => ()
    Err(message) => return Err(message)
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
    Ok(Some(runtime)) => Ok(runtime)
    Ok(None) => Err("Runtime could not be loaded after saving.")
    Err(message) => Err(message)
  }
}
