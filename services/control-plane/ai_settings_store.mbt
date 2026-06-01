///|
struct RuntimeSettings {
  runtime_config : @sdk.RuntimeConfig
  env : Map[String, String]
  secrets : Array[ResolvedRuntimeSecret]
  source_credential : RuntimeServiceSourceCredential
} derive(Debug)

///|
struct ResolvedRuntimeSecret {
  name : String
  value : String
} derive(Debug)

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
  let source_credential = match self.source_credential_for_project(project_id) {
    Ok(credential) => credential
    Err(message) => return Err(message)
  }
  Ok({ runtime_config, env: runtime_config.env, secrets, source_credential })
}

///|
async fn Store::source_credential_for_project(
  self : Store,
  project_id : String,
) -> Result[RuntimeServiceSourceCredential, String] noraise {
  let row = match
    self.query_one(
      (
        #|SELECT
        #|  p.owner_user_id,
        #|  COALESCE(psr.host, '') AS source_host
        #|FROM projects p
        #|LEFT JOIN project_source_repositories psr ON psr.project_id = p.id
        #|WHERE p.id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => row
    None => return Err("Project Source Repository is not configured.")
  }
  let host = row_text(row, "source_host")
  if host != "github" {
    return Err("Project Source Repository is not connected to GitHub.")
  }
  let token = match
    self.get_oauth_access_token(row_text(row, "owner_user_id"), "github") {
    Some(token) => token
    None => return Err("Project Source Credential is not available.")
  }
  Ok({ kind: "git_https_token", username: "x-access-token", password: token })
}

///|
async fn Store::resolve_runtime_secrets(
  self : Store,
  runtime_config : @sdk.RuntimeConfig,
) -> Result[Array[ResolvedRuntimeSecret], String] noraise {
  let resolved : Array[ResolvedRuntimeSecret] = []
  for name_input, source_input in runtime_config.secrets {
    let name = name_input.trim().to_owned()
    if name == "" {
      return Err("Runtime secret name is required.")
    }
    let source = source_input.trim().to_owned()
    if source == "" {
      return Err("Runtime secret source is required.")
    }
    let record = match self.get_admin_secret_record_by_name(source) {
      Some(record) => record
      None => return Err("Runtime secret source is not configured: \{source}")
    }
    resolved.push({ name, value: record.value })
  }
  Ok(resolved)
}
