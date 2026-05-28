///|
struct RuntimeSettings {
  runtime_spec : @sdk.RuntimeSpec
  env : Map[String, String]
  secrets : Array[ResolvedRuntimeSecret]
}

///|
struct ResolvedRuntimeSecret {
  env : String?
  file : String?
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
        #|  runtime_spec_json
        #|FROM projects
        #|WHERE id = ?;
      ),
      params=[String(project_id)],
    ) {
    Some(row) => row
    None => return Err("The project owner could not be loaded for this run.")
  }
  let runtime_spec = match
    @sdk.runtime_spec_from_json(row_text(project, "runtime_spec_json")) {
    Ok(spec) => spec
    Err(message) =>
      return Err("Project Runtime snapshot is invalid: \{message}")
  }
  let secrets = match self.resolve_runtime_secrets(runtime_spec) {
    Ok(secrets) => secrets
    Err(message) => return Err(message)
  }
  Ok({ runtime_spec, env: runtime_spec.env, secrets })
}

///|
async fn Store::resolve_runtime_secrets(
  self : Store,
  runtime_spec : @sdk.RuntimeSpec,
) -> Result[Array[ResolvedRuntimeSecret], String] noraise {
  let resolved : Array[ResolvedRuntimeSecret] = []
  for binding in runtime_spec.secrets {
    let source = binding.source.trim().to_owned()
    if source == "" {
      return Err("Runtime secret source is required.")
    }
    let record = match self.get_admin_secret_record_by_name(source) {
      Some(record) => record
      None => return Err("Runtime secret source is not configured: \{source}")
    }
    match binding.target.kind {
      "env" =>
        match binding.target.name {
          Some(name) if name.trim() != "" =>
            resolved.push({
              env: Some(name.trim().to_owned()),
              file: None,
              value: record.value,
            })
          _ => return Err("Runtime secret env target name is required.")
        }
      "file" =>
        match binding.target.path {
          Some(path) if path.trim() != "" =>
            resolved.push({
              env: None,
              file: Some(path.trim().to_owned()),
              value: record.value,
            })
          _ => return Err("Runtime secret file target path is required.")
        }
      _ => return Err("Runtime secret target type must be env or file.")
    }
  }
  Ok(resolved)
}
