///|
pub fn runtime_manifest_protocol_version() -> Int {
  2
}

///|
pub fn runtime_manifest_forbidden_v1_fields() -> Array[String] {
  ["provider", "send", "secrets", "container_home", "container_user"]
}

///|
pub fn runtime_manifest_allowed_fields() -> Array[String] {
  ["protocol_version", "image", "agent", "model", "auth"]
}

///|
pub fn runtime_manifest_supported_agents() -> Array[String] {
  ["codex", "claude"]
}

///|
pub fn runtime_manifest_supported_auth_kinds() -> Array[String] {
  ["openrouter_api_key", "codex_auth_json", "claude_auth_json"]
}

///|
pub fn runtime_spec_to_json(spec : RuntimeSpec) -> String {
  spec.to_json().stringify()
}

///|
pub fn default_runtime_manifest_json() -> String {
  (
    #|{
    #|  "protocol_version": 2,
    #|  "image": "docker.io/<org>/<image>:<version>",
    #|  "agent": "codex",
    #|  "model": "openai/gpt-5.4-mini",
    #|  "auth": {
    #|    "kind": "openrouter_api_key",
    #|    "secret": {
    #|      "source": "mooncraft_ai_api_key",
    #|      "target": {
    #|        "type": "env",
    #|        "name": "MOONCRAFT_AI_API_KEY"
    #|      }
    #|    }
    #|  }
    #|}
  )
}

///|
pub fn validate_runtime_secret_file_path(
  path : String,
) -> Result[String, String] {
  let trimmed = path.trim().to_owned()
  if trimmed == "" {
    return Err("Runtime auth target path is required.")
  }
  if trimmed.has_prefix("/") {
    return Err("Runtime auth target path must be relative to /home/mooncraft.")
  }
  if trimmed.contains("\\") {
    return Err("Runtime auth target path must use forward slashes.")
  }
  for part in trimmed.split("/").to_array() {
    let segment = part.to_owned()
    if segment == "" || segment == "." || segment == ".." {
      return Err(
        "Runtime auth target path must not contain empty, '.', or '..' path segments.",
      )
    }
  }
  Ok(trimmed)
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
fn runtime_spec_forbidden_v1_fields(
  fields : Map[String, Json],
) -> Result[Unit, String] {
  for name in runtime_manifest_forbidden_v1_fields() {
    if fields.contains(name) {
      return Err("Runtime Protocol v2 does not support '\{name}'.")
    }
  }
  Ok(())
}

///|
fn runtime_spec_allowed_fields(
  fields : Map[String, Json],
) -> Result[Unit, String] {
  let allowed = runtime_manifest_allowed_fields()
  for key in fields.keys() {
    if !allowed.any(fn(name) { name == key }) {
      return Err("Runtime field is not supported: \{key}")
    }
  }
  Ok(())
}

///|
pub fn normalize_runtime_auth_target(
  target : RuntimeAuthTarget,
) -> Result[RuntimeAuthTarget, String] {
  let kind = target.kind.trim().to_owned()
  match kind {
    "env" => {
      let name = match target.name {
        Some(value) if value.trim() != "" => value.trim().to_owned()
        _ => return Err("Runtime auth env target name is required.")
      }
      match target.path {
        Some(value) if value.trim() != "" =>
          return Err("Runtime auth env target must not include path.")
        _ => Ok({ kind, name: Some(name), path: None })
      }
    }
    "file" => {
      let file_path = match target.path {
        Some(value) =>
          match validate_runtime_secret_file_path(value) {
            Ok(path) => path
            Err(message) => return Err(message)
          }
        None => return Err("Runtime auth file target path is required.")
      }
      match target.name {
        Some(value) if value.trim() != "" =>
          return Err("Runtime auth file target must not include name.")
        _ => Ok({ kind, name: None, path: Some(file_path) })
      }
    }
    _ => Err("Runtime auth target type must be env or file.")
  }
}

///|
pub fn normalize_runtime_auth(
  agent : String,
  auth : RuntimeAuth,
) -> Result[RuntimeAuth, String] {
  let kind = auth.kind.trim().to_owned()
  if !runtime_manifest_supported_auth_kinds().any(fn(name) { name == kind }) {
    return Err(
      "Runtime auth kind must be openrouter_api_key, codex_auth_json, or claude_auth_json.",
    )
  }
  if kind == "codex_auth_json" && agent != "codex" {
    return Err("Runtime auth codex_auth_json requires agent codex.")
  }
  if kind == "claude_auth_json" && agent != "claude" {
    return Err("Runtime auth claude_auth_json requires agent claude.")
  }
  let source = auth.secret.source.trim().to_owned()
  if source == "" {
    return Err("Runtime auth secret source is required.")
  }
  let target = match normalize_runtime_auth_target(auth.secret.target) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if kind == "openrouter_api_key" && target.kind != "env" {
    return Err("Runtime auth openrouter_api_key must target env.")
  }
  if (kind == "codex_auth_json" || kind == "claude_auth_json") &&
    target.kind != "file" {
    return Err("Runtime account-file auth must target file.")
  }
  Ok({ kind, secret: { source, target } })
}

///|
pub fn normalize_runtime_spec(
  spec : RuntimeSpec,
) -> Result[RuntimeSpec, String] {
  let protocol_version = spec.protocol_version
  if protocol_version != runtime_manifest_protocol_version() {
    return Err("Runtime protocol_version must be 2.")
  }
  let image = spec.image.trim().to_owned()
  if image == "" {
    return Err("Runtime image is required.")
  }
  let agent = spec.agent.trim().to_owned()
  if !runtime_manifest_supported_agents().any(fn(name) { name == agent }) {
    return Err("Runtime agent must be codex or claude.")
  }
  let model = spec.model.trim().to_owned()
  if model == "" {
    return Err("Runtime model is required.")
  }
  let auth = match normalize_runtime_auth(agent, spec.auth) {
    Ok(auth) => auth
    Err(message) => return Err(message)
  }
  Ok({ protocol_version, image, agent, model, auth })
}

///|
pub fn runtime_spec_from_json(text : String) -> Result[RuntimeSpec, String] {
  let parsed = @json.parse(text) catch {
    _ => return Err("Runtime spec must be valid JSON.")
  }
  match parsed {
    Object(fields) => {
      match runtime_spec_int_field(fields, "protocol_version") {
        Ok(value) =>
          if value != runtime_manifest_protocol_version() {
            return Err("Runtime protocol_version must be 2.")
          }
        Err(message) => return Err(message)
      }
      match runtime_spec_forbidden_v1_fields(fields) {
        Ok(_) => ()
        Err(message) => return Err(message)
      }
      match runtime_spec_allowed_fields(fields) {
        Ok(_) => ()
        Err(message) => return Err(message)
      }
      let spec : RuntimeSpec = @json.from_json(parsed) catch {
        err => return Err("Runtime spec does not match Protocol v2: \{err}")
      }
      normalize_runtime_spec(spec)
    }
    _ => Err("Runtime spec must be a JSON object.")
  }
}
