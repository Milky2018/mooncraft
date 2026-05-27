///|
test "default runtime manifest is validated by the shared protocol module" {
  match runtime_spec_from_json(default_runtime_manifest_json()) {
    Ok(spec) => {
      inspect(spec.protocol_version, content="3")
      inspect(spec.image, content="docker.io/<org>/<image>:<version>")
      inspect(spec.env.length(), content="0")
      inspect(spec.secrets.length(), content="0")
    }
    Err(message) => fail(message)
  }
}

///|
test "runtime manifest rejects v2 and unknown fields" {
  let invalid =
    #|{
    #|  "protocol_version": 3,
    #|  "image": "runtime:test",
    #|  "agent": "codex"
    #|}
  match runtime_spec_from_json(invalid) {
    Ok(_) => fail("expected agent to be rejected")
    Err(message) =>
      inspect(message, content="Runtime field is not supported: agent")
  }
}

///|
test "runtime manifest normalizes env and file secret target paths" {
  let spec =
    #|{
    #|  "protocol_version": 3,
    #|  "image": " runtime:test ",
    #|  "env": {
    #|    "RUNTIME_MODE": "production"
    #|  },
    #|  "secrets": [
    #|    {
    #|      "source": " codex_subscription ",
    #|      "target": {
    #|        "type": "file",
    #|        "path": " .codex/auth.json "
    #|      }
    #|    }
    #|  ]
    #|}
  match runtime_spec_from_json(spec) {
    Ok(spec) => {
      inspect(spec.image, content="runtime:test")
      debug_inspect(
        spec.env.get("RUNTIME_MODE"),
        content="Some(\"production\")",
      )
      inspect(spec.secrets[0].source, content="codex_subscription")
      debug_inspect(
        spec.secrets[0].target.path,
        content="Some(\".codex/auth.json\")",
      )
    }
    Err(message) => fail(message)
  }
}

///|
test "runtime manifest rejects reserved and duplicate env names" {
  let reserved =
    #|{
    #|  "protocol_version": 3,
    #|  "image": "runtime:test",
    #|  "env": {
    #|    "MOONCRAFT_INTERNAL": "bad"
    #|  }
    #|}
  match runtime_spec_from_json(reserved) {
    Ok(_) => fail("expected reserved env to be rejected")
    Err(message) =>
      inspect(
        message,
        content="Runtime env name must not use the reserved MOONCRAFT_ prefix.",
      )
  }
  let duplicate =
    #|{
    #|  "protocol_version": 3,
    #|  "image": "runtime:test",
    #|  "env": {
    #|    "OPENROUTER_API_KEY": "not-secret"
    #|  },
    #|  "secrets": [
    #|    {
    #|      "source": "secret",
    #|      "target": {
    #|        "type": "env",
    #|        "name": "OPENROUTER_API_KEY"
    #|      }
    #|    }
    #|  ]
    #|}
  match runtime_spec_from_json(duplicate) {
    Ok(_) => fail("expected duplicate env to be rejected")
    Err(message) =>
      inspect(
        message,
        content="Runtime env 'OPENROUTER_API_KEY' must not duplicate a secret env target.",
      )
  }
}
