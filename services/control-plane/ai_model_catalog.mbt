///|
struct ModelOptionsCacheEntry {
  fetched_at : UInt64
  response : @sdk.ListModelOptionsResponse
}

///|
struct OpenAIModelsResponse {
  data : Array[OpenAIModel]
} derive(Debug, FromJson)

///|
struct OpenAIModel {
  id : String
} derive(Debug, FromJson)

///|
struct OpenRouterModelsResponse {
  data : Array[OpenRouterModel]
} derive(Debug, FromJson)

///|
struct OpenRouterModel {
  id : String
  name : String?
  description : String?
  context_length : Int?
  architecture : OpenRouterArchitecture?
} derive(Debug, FromJson)

///|
struct OpenRouterArchitecture {
  modality : String?
  input_modalities : Array[String]?
  output_modalities : Array[String]?
} derive(Debug, FromJson)

///|
let model_options_cache : Ref[Map[String, ModelOptionsCacheEntry]] = @ref.new({})

///|
let model_options_cache_ttl_millis : UInt64 = 60UL * 60UL * 1000UL

///|
fn openai_recommended_model_ids() -> Array[String] {
  ["gpt-5.5", "gpt-5.3-codex", "gpt-5.2"]
}

///|
fn openrouter_recommended_model_ids() -> Array[String] {
  ["openai/gpt-5.5", "openai/gpt-5.3-codex", "anthropic/claude-sonnet-4.5"]
}

///|
fn model_id_is_non_text(id : String) -> Bool {
  let value = id.to_lower()
  value.contains("embedding") ||
  value.contains("moderation") ||
  value.contains("whisper") ||
  value.contains("tts") ||
  value.contains("audio") ||
  value.contains("image") ||
  value.contains("vision") ||
  value.contains("transcribe")
}

///|
fn model_id_is_openai_agent_candidate(id : String) -> Bool {
  !model_id_is_non_text(id) && (id.has_prefix("gpt-") || id.has_prefix("o"))
}

///|
fn openrouter_model_is_text_candidate(model : OpenRouterModel) -> Bool {
  if model_id_is_non_text(model.id) {
    return false
  }
  match model.architecture {
    Some(architecture) =>
      match architecture.output_modalities {
        Some(items) => items.contains("text")
        None =>
          match architecture.modality {
            Some(value) => value.contains("text")
            None => true
          }
      }
    None => true
  }
}

///|
fn model_label_from_id(id : String) -> String {
  id
}

///|
fn model_option(
  provider : String,
  id : String,
  label : String,
  recommended : Bool,
  context_length? : Int? = None,
  description? : String? = None,
) -> @sdk.ModelOption {
  @sdk.ModelOption::{
    id,
    label,
    provider,
    recommended,
    context_length,
    description,
  }
}

///|
fn recommended_ids_for_provider(provider : String) -> Array[String] {
  if provider == "openrouter" {
    openrouter_recommended_model_ids()
  } else {
    openai_recommended_model_ids()
  }
}

///|
fn is_recommended_model(provider : String, id : String) -> Bool {
  recommended_ids_for_provider(provider).contains(id)
}

///|
fn curated_model_options(provider : String) -> Array[@sdk.ModelOption] {
  let items : Array[@sdk.ModelOption] = []
  for id in recommended_ids_for_provider(provider) {
    items.push(model_option(provider, id, model_label_from_id(id), true))
  }
  items
}

///|
fn model_option_ids(items : Array[@sdk.ModelOption]) -> Array[String] {
  let ids : Array[String] = []
  for item in items {
    ids.push(item.id)
  }
  ids
}

///|
fn add_missing_recommended_models(
  provider : String,
  items : Array[@sdk.ModelOption],
) -> Array[@sdk.ModelOption] {
  let result : Array[@sdk.ModelOption] = []
  let existing = model_option_ids(items)
  for id in recommended_ids_for_provider(provider) {
    if !existing.contains(id) {
      result.push(model_option(provider, id, model_label_from_id(id), true))
    }
  }
  for item in items {
    result.push(item)
  }
  result
}

///|
fn model_options_response(
  provider : String,
  items : Array[@sdk.ModelOption],
  source : String,
  warning : String?,
) -> @sdk.ListModelOptionsResponse {
  @sdk.ListModelOptionsResponse::{
    provider,
    items,
    fetched_at: now_string(),
    source,
    warning,
  }
}

///|
fn fallback_model_options_response(
  provider : String,
  warning : String,
) -> @sdk.ListModelOptionsResponse {
  model_options_response(
    provider,
    curated_model_options(provider),
    "fallback",
    Some(warning),
  )
}

///|
fn cached_model_options(cache_key : String) -> @sdk.ListModelOptionsResponse? {
  match model_options_cache.val.get(cache_key) {
    Some(entry) if @env.now() - entry.fetched_at <
      model_options_cache_ttl_millis => Some(entry.response)
    _ => None
  }
}

