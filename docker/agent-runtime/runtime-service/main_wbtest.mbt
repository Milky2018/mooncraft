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
test "api key lookup trims secrets and shares provider priority" {
  reset_runtime_service_for_test()
  runtime_secrets["OPENROUTER_API_KEY"] = " router-key "
  runtime_secrets["CODEX_API_KEY"] = " codex-key "
  debug_inspect(current_api_key(), content="Some(\"codex-key\")")
  debug_inspect(current_provider_env_key(), content="Some(\"CODEX_API_KEY\")")
  runtime_secrets.clear()
  runtime_secrets["CODEX_API_KEY"] = " "
  runtime_secrets["OPENROUTER_API_KEY"] = " router-key "
  debug_inspect(current_api_key(), content="Some(\"router-key\")")
  debug_inspect(
    current_provider_env_key(),
    content="Some(\"OPENROUTER_API_KEY\")",
  )
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
  initialized.val = false
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
