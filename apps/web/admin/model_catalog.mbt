///|
fn model_by_id(
  catalog : Array[@sdk.AdminAiModelSummary],
  id : String,
) -> @sdk.AdminAiModelSummary? {
  for item in catalog {
    if item.id == id {
      return Some(item)
    }
  }
  None
}

///|
fn model_label(
  catalog : Array[@sdk.AdminAiModelSummary],
  id : String,
) -> String {
  match model_by_id(catalog, id) {
    Some(item) =>
      if item.name != "" && item.name != item.id {
        item.name + " - " + item.id
      } else {
        item.id
      }
    None => id
  }
}

///|
fn normalized_model_id(id : String) -> String {
  let text = id.trim().to_owned().to_lower()
  if text.has_prefix("~") {
    text[1:].to_owned()
  } else {
    text
  }
}

///|
fn model_provider(id : String) -> String {
  let parts = normalized_model_id(id).split("/").to_array()
  match parts.get(0) {
    Some(provider) if provider != "" => provider.to_owned()
    _ => "other"
  }
}

///|
fn provider_label(provider : String) -> String {
  match provider {
    "openai" => "OpenAI"
    "anthropic" => "Anthropic"
    "google" => "Google"
    "moonshotai" => "Moonshot AI"
    "deepseek" => "DeepSeek"
    "qwen" => "Qwen"
    "meta-llama" => "Meta Llama"
    "mistralai" => "Mistral AI"
    "xai" => "xAI"
    "cohere" => "Cohere"
    "other" => "Other"
    _ => provider
  }
}

///|
fn provider_rank(provider : String) -> Int {
  match provider {
    "openai" => 1
    "anthropic" => 2
    "google" => 3
    "moonshotai" => 4
    "deepseek" => 5
    "qwen" => 6
    "meta-llama" => 7
    "mistralai" => 8
    "xai" => 9
    "cohere" => 10
    _ => 99
  }
}

///|
fn excluded_recommended_model(id : String) -> Bool {
  [
    ":free", "audio", "embedding", "image", "moderation", "realtime", "search", "transcribe",
    "tts", "vision", "-vl-", "/vl-",
  ].any(fn(token) { id.contains(token) })
}

///|
fn recommended_model(item : @sdk.AdminAiModelSummary) -> Bool {
  let id = normalized_model_id(item.id)
  if excluded_recommended_model(id) {
    return false
  }
  (
    id.has_prefix("openai/gpt-5") &&
    !id.contains("image") &&
    !id.contains("pro")
  ) ||
  id.has_prefix("anthropic/claude-sonnet") ||
  id.has_prefix("anthropic/claude-opus") ||
  id.has_prefix("google/gemini-pro") ||
  (id.contains("/gemini-3") && id.contains("pro")) ||
  id.has_prefix("deepseek/deepseek-chat") ||
  id.has_prefix("deepseek/deepseek-r1") ||
  id.has_prefix("deepseek/deepseek-v3") ||
  id.has_prefix("deepseek/deepseek-v4") ||
  id.contains("coder") ||
  id.contains("qwen3-max") ||
  id.contains("qwen3.5-plus") ||
  id.contains("qwen3.6-plus") ||
  id.contains("qwen-plus")
}

///|
fn search_text(item : @sdk.AdminAiModelSummary) -> String {
  (item.id + " " + item.name + " " + provider_label(model_provider(item.id))).to_lower()
}

///|
fn filtered_catalog(model : AdminModel) -> Array[@sdk.AdminAiModelSummary] {
  let query = model.model_search.trim().to_owned().to_lower()
  let items = []
  for item in model.catalog {
    if model_contains(model.ai_config.allowed_models, item.id) {
      continue
    }
    if model.model_catalog_mode is Recommended && !recommended_model(item) {
      continue
    }
    if query != "" && !search_text(item).contains(query) {
      continue
    }
    items.push(item)
  }
  items.sort_by(fn(left, right) {
    let recommended_diff = (if recommended_model(left) { 0 } else { 1 }) -
      (if recommended_model(right) { 0 } else { 1 })
    if recommended_diff != 0 {
      return recommended_diff
    }
    let left_provider = model_provider(left.id)
    let right_provider = model_provider(right.id)
    let rank_diff = provider_rank(left_provider) - provider_rank(right_provider)
    if rank_diff != 0 {
      return rank_diff
    }
    let provider_diff = provider_label(left_provider).compare(
      provider_label(right_provider),
    )
    if provider_diff != 0 {
      return provider_diff
    }
    left.name.compare(right.name)
  })
  items
}

///|
fn available_model_count(model : AdminModel) -> Int {
  let mut count = 0
  for item in model.catalog {
    if !model_contains(model.ai_config.allowed_models, item.id) {
      count += 1
    }
  }
  count
}
