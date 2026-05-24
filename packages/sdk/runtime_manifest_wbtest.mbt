///|
test "default runtime manifest is validated by the shared protocol module" {
  match runtime_spec_from_json(default_runtime_manifest_json()) {
    Ok(spec) => {
      inspect(spec.protocol_version, content="2")
      inspect(spec.agent, content="codex")
      inspect(spec.auth.kind, content="openrouter_api_key")
    }
    Err(message) => fail(message)
  }
}

///|
test "runtime manifest rejects v1 and unknown fields" {
  let invalid =
    #|{
    #|  "protocol_version": 2,
    #|  "image": "runtime:test",
    #|  "agent": "codex",
    #|  "model": "openai/test",
    #|  "provider": "openrouter",
    #|  "auth": {
    #|    "kind": "openrouter_api_key",
    #|    "secret": {
    #|      "source": "mooncraft_ai_api_key",
    #|      "target": {
    #|        "type": "env",
    #|        "name": "MOONCRAFT_AI_API_KEY"
    #|      }
    #|    }
    #|  }
    #|}
  match runtime_spec_from_json(invalid) {
    Ok(_) => fail("expected provider to be rejected")
    Err(message) =>
      inspect(
        message,
        content="Runtime Protocol v2 does not support 'provider'.",
      )
  }
}

///|
test "runtime manifest normalizes account file target paths" {
  let spec =
    #|{
    #|  "protocol_version": 2,
    #|  "image": "runtime:test",
    #|  "agent": "codex",
    #|  "model": "openai/test",
    #|  "auth": {
    #|    "kind": "codex_auth_json",
    #|    "secret": {
    #|      "source": "codex_subscription",
    #|      "target": {
    #|        "type": "file",
    #|        "path": " .codex/auth.json "
    #|      }
    #|    }
    #|  }
    #|}
  match runtime_spec_from_json(spec) {
    Ok(spec) =>
      debug_inspect(
        spec.auth.secret.target.path,
        content="Some(\".codex/auth.json\")",
      )
    Err(message) => fail(message)
  }
}
