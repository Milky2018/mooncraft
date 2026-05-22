///|
fn default_runtime_id() -> String {
  "agent-runtime-001"
}

///|
fn runtime_spec_to_json(spec : @sdk.RuntimeSpec) -> String {
  spec.to_json().stringify()
}

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
fn legacy_builtin_runtime_name(index : Int) -> String {
  "Agent" + builtin_runtime_suffix(index)
}

///|
fn legacy_container_home(agent : String) -> String {
  if agent == "claude_code" {
    "/home/mooncraft"
  } else {
    "/root"
  }
}

///|
fn config_agent_runtime_image() -> String {
  safe_read_string_or("config/agent_runtime_image.txt", "").trim().to_owned()
}

///|
fn runtime_spec_string_field(
  fields : Map[String, Json],
  name : String,
) -> String {
  match fields.get(name) {
    Some(String(value)) => value.trim().to_owned()
    _ => ""
  }
}

///|
fn runtime_spec_send_field(
  fields : Map[String, Json],
) -> Result[Array[String], String] {
  match fields.get("send") {
    Some(Array(items)) => {
      let send : Array[String] = []
      for item in items {
        match item {
          String(value) if value.trim() != "" =>
            send.push(value.trim().to_owned())
          String(_) => ()
          _ =>
            return Err(
              "Runtime send command must contain only string argv items.",
            )
        }
      }
      Ok(send)
    }
    _ => Err("Runtime send command must be an argv array.")
  }
}

///|
fn normalize_runtime_spec(
  spec : @sdk.RuntimeSpec,
) -> Result[@sdk.RuntimeSpec, String] {
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
  let container_home = {
    let value = spec.container_home.trim().to_owned()
    if value == "" {
      legacy_container_home(agent)
    } else {
      value
    }
  }
  Ok({ image, agent, model, send, container_home })
}

///|
fn legacy_runtime_spec(
  agent_input : String,
  model_input : String,
) -> @sdk.RuntimeSpec {
  let agent = match normalize_agent_cli(agent_input) {
    Ok(agent) => agent
    Err(_) => default_agent_cli()
  }
  let model = normalize_openrouter_model(model_input)
  {
    image: config_agent_runtime_image(),
    agent,
    model,
    send: ["mooncraft-runtime-send"],
    container_home: legacy_container_home(agent),
  }
}

///|
fn runtime_spec_from_json(text : String) -> Result[@sdk.RuntimeSpec, String] {
  let parsed = @json.parse(text) catch {
    _ => return Err("Runtime spec must be valid JSON.")
  }
  match parsed {
    Object(fields) => {
      let agent_input = runtime_spec_string_field(fields, "agent")
      let agent = match normalize_agent_cli(agent_input) {
        Ok(agent) => agent
        Err(message) => return Err(message)
      }
      normalize_runtime_spec({
        image: runtime_spec_string_field(fields, "image"),
        agent,
        model: runtime_spec_string_field(fields, "model"),
        send: match runtime_spec_send_field(fields) {
          Ok(send) => send
          Err(message) => return Err(message)
        },
        container_home: runtime_spec_string_field(fields, "container_home"),
      })
    }
    _ => Err("Runtime spec must be a JSON object.")
  }
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
      let spec = match normalize_runtime_spec(definition.spec) {
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
fn runtime_detail_from_row(row : Map[String, @db.Param]) -> @sdk.RuntimeDetail {
  let spec_json = row_text(row, "spec_json")
  let spec = match runtime_spec_from_json(spec_json) {
    Ok(spec) => spec
    Err(_) =>
      legacy_runtime_spec(row_text(row, "agent"), row_text(row, "model"))
  }
  {
    id: row_text(row, "id"),
    name: row_text(row, "name"),
    spec,
    spec_json: runtime_spec_to_json(spec),
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
  let builtins = match builtin_runtime_definitions() {
    Ok(builtins) => builtins
    Err(message) => return Err(message)
  }
  let now = now_string()
  for index, item in builtins {
    let id = builtin_runtime_id(index)
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
          String(item.name),
          String(runtime_spec_to_json(item.spec)),
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
    match
      self.exec_or_error(
        (
          #|UPDATE agent_runtimes
          #|SET name = ?,
          #|    updated_at = ?
          #|WHERE id = ?
          #|  AND name = ?;
        ),
        "rename seeded agent runtime",
        params=[
          String(item.name),
          String(now),
          String(id),
          String(legacy_builtin_runtime_name(index)),
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
