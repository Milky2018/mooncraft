///|
test "default runtime config is validated by the shared config module" {
  match runtime_config_from_json(default_runtime_config_json()) {
    Ok(config) =>
      debug_inspect(
        config,
        content=(
          #|{
          #|  config_version: 3,
          #|  launcher: { kind: "docker", image: "docker.io/<org>/<image>:<version>" },
          #|  env: {},
          #|  secrets: {},
          #|}
        ),
      )
    Err(message) => fail(message)
  }
}

///|
test "runtime config rejects old manifest and unknown fields" {
  let old_manifest =
    #|{
    #|  "protocol_version": 3,
    #|  "image": "runtime:test"
    #|}
  match runtime_config_from_json(old_manifest) {
    Ok(_) => fail("expected old manifest to be rejected")
    Err(message) =>
      inspect(message, content="Runtime config_version is required.")
  }
  let unknown =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "docker",
    #|    "image": "runtime:test"
    #|  },
    #|  "agent": "codex"
    #|}
  match runtime_config_from_json(unknown) {
    Ok(_) => fail("expected agent to be rejected")
    Err(message) =>
      inspect(message, content="Runtime config field is not supported: agent")
  }
  let unknown_launcher_field =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "docker",
    #|    "image": "runtime:test",
    #|    "command": "start"
    #|  }
    #|}
  match runtime_config_from_json(unknown_launcher_field) {
    Ok(_) => fail("expected launcher command to be rejected")
    Err(message) =>
      inspect(
        message,
        content="Runtime launcher field is not supported: command",
      )
  }
}

///|
test "runtime config normalizes docker launcher env and secret names" {
  let config_json =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": " docker ",
    #|    "image": " runtime:test "
    #|  },
    #|  "env": {
    #|    "RUNTIME_MODE": "production"
    #|  },
    #|  "secrets": {
    #|    " codex_auth ": " codex_subscription "
    #|  }
    #|}
  match runtime_config_from_json(config_json) {
    Ok(config) =>
      debug_inspect(
        config,
        content=(
          #|{
          #|  config_version: 3,
          #|  launcher: { kind: "docker", image: "runtime:test" },
          #|  env: { "RUNTIME_MODE": "production" },
          #|  secrets: { "codex_auth": "codex_subscription" },
          #|}
        ),
      )
    Err(message) => fail(message)
  }
}

///|
test "runtime config rejects unsupported launcher and invalid bindings" {
  let unsupported =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "http",
    #|    "image": "runtime:test"
    #|  }
    #|}
  match runtime_config_from_json(unsupported) {
    Ok(_) => fail("expected unsupported launcher to be rejected")
    Err(message) =>
      inspect(message, content="Runtime launcher kind must be docker.")
  }
  let old_array_secrets =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "docker",
    #|    "image": "runtime:test"
    #|  },
    #|  "secrets": [
    #|    {
    #|      "source": "one",
    #|      "name": "builder_api_key"
    #|    }
    #|  ]
    #|}
  match runtime_config_from_json(old_array_secrets) {
    Ok(_) => fail("expected old array secrets to be rejected")
    Err(message) =>
      inspect(
        message,
        content="Runtime config does not match v3: JsonDecodeError((/secrets, Runtime secrets must be an object))",
      )
  }
}

///|
test "runtime config rejects normalized duplicate secret names" {
  let duplicate =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "docker",
    #|    "image": "runtime:test"
    #|  },
    #|  "secrets": {
    #|    " builder_api_key ": "one",
    #|    "builder_api_key": "two"
    #|  }
    #|}
  match runtime_config_from_json(duplicate) {
    Ok(_) => fail("expected duplicate secret name to be rejected")
    Err(message) =>
      inspect(
        message,
        content="Runtime secret name is duplicated: builder_api_key",
      )
  }
}

///|
test "runtime config rejects reserved env names" {
  let reserved =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "docker",
    #|    "image": "runtime:test"
    #|  },
    #|  "env": {
    #|    "MOONCRAFT_INTERNAL": "bad"
    #|  }
    #|}
  match runtime_config_from_json(reserved) {
    Ok(_) => fail("expected reserved env to be rejected")
    Err(message) =>
      inspect(
        message,
        content="Runtime env name must not use the reserved MOONCRAFT_ prefix.",
      )
  }
}
