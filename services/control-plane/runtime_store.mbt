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
fn runtime_spec_optional_string_field(
  fields : Map[String, Json],
  name : String,
) -> String? {
  match fields.get(name) {
    Some(String(value)) if value.trim() != "" => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn normalize_runtime_container_user(value : String?) -> Result[String?, String] {
  match value {
    Some(user) => {
      let trimmed = user.trim().to_owned()
      if trimmed == "" {
        Ok(None)
      } else if trimmed.contains(" ") ||
        trimmed.contains("\t") ||
        trimmed.has_prefix("-") {
        Err("Runtime container_user must be a Docker user name or uid.")
      } else {
        Ok(Some(trimmed))
      }
    }
    None => Ok(None)
  }
}

///|
fn validate_runtime_secret_file_path(path : String) -> Result[String, String] {
  let trimmed = path.trim().to_owned()
  if trimmed == "" {
    return Err("Runtime secret file is required.")
  }
  if trimmed.has_prefix("/") {
    return Err("Runtime secret file must be relative to container_home.")
  }
  if trimmed.contains("\\") {
    return Err("Runtime secret file must use forward slashes.")
  }
  for part in trimmed.split("/").to_array() {
    let segment = part.to_owned()
    if segment == "" || segment == "." || segment == ".." {
      return Err(
        "Runtime secret file must not contain empty, '.', or '..' path segments.",
      )
    }
  }
  Ok(trimmed)
}

///|
fn normalize_runtime_secret_binding(
  source_input : String,
  env_input : String?,
  file_input : String?,
) -> Result[@sdk.RuntimeSecretBinding, String] {
  let source = source_input.trim().to_owned()
  if source == "" {
    return Err("Runtime secret source is required.")
  }
  let env = match env_input {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ => None
  }
  let file = match file_input {
    Some(value) =>
      match validate_runtime_secret_file_path(value) {
        Ok(path) => Some(path)
        Err(message) => return Err(message)
      }
    None => None
  }
  match (env, file) {
    (Some(_), Some(_)) =>
      Err("Runtime secret binding must use either env or file, not both.")
    (None, None) => Err("Runtime secret binding must declare env or file.")
    _ => Ok({ source, env, file })
  }
}

///|
fn runtime_spec_int_field(
  fields : Map[String, Json],
  name : String,
) -> Result[Int, String] {
  match fields.get(name) {
    Some(Number(_, ..) as value) =>
      Ok(
        @string.parse_int(value.stringify()) catch {
          _ => return Err("Runtime \{name} must be an integer.")
        },
      )
    Some(String(value)) =>
      Ok(
        @string.parse_int(value) catch {
          _ => return Err("Runtime \{name} must be an integer.")
        },
      )
    _ => Err("Runtime \{name} is required.")
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
fn runtime_spec_secret_bindings_field(
  fields : Map[String, Json],
) -> Result[Array[@sdk.RuntimeSecretBinding], String] {
  match fields.get("secrets") {
    None | Some(Null) => Err("Runtime secrets must be an array.")
    Some(Array(items)) => {
      let secrets : Array[@sdk.RuntimeSecretBinding] = []
      for item in items {
        match item {
          Object(fields) => {
            let source = runtime_spec_string_field(fields, "source")
            let env = runtime_spec_optional_string_field(fields, "env")
            let file = runtime_spec_optional_string_field(fields, "file")
            match normalize_runtime_secret_binding(source, env, file) {
              Ok(secret) => secrets.push(secret)
              Err(message) => return Err(message)
            }
          }
          _ => return Err("Runtime secrets must be JSON objects.")
        }
      }
      Ok(secrets)
    }
    _ => Err("Runtime secrets must be an array.")
  }
}

///|
fn normalize_runtime_spec(
  spec : @sdk.RuntimeSpec,
) -> Result[@sdk.RuntimeSpec, String] {
  let protocol_version = spec.protocol_version
  if protocol_version != 1 {
    return Err("Runtime protocol_version must be 1.")
  }
  let image = spec.image.trim().to_owned()
  if image == "" {
    return Err("Runtime image is required.")
  }
  let agent = spec.agent.trim().to_owned()
  if agent == "" {
    return Err("Runtime agent is required.")
  }
  let model = spec.model.trim().to_owned()
  if model == "" {
    return Err("Runtime model is required.")
  }
  let provider = spec.provider.trim().to_owned()
  if provider == "" {
    return Err("Runtime provider is required.")
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
  let container_home = spec.container_home.trim().to_owned()
  if container_home == "" {
    return Err("Runtime container_home is required.")
  }
  let container_user = match
    normalize_runtime_container_user(spec.container_user) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let secrets : Array[@sdk.RuntimeSecretBinding] = []
  for secret in spec.secrets {
    match
      normalize_runtime_secret_binding(secret.source, secret.env, secret.file) {
      Ok(secret) => secrets.push(secret)
      Err(message) => return Err(message)
    }
  }
  Ok({
    protocol_version,
    image,
    agent,
    model,
    provider,
    send,
    container_home,
    container_user,
    secrets,
  })
}

///|
fn runtime_spec_from_json(text : String) -> Result[@sdk.RuntimeSpec, String] {
  let parsed = @json.parse(text) catch {
    _ => return Err("Runtime spec must be valid JSON.")
  }
  match parsed {
    Object(fields) =>
      normalize_runtime_spec({
        protocol_version: match
          runtime_spec_int_field(fields, "protocol_version") {
          Ok(value) => value
          Err(message) => return Err(message)
        },
        image: runtime_spec_string_field(fields, "image"),
        agent: runtime_spec_string_field(fields, "agent"),
        model: runtime_spec_string_field(fields, "model"),
        provider: runtime_spec_string_field(fields, "provider"),
        send: match runtime_spec_send_field(fields) {
          Ok(send) => send
          Err(message) => return Err(message)
        },
        container_home: runtime_spec_string_field(fields, "container_home"),
        container_user: runtime_spec_optional_string_field(
          fields, "container_user",
        ),
        secrets: match runtime_spec_secret_bindings_field(fields) {
          Ok(secrets) => secrets
          Err(message) => return Err(message)
        },
      })
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
fn runtime_detail_from_row(
  row : Map[String, @db.Param],
) -> Result[@sdk.RuntimeDetail, String] {
  let spec_json = row_text(row, "spec_json")
  let spec = match runtime_spec_from_json(spec_json) {
    Ok(spec) => spec
    Err(message) =>
      return Err("Stored Runtime \{row_text(row, "id")} is invalid: \{message}")
  }
  Ok({
    id: row_text(row, "id"),
    name: row_text(row, "name"),
    spec,
    spec_json: runtime_spec_to_json(spec),
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
    Ok(Some(runtime)) => Ok(runtime)
    Ok(None) => Err("Runtime could not be loaded after saving.")
    Err(message) => Err(message)
  }
}
