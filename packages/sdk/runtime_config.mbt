///|
pub fn runtime_config_version() -> Int {
  3
}

///|
pub fn runtime_config_allowed_fields() -> Array[String] {
  ["config_version", "launcher", "env", "secrets"]
}

///|
pub fn runtime_config_to_json(config : RuntimeConfig) -> String {
  config.to_json().stringify()
}

///|
pub fn default_runtime_config_json() -> String {
  (
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "docker",
    #|    "image": "docker.io/<org>/<image>:<version>"
    #|  },
    #|  "env": {},
    #|  "secrets": []
    #|}
  )
}

///|
fn runtime_config_int_field(
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
fn runtime_config_allowed_fields_check(
  fields : Map[String, Json],
) -> Result[Unit, String] {
  let allowed = runtime_config_allowed_fields()
  for key in fields.keys() {
    if !allowed.any(fn(name) { name == key }) {
      return Err("Runtime config field is not supported: \{key}")
    }
  }
  Ok(())
}

///|
fn runtime_launcher_allowed_fields_check(
  fields : Map[String, Json],
) -> Result[Unit, String] {
  let allowed = ["kind", "image"]
  for key in fields.keys() {
    if !allowed.any(fn(name) { name == key }) {
      return Err("Runtime launcher field is not supported: \{key}")
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
fn normalize_runtime_launcher(
  launcher : RuntimeLauncher,
) -> Result[RuntimeLauncher, String] {
  let kind = launcher.kind.trim().to_owned()
  if kind != "docker" {
    return Err("Runtime launcher kind must be docker.")
  }
  let image = launcher.image.trim().to_owned()
  if image == "" {
    return Err("Runtime launcher image is required.")
  }
  Ok({ kind, image })
}

///|
fn normalize_runtime_secret_binding(
  secret : RuntimeSecret,
) -> Result[RuntimeSecret, String] {
  let source = secret.source.trim().to_owned()
  if source == "" {
    return Err("Runtime secret source is required.")
  }
  let name = secret.name.trim().to_owned()
  if name == "" {
    return Err("Runtime secret name is required.")
  }
  Ok({ source, name })
}

///|
fn normalize_runtime_secrets(
  secrets : Array[RuntimeSecret],
) -> Result[Array[RuntimeSecret], String] {
  let normalized : Array[RuntimeSecret] = []
  let names : Map[String, Bool] = {}
  for secret in secrets {
    let binding = match normalize_runtime_secret_binding(secret) {
      Ok(binding) => binding
      Err(message) => return Err(message)
    }
    if names.contains(binding.name) {
      return Err("Runtime secret name is duplicated: \{binding.name}")
    }
    names[binding.name] = true
    normalized.push(binding)
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
pub fn normalize_runtime_config(
  config : RuntimeConfig,
) -> Result[RuntimeConfig, String] {
  let config_version = config.config_version
  if config_version != runtime_config_version() {
    return Err("Runtime config_version must be 3.")
  }
  let launcher = match normalize_runtime_launcher(config.launcher) {
    Ok(launcher) => launcher
    Err(message) => return Err(message)
  }
  let env = match normalize_runtime_env(config.env) {
    Ok(env) => env
    Err(message) => return Err(message)
  }
  let secrets = match normalize_runtime_secrets(config.secrets) {
    Ok(secrets) => secrets
    Err(message) => return Err(message)
  }
  Ok({ config_version, launcher, env, secrets })
}

///|
pub fn runtime_config_from_json(text : String) -> Result[RuntimeConfig, String] {
  let parsed = @json.parse(text) catch {
    _ => return Err("Runtime config must be valid JSON.")
  }
  match parsed {
    Object(fields) => {
      match runtime_config_int_field(fields, "config_version") {
        Ok(value) =>
          if value != runtime_config_version() {
            return Err("Runtime config_version must be 3.")
          }
        Err(message) => return Err(message)
      }
      if runtime_config_allowed_fields_check(fields) is Err(message) {
        return Err(message)
      }
      match fields.get("launcher") {
        Some(Object(launcher_fields)) =>
          if runtime_launcher_allowed_fields_check(launcher_fields)
            is Err(message) {
            return Err(message)
          }
        _ => ()
      }
      let config : RuntimeConfig = @json.from_json(parsed) catch {
        err => return Err("Runtime config does not match v3: \{err}")
      }
      normalize_runtime_config(config)
    }
    _ => Err("Runtime config must be a JSON object.")
  }
}
