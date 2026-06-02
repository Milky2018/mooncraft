///|
fn init_request_for_test() -> @runtime_protocol.RuntimeServiceInitRequest {
  {
    project: { id: "project-1" },
    source_repository: {
      url: "https://github.com/moonbitlang/project-1.git",
      default_branch: "main",
      current_commit_sha: Some("abc123"),
    },
    source_credential: {
      kind: "git_https_token",
      username: "x-access-token",
      password: "token with spaces",
    },
    secrets: [{ name: "OPENROUTER_API_KEY", value: "runtime-key" }],
  }
}

///|
test "source authenticated url encodes credential without changing repository path" {
  debug_inspect(
    source_authenticated_url(init_request_for_test()),
    content=(
      #|Ok("https://x-access-token:token%20with%20spaces@github.com/moonbitlang/project-1.git")
    ),
  )
}

///|
test "preview subtree paths map to generated app paths" {
  debug_inspect(
    [
      preview_upstream_path("/preview"),
      preview_upstream_path("/preview/"),
      preview_upstream_path("/preview/assets/app.js"),
    ],
    content=(
      #|["/", "/", "/assets/app.js"]
    ),
  )
}

///|
test "official runtime auth requires exactly one secret and ignores env keys" {
  reset_runtime_service_for_test()
  runtime_secrets["CODEX_API_KEY"] = " codex-key "
  inspect(
    resolved_runtime_auth_for_test(),
    content="Ok(CODEX_API_KEY=codex-key)",
  )

  runtime_secrets.clear()
  @env.set_env_var("CODEX_API_KEY", "env-key")
  defer @env.unset_env_var("CODEX_API_KEY")
  inspect(
    resolved_runtime_auth_for_test(),
    content=(
      #|Err(Official Codex Runtime requires exactly one authentication secret: CODEX_AUTH_JSON, CODEX_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY.)
    ),
  )

  runtime_secrets["CODEX_API_KEY"] = " codex-key "
  runtime_secrets["OPENAI_API_KEY"] = " openai-key "
  inspect(
    resolved_runtime_auth_for_test(),
    content=(
      #|Err(Official Codex Runtime received multiple authentication secrets. Configure exactly one of CODEX_AUTH_JSON, CODEX_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY.)
    ),
  )
}

///|
test "official runtime auth rejects conflicting base url config" {
  reset_runtime_service_for_test()
  @env.set_env_var("OPENAI_BASE_URL", "https://example.invalid/v1")
  defer @env.unset_env_var("OPENAI_BASE_URL")

  runtime_secrets["CODEX_AUTH_JSON"] = "{}"
  inspect(
    resolved_runtime_auth_for_test(),
    content=(
      #|Err(CODEX_AUTH_JSON cannot be combined with env.OPENAI_BASE_URL.)
    ),
  )

  runtime_secrets.clear()
  runtime_secrets["OPENROUTER_API_KEY"] = " router-key "
  inspect(
    resolved_runtime_auth_for_test(),
    content=(
      #|Err(OPENROUTER_API_KEY always uses https://openrouter.ai/api/v1; remove env.OPENAI_BASE_URL.)
    ),
  )
}

///|
test "codex process env strips auth variables" {
  @env.set_env_var("CODEX_API_KEY", "env-key")
  @env.set_env_var("OPENAI_BASE_URL", "https://example.invalid/v1")
  defer {
    @env.unset_env_var("CODEX_API_KEY")
    @env.unset_env_var("OPENAI_BASE_URL")
  }
  let env = codex_process_env()
  debug_inspect(env.get("CODEX_API_KEY"), content="None")
  debug_inspect(env.get("OPENAI_BASE_URL"), content="None")
}

///|
fn resolved_runtime_auth_for_test() -> String {
  match resolved_runtime_auth() {
    Ok(CodexAuthJson(value)) => "Ok(CODEX_AUTH_JSON=\{value})"
    Ok(CodexApiKey(value)) => "Ok(CODEX_API_KEY=\{value})"
    Ok(OpenAIApiKey(value)) => "Ok(OPENAI_API_KEY=\{value})"
    Ok(OpenRouterApiKey(value)) => "Ok(OPENROUTER_API_KEY=\{value})"
    Err(message) => "Err(\{message})"
  }
}

///|
async test "ensure directory accepts an existing directory" {
  let path = "/tmp/mooncraft-runtime-service-dir-test-\{@env.now()}"
  @fs.mkdir(path, permission=0o755)
  debug_inspect(ensure_directory(path, "test directory"), content="Ok(())")
  @fs.rmdir(path)
}

///|
fn reset_runtime_service_for_test() -> Unit {
  runs.clear()
  active_run_id.val = None
  pending_run.val = None
  preview_pid.val = None
  preview_process.val = None
  initialized.val = false
  runtime_init_identity.val = None
  runtime_init_commit_sha.val = None
  runtime_secrets.clear()
  runtime_source.val = None
}