///|
fn remember_model_options(
  cache_key : String,
  response : @sdk.ListModelOptionsResponse,
) -> Unit {
  model_options_cache.val[cache_key] = { fetched_at: @env.now(), response }
}

///|
fn openai_model_options_from_response(
  payload : OpenAIModelsResponse,
) -> Array[@sdk.ModelOption] {
  let items : Array[@sdk.ModelOption] = []
  for item in payload.data {
    if model_id_is_openai_agent_candidate(item.id) {
      items.push(
        model_option(
          "openai",
          item.id,
          model_label_from_id(item.id),
          is_recommended_model("openai", item.id),
        ),
      )
    }
  }
  add_missing_recommended_models("openai", items)
}

///|
fn openrouter_model_options_from_response(
  payload : OpenRouterModelsResponse,
) -> Array[@sdk.ModelOption] {
  let items : Array[@sdk.ModelOption] = []
  for item in payload.data {
    if openrouter_model_is_text_candidate(item) {
      items.push(
        model_option(
          "openrouter",
          item.id,
          item.name.unwrap_or(item.id),
          is_recommended_model("openrouter", item.id),
          context_length=item.context_length,
          description=item.description,
        ),
      )
    }
  }
  add_missing_recommended_models("openrouter", items)
}

///|
async fn fetch_openai_model_options(
  api_key : String,
) -> Result[@sdk.ListModelOptionsResponse, String] noraise {
  if api_key.trim() == "" {
    return Ok(
      fallback_model_options_response(
        "openai", "Add an OpenAI API key to fetch the model list available to your account.",
      ),
    )
  }
  let headers : Map[String, String] = {
    "Accept": "application/json",
    "Authorization": "Bearer \{api_key}",
  }
  let response = try
    @mocket.fetch("https://api.openai.com/v1/models", GET, headers~)
  catch {
    _ =>
      return Ok(
        fallback_model_options_response(
          "openai", "OpenAI models could not be loaded right now. Showing the curated defaults.",
        ),
      )
  } noraise {
    response => response
  }
  if response.status_code != OK {
    return Ok(
      fallback_model_options_response(
        "openai", "OpenAI did not return a usable model list. Showing the curated defaults.",
      ),
    )
  }
  match decode_json_text(bytes_to_string(response.raw_body)) {
    Ok(payload) =>
      Ok(
        model_options_response(
          "openai",
          openai_model_options_from_response(payload),
          "openai",
          None,
        ),
      )
    Err(_) =>
      Ok(
        fallback_model_options_response(
          "openai", "OpenAI returned an unexpected model list. Showing the curated defaults.",
        ),
      )
  }
}

///|
async fn fetch_openrouter_model_options(
  api_key : String,
) -> Result[@sdk.ListModelOptionsResponse, String] noraise {
  let headers : Map[String, String] = if api_key.trim() == "" {
    { "Accept": "application/json" }
  } else {
    { "Accept": "application/json", "Authorization": "Bearer \{api_key}" }
  }
  let response = try
    @mocket.fetch("https://openrouter.ai/api/v1/models", GET, headers~)
  catch {
    _ =>
      return Ok(
        fallback_model_options_response(
          "openrouter", "OpenRouter models could not be loaded right now. Showing the curated defaults.",
        ),
      )
  } noraise {
    response => response
  }
  if response.status_code != OK {
    return Ok(
      fallback_model_options_response(
        "openrouter", "OpenRouter did not return a usable model list. Showing the curated defaults.",
      ),
    )
  }
  match decode_json_text(bytes_to_string(response.raw_body)) {
    Ok(payload) =>
      Ok(
        model_options_response(
          "openrouter",
          openrouter_model_options_from_response(payload),
          "openrouter",
          None,
        ),
      )
    Err(_) =>
      Ok(
        fallback_model_options_response(
          "openrouter", "OpenRouter returned an unexpected model list. Showing the curated defaults.",
        ),
      )
  }
}

///|
async fn list_ai_model_options(
  user_id : String,
  provider_input : String,
  credentials : AiCredentialSettings,
) -> Result[@sdk.ListModelOptionsResponse, String] noraise {
  let provider = match normalize_ai_provider(provider_input) {
    Ok(provider) => provider
    Err(message) => return Err(message)
  }
  let cache_key = "\{provider}:\{user_id}"
  match cached_model_options(cache_key) {
    Some(response) => return Ok(response)
    None => ignore(())
  }
  let api_key = if credentials.provider == provider {
    credentials.api_key
  } else {
    ""
  }
  let response = match provider {
    "openrouter" => fetch_openrouter_model_options(api_key)
    _ => fetch_openai_model_options(api_key)
  }
  match response {
    Ok(response) => {
      remember_model_options(cache_key, response)
      Ok(response)
    }
    Err(message) => Err(message)
  }
}
