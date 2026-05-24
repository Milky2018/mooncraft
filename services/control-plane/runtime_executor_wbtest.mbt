///|
test "preview audit targets private preview port" {
  let preview : @sdk.PreviewTarget = {
    url: "/p/public-preview-id/",
    port: 4792,
    healthy: true,
  }
  debug_inspect(
    preview_audit_target_url(preview),
    content="\"http://127.0.0.1:4792/\"",
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
    Some(event) => {
      inspect(event.kind, content="status")
      inspect(event.code, content="builder_started")
      inspect(event.content, content="Started the builder session.")
    }
    None => fail("expected claude init event")
  }
  match
    runtime_display_event(
      (
        #|{"type":"result","subtype":"success","is_error":false}
      ),
    ) {
    Some(event) => {
      inspect(event.kind, content="status")
      inspect(event.code, content="builder_ended")
      inspect(event.content, content="Builder session ended.")
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
    Some(event) => {
      inspect(event.kind, content="activity")
      inspect(event.code, content="activity_message")
      inspect(
        event.content,
        content="Now I have a clear picture of the template.",
      )
    }
    None => fail("expected claude assistant progress")
  }
  match
    runtime_display_event(
      (
        #|{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"description":"Check available MoonCraft templates","command":"cat /opt/mooncraft/templates/catalog.json"}}]}}
      ),
    ) {
    Some(event) => {
      inspect(event.kind, content="activity")
      inspect(event.code, content="activity_tool_running")
      inspect(event.content, content="Check available MoonCraft templates")
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
    Some(event) => {
      inspect(event.kind, content="activity")
      inspect(event.code, content="activity_message")
      inspect(event.content, content="Escaped \"quote\" progress")
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
    Some(event) => {
      inspect(event.kind, content="activity")
      inspect(event.code, content="activity_tool_error")
      inspect(
        event.content,
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
fn path_is_other_writable(path : String) -> Bool {
  shell_status(
    "mode=$(ls -ld " +
    shell_quote(path) +
    " | awk '{print $1}'); case \"$mode\" in ????????w*) exit 0;; *) exit 1;; esac",
  ) ==
  0
}

///|
test "agent home is normalized after auth creates new directories" {
  let root = "/tmp/mooncraft-agent-home-perm-test-" + random_hex(6)
  let agent_home_path = root + "/home"
  ensure_dir(agent_home_path)
  defer safe_remove_tree(root)
  prepare_agent_mount_path(agent_home_path)
  let config = {
    ..test_runtime_config(),
    auth_kind: "codex_auth_json",
    secret: { env: None, file: Some(".codex/auth.json"), value: "{}" },
  }
  match materialize_runtime_file_secrets(config, agent_home_path) {
    Ok(_) => ()
    Err(message) => fail(message)
  }
  let codex_home = agent_home_path + "/.codex"
  // Simulate a host-created auth directory that is not writable by the
  // container's non-root runtime user on a Linux bind mount.
  ignore(shell_status("chmod 755 " + shell_quote(codex_home)))
  inspect(path_is_other_writable(codex_home), content="false")
  prepare_agent_mount_path(agent_home_path)
  inspect(path_is_other_writable(codex_home), content="true")
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
