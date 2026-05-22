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
fn test_runtime_config(container_user : String?) -> AgentRuntimeConfig {
  {
    runtime_id: "agent-runtime-test",
    runtime_name: "Test",
    agent_session_id: "agent-session-test",
    runtime_session_id: None,
    protocol_version: 1,
    image: "runtime:test",
    platform: "linux/arm64",
    agent_cli: "claude_code",
    provider: "openrouter",
    model: "anthropic/claude-sonnet-4.5",
    secrets: [],
    container_home: "/home/mooncraft",
    container_user,
    container_data_dir: "/app/data",
    host_data_dir: None,
    send: ["mooncraft-runtime-send"],
  }
}

///|
fn test_run_artifacts() -> RunArtifacts {
  {
    project_id: "project-test",
    run_id: "run-test",
    dir: "/tmp/artifacts",
    prompt_path: "/tmp/artifacts/prompt.txt",
    runtime_context_path: "/tmp/artifacts/runtime_context.json",
    result_path: "/tmp/artifacts/result.json",
    last_message_path: "/tmp/artifacts/last_message.txt",
    agent_log_path: "/tmp/artifacts/agent.log",
    validation_log_path: "/tmp/artifacts/validation.log",
  }
}

///|
test "docker runtime command honors explicit container user" {
  let args = docker_command_args(
    test_runtime_config(Some("mooncraft")),
    "/tmp/agent.env",
    "/tmp/workspace",
    Some("/tmp/home"),
    test_run_artifacts(),
    ["mooncraft-runtime-send"],
  )
  debug_inspect(args[8], content="\"--user\"")
  debug_inspect(args[9], content="\"mooncraft\"")
  debug_inspect(args[10], content="\"-v\"")
}

///|
test "docker runtime command omits user by default" {
  let args = docker_command_args(
    test_runtime_config(None),
    "/tmp/agent.env",
    "/tmp/workspace",
    Some("/tmp/home"),
    test_run_artifacts(),
    ["mooncraft-runtime-send"],
  )
  debug_inspect(args[8], content="\"-v\"")
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
