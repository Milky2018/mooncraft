///|
struct RuntimeSettings {
  runtime_config : @sdk.RuntimeConfig
  env : Map[String, String]
  secrets : Array[ResolvedRuntimeSecret]
}

///|
struct ResolvedRuntimeSecret {
  name : String
  value : String
}

///|
async fn Store::lease_runtime_settings_for_project(
  self : Store,
  project_id : String,
) -> Result[RuntimeSettings, String] noraise {
  let project = match
    self.query_one(
      (
        #|SELECT
        #|  owner_user_id,
        #|  runtime_id,
        #|  runtime_name,
        #|  runtime_config_json
        #|FROM projects
        #|WHERE id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => row
    None => return Err("The project owner could not be loaded for this run.")
  }
  let runtime_config = match
    @sdk.runtime_config_from_json(row_text(project, "runtime_config_json")) {
    Ok(config) => config
    Err(message) =>
      return Err("Project Runtime snapshot is invalid: \{message}")
  }
  let secrets = match self.resolve_runtime_secrets(runtime_config) {
    Ok(secrets) => secrets
    Err(message) => return Err(message)
  }
  Ok({ runtime_config, env: runtime_config.env, secrets })
}

///|
async fn Store::resolve_runtime_secrets(
  self : Store,
  runtime_config : @sdk.RuntimeConfig,
) -> Result[Array[ResolvedRuntimeSecret], String] noraise {
  let resolved : Array[ResolvedRuntimeSecret] = []
  for binding in runtime_config.secrets {
    let source = binding.source.trim().to_owned()
    if source == "" {
      return Err("Runtime secret source is required.")
    }
    let name = binding.name.trim().to_owned()
    if name == "" {
      return Err("Runtime secret name is required.")
    }
    let record = match self.get_admin_secret_record_by_name(source) {
      Some(record) => record
      None => return Err("Runtime secret source is not configured: \{source}")
    }
    resolved.push({ name, value: record.value })
  }
  Ok(resolved)
}
