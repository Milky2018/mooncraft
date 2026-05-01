///|
test "curated model options include provider defaults" {
  let openai = curated_model_options("openai")
  let openrouter = curated_model_options("openrouter")
  assert_true(model_option_ids(openai).contains("gpt-5.5"))
  assert_true(model_option_ids(openrouter).contains("openai/gpt-5.5"))
}

///|
test "openai model filtering removes non-agent models" {
  assert_true(model_id_is_openai_agent_candidate("gpt-5.5"))
  assert_true(model_id_is_openai_agent_candidate("o4-mini"))
  assert_false(model_id_is_openai_agent_candidate("text-embedding-3-large"))
  assert_false(model_id_is_openai_agent_candidate("gpt-image-1"))
}

///|
test "openrouter filtering prefers text output models" {
  let text_model = OpenRouterModel::{
    id: "openai/gpt-5.5",
    name: Some("GPT-5.5"),
    description: None,
    context_length: Some(128000),
    architecture: Some(OpenRouterArchitecture::{
      modality: None,
      input_modalities: Some(["text"]),
      output_modalities: Some(["text"]),
    }),
  }
  let image_model = OpenRouterModel::{
    id: "provider/image-model",
    name: Some("Image Model"),
    description: None,
    context_length: None,
    architecture: Some(OpenRouterArchitecture::{
      modality: None,
      input_modalities: Some(["text"]),
      output_modalities: Some(["image"]),
    }),
  }
  assert_true(openrouter_model_is_text_candidate(text_model))
  assert_false(openrouter_model_is_text_candidate(image_model))
}

///|
test "provider model responses prepend missing recommended options" {
  let payload = OpenRouterModelsResponse::{
    data: [
      OpenRouterModel::{
        id: "provider/custom-text",
        name: Some("Custom Text"),
        description: None,
        context_length: Some(8192),
        architecture: None,
      },
    ],
  }
  let options = openrouter_model_options_from_response(payload)
  let ids = model_option_ids(options)
  assert_true(ids.contains("openai/gpt-5.5"))
  assert_true(ids.contains("provider/custom-text"))
}
