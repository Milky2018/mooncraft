///|
test "preview audit targets public preview proxy path" {
  let preview : @sdk.PreviewTarget = {
    url: "/p/public-preview-id/",
    port: 4792,
    healthy: true,
  }
  debug_inspect(
    preview_audit_target_url_for_base("http://127.0.0.1:8080", preview),
    content="\"http://127.0.0.1:8080/p/public-preview-id/\"",
  )
  debug_inspect(
    preview_audit_target_url_for_base("http://127.0.0.1:8080/", preview),
    content="\"http://127.0.0.1:8080/p/public-preview-id/\"",
  )
}

///|
test "preview audit accepts absolute preview origin" {
  let preview : @sdk.PreviewTarget = {
    url: "https://preview-id.example.test/",
    port: 4792,
    healthy: true,
  }
  debug_inspect(
    preview_audit_target_url_for_base("http://127.0.0.1:8080", preview),
    content="\"https://preview-id.example.test/\"",
  )
}

///|
test "claude stream json emits lifecycle events" {
  match
    runtime_display_event(
      (
        #|{"type":"system","subtype":"init","session_id":"session-test"}
      ),
    ) {
    Some((kind, content)) => {
      inspect(kind, content="status")
      inspect(content, content="Started the builder session.")
    }
    None => fail("expected claude init event")
  }
  match
    runtime_display_event(
      (
        #|{"type":"result","subtype":"success","is_error":false}
      ),
    ) {
    Some((kind, content)) => {
      inspect(kind, content="status")
      inspect(content, content="Builder session ended.")
    }
    None => fail("expected claude result event")
  }
}

///|
test "claude stream json emits assistant progress and tool status" {
  match
    runtime_display_event(
      (
        #|{"type":"assistant","message":{"content":[{"type":"text","text":"Now I have a clear picture of the template."}]}}
      ),
    ) {
    Some((kind, content)) => {
      inspect(kind, content="progress")
      inspect(content, content="Now I have a clear picture of the template.")
    }
    None => fail("expected claude assistant progress")
  }
  match
    runtime_display_event(
      (
        #|{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"description":"Check available MoonCraft templates","command":"cat /opt/mooncraft/templates/catalog.json"}}]}}
      ),
    ) {
    Some((kind, content)) => {
      inspect(kind, content="status")
      inspect(content, content="Check available MoonCraft templates")
    }
    None => fail("expected claude tool status")
  }
}

///|
test "codex stream json parses structured assistant progress" {
  match
    runtime_display_event(
      (
        #|{"type":"agent_message","text":"Escaped \"quote\" progress"}
      ),
    ) {
    Some((kind, content)) => {
      inspect(kind, content="progress")
      inspect(content, content="Escaped \"quote\" progress")
    }
    None => fail("expected codex assistant progress")
  }
}

///|
test "claude stream json emits failed tool repair status" {
  match
    runtime_display_event(
      (
        #|{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"moon check failed"}]}}
      ),
    ) {
    Some((kind, content)) => {
      inspect(kind, content="status")
      inspect(
        content,
        content="A workspace check failed; the builder is fixing it.",
      )
    }
    None => fail("expected claude failed tool event")
  }
}

///|
fn test_runtime_config() -> AgentRuntimeConfig {
  {
    agent_session_id: "agent-session-test",
    runtime_session_id: None,
    image: "runtime:test",
    platform: "linux/arm64",
    agent_cli: "claude",
    auth_kind: "openrouter_api_key",
    model: "anthropic/claude-sonnet-4.5",
    secret: { env: Some("MOONCRAFT_AI_API_KEY"), file: None, value: "test-key" },
    container_data_dir: "/app/data",
    host_data_dir: None,
  }
}

///|
fn test_run_artifacts() -> RunArtifacts {
  {
    project_id: "project-test",
    run_id: "run-test",
    dir: "/tmp/artifacts",
    prompt_path: "/tmp/artifacts/prompt.txt",
    last_message_path: "/tmp/artifacts/last_message.txt",
    agent_log_path: "/tmp/artifacts/agent.log",
    validation_log_path: "/tmp/artifacts/validation.log",
  }
}

///|
test "docker runtime command uses fixed container mounts" {
  let args = docker_command_args(
    test_runtime_config(),
    "/tmp/agent.env",
    "/tmp/workspace",
    "/tmp/home",
    test_run_artifacts(),
    ["claude", "--version"],
  )
  inspect(args.contains("--user"), content="false")
  debug_inspect(args[8], content="\"-v\"")
  debug_inspect(args[9], content="\"/tmp/home:/home/mooncraft\"")
}

///|
async test "process log streaming polls structured child process" {
  let root = "/tmp/mooncraft-async-process-test-" + random_hex(6)
  let log_path = root + "/process.log"
  ensure_dir(root)
  ensure_dir(parent_dir(log_path))
  defer safe_remove_tree(root)
  let exit_code = @async.with_task_group(group => {
    let writer = @process.redirect_to_file(
      log_path,
      create=0o644,
      truncate=true,
    )
    let process = @process.spawn(
      group,
      "sh",
      ["-c", "printf 'first\\n'; sleep 1; printf 'second\\n'"],
      stdout=writer,
      stderr=writer,
      no_wait=true,
    )
    let seen_first = @ref.new(false)
    let seen_second = @ref.new(false)
    let mut status : Int? = None
    while status is None {
      let text = safe_read_string_or(log_path, "")
      if text.contains("first") {
        seen_first.val = true
      }
      if text.contains("second") {
        seen_second.val = true
      }
      let next_status = process.try_wait() catch { _ => None }
      match next_status {
        Some(code) => status = Some(code)
        None => @async.sleep(100)
      }
    }
    assert_true(seen_first.val)
    assert_true(seen_second.val)
    match status {
      Some(code) => code
      None => process.wait()
    }
  })
  inspect(exit_code, content="0")
  inspect(safe_read_string_or(log_path, ""), content="first\nsecond\n")
}