///|
fn reply_text(reply : HttpReply) -> String {
  @utf8.decode(reply.body) catch {
    _ => ""
  }
}

///|
test "exec is rejected before init" {
  reset_runtime_service_for_test()
  let reply = handle_exec(
    "{\"run_id\":\"run-before-init\",\"prompt\":\"Build a tiny app.\"}",
  )
  inspect(reply.code, content="409")
  inspect(
    reply_text(reply),
    content=(
      #|{"message":"Runtime Service is not initialized. Call /init first."}
    ),
  )
}

///|
async test "init is idempotent for the same request after ready" {
  reset_runtime_service_for_test()
  let request = init_request_for_test()
  initialized.val = true
  runtime_init_identity.val = Some(init_request_identity(request))
  runtime_init_commit_sha.val = Some("abc123")
  runtime_secrets["KEEP_ME"] = "secret-value"
  let source : RuntimeSourceState = {
    repository: request.source_repository,
    credential: request.source_credential,
    authenticated_url: "https://existing.example/repo.git",
  }
  runtime_source.val = Some(source)
  let reply = handle_init(request.to_json().stringify())
  inspect(reply.code, content="200")
  inspect(
    reply_text(reply),
    content=(
      #|{"status":"ready","current_commit_sha":"abc123","message":"Runtime initialized."}
    ),
  )
  debug_inspect(
    runtime_secrets.get("KEEP_ME"),
    content="Some(\"secret-value\")",
  )
  debug_inspect(
    runtime_source.val.map(fn(value) { value.authenticated_url }),
    content="Some(\"https://existing.example/repo.git\")",
  )
}

///|
async test "init rejects different request after ready without mutation" {
  reset_runtime_service_for_test()
  let request = init_request_for_test()
  let different_request = {
    ..request,
    source_repository: {
      ..request.source_repository,
      current_commit_sha: Some("def456"),
    },
  }
  initialized.val = true
  runtime_init_identity.val = Some(init_request_identity(request))
  runtime_init_commit_sha.val = Some("abc123")
  runtime_secrets["KEEP_ME"] = "secret-value"
  let source : RuntimeSourceState = {
    repository: request.source_repository,
    credential: request.source_credential,
    authenticated_url: "https://existing.example/repo.git",
  }
  runtime_source.val = Some(source)
  let reply = handle_init(different_request.to_json().stringify())
  inspect(reply.code, content="409")
  inspect(
    reply_text(reply),
    content=(
      #|{"message":"Runtime Service is already initialized with different initialization data."}
    ),
  )
  debug_inspect(
    runtime_secrets.get("KEEP_ME"),
    content="Some(\"secret-value\")",
  )
  debug_inspect(
    runtime_source.val.map(fn(value) { value.authenticated_url }),
    content="Some(\"https://existing.example/repo.git\")",
  )
}

///|
async test "init is rejected while a run is active" {
  reset_runtime_service_for_test()
  initialized.val = true
  active_run_id.val = Some("run-active")
  let reply = handle_init(init_request_for_test().to_json().stringify())
  inspect(reply.code, content="409")
  inspect(
    reply_text(reply),
    content=(
      #|{"message":"Runtime Service cannot be initialized while a run is active."}
    ),
  )
}

///|
test "exec registers a readable idempotent run after init" {
  reset_runtime_service_for_test()
  initialized.val = true
  let first = handle_exec(
    "{\"run_id\":\"run-contract\",\"prompt\":\"Build a tiny app.\"}",
  )
  inspect(first.code, content="202")
  let status = handle_run("run-contract")
  inspect(status.code, content="200")
  let same = handle_exec(
    "{\"run_id\":\"run-contract\",\"prompt\":\"Build a tiny app.\"}",
  )
  inspect(same.code, content="202")
  let different = handle_exec(
    "{\"run_id\":\"run-contract\",\"prompt\":\"Build a different app.\"}",
  )
  inspect(different.code, content="409")
}

///|
test "run events honor after cursor" {
  reset_runtime_service_for_test()
  initialized.val = true
  let reply = handle_exec(
    "{\"run_id\":\"run-events\",\"prompt\":\"Build a tiny app.\"}",
  )
  inspect(reply.code, content="202")
  match runs.get("run-events") {
    Some(run) => {
      add_event(
        run,
        @runtime_protocol.runtime_service_event_level_info(),
        "Second",
      )
      let all = handle_run_events(
        "run-events", "/runs/run-events/events?after=0",
      )
      inspect(all.code, content="200")
      inspect(
        reply_text(all).contains("Builder session accepted."),
        content="true",
      )
      let after_all = handle_run_events(
        "run-events", "/runs/run-events/events?after=999",
      )
      inspect(after_all.code, content="200")
      inspect(reply_text(after_all), content="{\"events\":[]}")
    }
    None => fail("expected run to be registered")
  }
}
