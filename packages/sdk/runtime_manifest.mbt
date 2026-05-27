///|
pub fn runtime_manifest_protocol_version() -> Int {
  3
}

///|
pub fn runtime_manifest_allowed_fields() -> Array[String] {
  ["protocol_version", "image", "env", "secrets"]
}

///|
pub fn runtime_spec_to_json(spec : RuntimeSpec) -> String {
  spec.to_json().stringify()
}

///|
pub fn default_runtime_manifest_json() -> String {
  (
    #|{
    #|  "protocol_version": 3,
    #|  "image": "docker.io/<org>/<image>:<version>",
    #|  "env": {},
    #|  "secrets": []
    #|}
  )
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
fn runtime_env_name_valid_char(code : Int) -> Bool {
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  (code >= 48 && code <= 57) ||
  code == 95
}

///|
fn runtime_env_name_valid_first_char(code : Int) -> Bool {
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95
}

///|
pub fn validate_runtime_env_name(name : String) -> Result[String, String] {
  let trimmed = name.trim().to_owned()
  if trimmed == "" {
    return Err("Runtime env name is required.")
  }
  if trimmed.has_prefix("MOONCRAFT_") {
    return Err("Runtime env name must not use the reserved MOONCRAFT_ prefix.")
  }
  if trimmed.length() == 0 ||
    !runtime_env_name_valid_first_char(trimmed[0].to_int()) {
    return Err(
      "Runtime env name must start with an ASCII letter or underscore.",
    )
  }
  for index in 0..<trimmed.length() {
    if !runtime_env_name_valid_char(trimmed[index].to_int()) {
      return Err(
        "Runtime env name may contain only ASCII letters, digits, and underscores.",
      )
    }
  }
  Ok(trimmed)
}

///|
pub fn validate_runtime_secret_file_path(
  path : String,
) -> Result[String, String] {
  let trimmed = path.trim().to_owned()
  if trimmed == "" {
    return Err("Runtime secret target path is required.")
  }
  if trimmed.has_prefix("/") {
    return Err(
      "Runtime secret target path must be relative to /home/mooncraft.",
    )
  }
  if trimmed.contains("\\") {
    return Err("Runtime secret target path must use forward slashes.")
  }
  for part in trimmed.split("/").to_array() {
    let segment = part.to_owned()
    if segment == "" || segment == "." || segment == ".." {
      return Err(
        "Runtime secret target path must not contain empty, '.', or '..' path segments.",
      )
    }
  }
  Ok(trimmed)
}

///|
pub fn normalize_runtime_secret_target(
  target : RuntimeSecretTarget,
) -> Result[RuntimeSecretTarget, String] {
  let kind = target.kind.trim().to_owned()
  match kind {
    "env" => {
      let name = match target.name {
        Some(value) =>
          match validate_runtime_env_name(value) {
            Ok(name) => name
            Err(message) => return Err(message)
          }
        None => return Err("Runtime secret env target name is required.")
      }
      match target.path {
        Some(value) if value.trim() != "" =>
          return Err("Runtime secret env target must not include path.")
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
        None => return Err("Runtime secret file target path is required.")
      }
      match target.name {
        Some(value) if value.trim() != "" =>
          return Err("Runtime secret file target must not include name.")
        _ => Ok({ kind, name: None, path: Some(file_path) })
      }
    }
    _ => Err("Runtime secret target type must be env or file.")
  }
}

///|
fn normalize_runtime_secrets(
  env : Map[String, String],
  secrets : Array[RuntimeSecret],
) -> Result[Array[RuntimeSecret], String] {
  let normalized : Array[RuntimeSecret] = []
  let secret_env_targets : Map[String, Bool] = {}
  for secret in secrets {
    let source = secret.source.trim().to_owned()
    if source == "" {
      return Err("Runtime secret source is required.")
    }
    let target = match normalize_runtime_secret_target(secret.target) {
      Ok(target) => target
      Err(message) => return Err(message)
    }
    if target.name is Some(name) {
      if env.contains(name) {
        return Err(
          "Runtime env '\{name}' must not duplicate a secret env target.",
        )
      }
      if secret_env_targets.contains(name) {
        return Err("Runtime secret env target is duplicated: \{name}")
      }
      secret_env_targets[name] = true
    }
    normalized.push({ source, target })
  }
  Ok(normalized)
}

///|
fn normalize_runtime_env(
  env : Map[String, String],
) -> Result[Map[String, String], String] {
  let normalized : Map[String, String] = {}
  for key, value in env {
    let name = match validate_runtime_env_name(key) {
      Ok(name) => name
      Err(message) => return Err(message)
    }
    normalized[name] = value
  }
  Ok(normalized)
}

///|
pub fn normalize_runtime_spec(
  spec : RuntimeSpec,
) -> Result[RuntimeSpec, String] {
  let protocol_version = spec.protocol_version
  if protocol_version != runtime_manifest_protocol_version() {
    return Err("Runtime protocol_version must be 3.")
  }
  let image = spec.image.trim().to_owned()
  if image == "" {
    return Err("Runtime image is required.")
  }
  let env = match normalize_runtime_env(spec.env) {
    Ok(env) => env
    Err(message) => return Err(message)
  }
  let secrets = match normalize_runtime_secrets(env, spec.secrets) {
    Ok(secrets) => secrets
    Err(message) => return Err(message)
  }
  Ok({ protocol_version, image, env, secrets })
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
            return Err("Runtime protocol_version must be 3.")
          }
        Err(message) => return Err(message)
      }
      if runtime_spec_allowed_fields(fields) is Err(message) {
        return Err(message)
      }
      let spec : RuntimeSpec = @json.from_json(parsed) catch {
        err => return Err("Runtime spec does not match Protocol v3: \{err}")
      }
      normalize_runtime_spec(spec)
    }
    _ => Err("Runtime spec must be a JSON object.")
  }
}
