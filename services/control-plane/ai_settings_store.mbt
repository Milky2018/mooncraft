///|
struct AiRuntimeSettings {
  provider : String
  model : String
  api_key : String
}

///|
struct AiCredentialSettings {
  provider : String
  api_key : String
}

///|
fn default_ai_provider() -> String {
  "openai"
}

///|
fn default_openai_model() -> String {
  "gpt-5.5"
}

///|
fn default_openrouter_model() -> String {
  "openai/gpt-5.5"
}

///|
fn normalize_ai_provider(provider : String) -> Result[String, String] {
  match provider.trim().to_owned().to_lower() {
    "openai" => Ok("openai")
    "openrouter" => Ok("openrouter")
    _ => Err("AI provider must be either openai or openrouter.")
  }
}

///|
fn normalized_ai_model(provider : String, model : String) -> String {
  let trimmed = model.trim().to_owned()
  if trimmed != "" {
    trimmed
  } else if provider == "openrouter" {
    default_openrouter_model()
  } else {
    default_openai_model()
  }
}

///|
fn ai_settings_response_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AiSettingsResponse {
  let provider = normalize_ai_provider(row_text(row, "ai_provider")).unwrap_or(
    default_ai_provider(),
  )
  @sdk.AiSettingsResponse::{
    provider,
    model: normalized_ai_model(provider, row_text(row, "ai_model")),
    api_key_configured: row_text(row, "ai_api_key") != "",
  }
}

///|
async fn Store::get_ai_settings(
  self : Store,
  user_id : String,
) -> @sdk.AiSettingsResponse? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  COALESCE(ai_provider, 'openai') AS ai_provider,
        #|  COALESCE(ai_model, '') AS ai_model,
        #|  COALESCE(ai_api_key, '') AS ai_api_key
        #|FROM users
        #|WHERE id = ?;
      ),
      params=[@db.String(user_id)],
    ) {
    Some(row) => Some(ai_settings_response_from_row(row))
    None => None
  }
}

///|
async fn Store::get_ai_credential_settings(
  self : Store,
  user_id : String,
) -> AiCredentialSettings? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  COALESCE(ai_provider, 'openai') AS ai_provider,
        #|  COALESCE(ai_model, '') AS ai_model,
        #|  COALESCE(ai_api_key, '') AS ai_api_key
        #|FROM users
        #|WHERE id = ?;
      ),
      params=[@db.String(user_id)],
    ) {
    Some(row) => {
      let provider = normalize_ai_provider(row_text(row, "ai_provider")).unwrap_or(
        default_ai_provider(),
      )
      Some({ provider, api_key: row_text(row, "ai_api_key") })
    }
    None => None
  }
}

///|
async fn Store::update_ai_settings(
  self : Store,
  user_id : String,
  provider_input : String,
  model_input : String,
  api_key_input : String,
) -> Result[@sdk.AiSettingsResponse, String] noraise {
  let provider = match normalize_ai_provider(provider_input) {
    Ok(provider) => provider
    Err(message) => return Err(message)
  }
  let model = normalized_ai_model(provider, model_input)
  let existing = match
    self.query_one(
      (
        #|SELECT COALESCE(ai_api_key, '') AS ai_api_key
        #|FROM users
        #|WHERE id = ?;
      ),
      params=[@db.String(user_id)],
    ) {
    Some(row) => row_text(row, "ai_api_key")
    None => return Err("User not found.")
  }
  let api_key = if api_key_input.trim() == "" {
    existing
  } else {
    api_key_input.trim().to_owned()
  }
  if api_key == "" {
    return Err("API key is required before building apps with AI.")
  }
  match
    self.exec_or_error(
      (
        #|UPDATE users
        #|SET ai_provider = ?,
        #|    ai_model = ?,
        #|    ai_api_key = ?,
        #|    updated_at = ?
        #|WHERE id = ?;
      ),
      "update user AI settings",
      params=[
        @db.String(provider),
        @db.String(model),
        @db.String(api_key),
        @db.String(now_string()),
        @db.String(user_id),
      ],
    ) {
    Ok(_) =>
      match self.get_ai_settings(user_id) {
        Some(settings) => Ok(settings)
        None => Err("The AI settings were saved but could not be loaded.")
      }
    Err(message) => Err(message)
  }
}

///|
async fn Store::get_ai_runtime_settings_for_project(
  self : Store,
  project_id : String,
) -> Result[AiRuntimeSettings, String] noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  COALESCE(u.ai_provider, 'openai') AS ai_provider,
        #|  COALESCE(u.ai_model, '') AS ai_model,
        #|  COALESCE(u.ai_api_key, '') AS ai_api_key
        #|FROM projects p
        #|JOIN users u ON u.id = p.owner_user_id
        #|WHERE p.id = ?;
      ),
      params=[@db.String(project_id)],
    ) {
    Some(row) => {
      let provider = match normalize_ai_provider(row_text(row, "ai_provider")) {
        Ok(provider) => provider
        Err(message) => return Err(message)
      }
      let api_key = row_text(row, "ai_api_key").trim().to_owned()
      if api_key == "" {
        return Err(
          "Configure your AI provider and API key in Account before building apps.",
        )
      }
      Ok({
        provider,
        model: normalized_ai_model(provider, row_text(row, "ai_model")),
        api_key,
      })
    }
    None => Err("The project owner could not be loaded for this run.")
  }
}
