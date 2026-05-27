///|
struct AiRuntimeSettings {
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
fn default_openrouter_model() -> String {
  "openai/gpt-5.4-mini"
}

///|
fn default_openrouter_secret_source() -> String {
  "mooncraft_ai_api_key"
}

///|
fn normalize_openrouter_model(model : String) -> String {
  let trimmed = model.trim().to_owned()
  if trimmed == "" {
    default_openrouter_model()
  } else {
    trimmed
  }
}

///|
fn normalize_allowed_models(models : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for model in models {
    let normalized = model.trim().to_owned()
    if normalized != "" && !result.contains(normalized) {
      result.push(normalized)
    }
  }
  result
}

///|
fn allowed_models_to_db(models : Array[String]) -> String {
  normalize_allowed_models(models).join("\n")
}

///|
fn allowed_models_from_db(value : String) -> Array[String] {
  normalize_allowed_models(
    value.split("\n").to_array().map(fn(line) { line.to_owned() }),
  )
}

///|
async fn Store::get_admin_ai_config(
  self : Store,
) -> @sdk.AdminAiConfigResponse noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  COALESCE(default_model, '') AS default_model,
        #|  COALESCE(allowed_models, '') AS allowed_models,
        #|  updated_at
        #|FROM ai_runtime_config
        #|WHERE id = ?;
      ),
      params=[String("default")],
    ) {
    Some(row) => {
      let default_model = normalize_openrouter_model(
        row_text(row, "default_model"),
      )
      let allowed_models = allowed_models_from_db(
        row_text(row, "allowed_models"),
      )
      {
        default_model,
        allowed_models: if allowed_models.length() == 0 {
          [default_model]
        } else {
          allowed_models
        },
        updated_at: row_text(row, "updated_at"),
      }
    }
    None =>
      {
        default_model: default_openrouter_model(),
        allowed_models: [default_openrouter_model()],
        updated_at: now_string(),
      }
  }
}

///|
async fn Store::update_admin_ai_config(
  self : Store,
  default_model_input : String,
  allowed_models_input : Array[String],
) -> Result[@sdk.AdminAiConfigResponse, String] noraise {
  let default_model = normalize_openrouter_model(default_model_input)
  let allowed_models = normalize_allowed_models(allowed_models_input)
  let persisted_allowed = if allowed_models.length() == 0 {
    [default_model]
  } else if allowed_models.contains(default_model) {
    allowed_models
  } else {
    let next = [default_model]
    for model in allowed_models {
      next.push(model)
    }
    next
  }
  let now = now_string()
  match
    self.exec_or_error(
      (
        #|INSERT INTO ai_runtime_config (
        #|  id,
        #|  default_model,
        #|  allowed_models,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?)
        #|ON CONFLICT(id) DO UPDATE SET
        #|  default_model = excluded.default_model,
        #|  allowed_models = excluded.allowed_models,
        #|  updated_at = excluded.updated_at;
      ),
      "update AI runtime config",
      params=[
        String("default"),
        String(default_model),
        String(allowed_models_to_db(persisted_allowed)),
        String(now),
      ],
    ) {
    Ok(_) =>
      Ok({ default_model, allowed_models: persisted_allowed, updated_at: now })
    Err(message) => Err(message)
  }
}

///|
async fn Store::get_openrouter_model_catalog_api_key(
  self : Store,
) -> Result[String, String] noraise {
  if self.get_admin_secret_record_by_name(default_openrouter_secret_source())
    is Some(record) {
    let value = record.value.trim().to_owned()
    if value != "" {
      return Ok(value)
    }
  }
  Err("Create the mooncraft_ai_api_key Secret before loading provider models.")
}

///|
async fn Store::lease_ai_runtime_settings_for_project(
  self : Store,
  project_id : String,
) -> Result[AiRuntimeSettings, String] noraise {
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
