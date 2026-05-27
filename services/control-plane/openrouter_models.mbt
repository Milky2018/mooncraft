///|
let openrouter_models_url = "https://openrouter.ai/api/v1/models?output_modalities=text"

///|
fn openrouter_model_string_field(
  fields : Map[String, Json],
  name : String,
) -> String {
  match fields.get(name) {
    Some(String(value)) => value
    _ => ""
  }
}

///|
fn openrouter_model_int_field(fields : Map[String, Json], name : String) -> Int {
  match fields.get(name) {
    Some(Number(_, ..) as value) =>
      @string.parse_int(value.stringify()) catch {
        _ => 0
      }
    Some(String(value)) => @string.parse_int(value) catch { _ => 0 }
    _ => 0
  }
}

///|
fn openrouter_pricing_field(
  fields : Map[String, Json],
  name : String,
) -> String {
  match fields.get("pricing") {
    Some(Object(pricing)) =>
      match pricing.get(name) {
        Some(String(value)) => value
        Some(Number(_, ..) as value) => value.stringify()
        _ => ""
      }
    _ => ""
  }
}

///|
fn openrouter_model_from_json(value : Json) -> @sdk.AdminAiModelSummary? {
  match value {
    Object(fields) => {
      let id = openrouter_model_string_field(fields, "id")
      if id == "" {
        None
      } else {
        let name = openrouter_model_string_field(fields, "name")
        Some({
          id,
          name: if name == "" {
            id
          } else {
            name
          },
          context_length: openrouter_model_int_field(fields, "context_length"),
          prompt_price: openrouter_pricing_field(fields, "prompt"),
          completion_price: openrouter_pricing_field(fields, "completion"),
        })
      }
    }
    _ => None
  }
}

///|
fn openrouter_models_from_response(
  body : String,
) -> Result[Array[@sdk.AdminAiModelSummary], String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("OpenRouter did not return valid JSON.")
  }
  match parsed {
    Object(fields) =>
      match fields.get("data") {
        Some(Array(values)) => {
          let models : Array[@sdk.AdminAiModelSummary] = []
          for value in values {
            if openrouter_model_from_json(value) is Some(model) {
              models.push(model)
            }
          }
          if models.length() == 0 {
            Err("OpenRouter did not return any usable text models.")
          } else {
            Ok(models)
          }
        }
        _ => Err("OpenRouter did not return a model list.")
      }
    _ => Err("OpenRouter did not return an object response.")
  }
}

///|
async fn AppContext::fetch_openrouter_models(
  self : AppContext,
) -> Result[@sdk.AdminListAiModelsResponse, String] noraise {
  let api_key = match self.store.get_openrouter_model_catalog_api_key() {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let headers : Map[String, String] = {
    "Accept": "application/json",
    "Authorization": "Bearer \{api_key}",
  }
  let response = try @mocket.fetch(openrouter_models_url, GET, headers~) catch {
    _ => return Err("OpenRouter model list could not be loaded.")
  } noraise {
    value => value
  }
  if !http_status_success(response.status_code) {
    return Err("OpenRouter model list request failed.")
  }
  match openrouter_models_from_response(bytes_to_string(response.raw_body)) {
    Ok(items) => Ok({ items, fetched_at: now_string() })
    Err(message) => Err(message)
  }
}
