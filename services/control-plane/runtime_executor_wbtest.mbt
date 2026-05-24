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
async fn path_is_other_writable(path : String) -> Bool {
  let result = match collect_process_text("ls", ["-ld", path]) {
    Ok(result) => result
    Err(_) => return false
  }
  let (exit_code, output) = result
  if exit_code != 0 {
    return false
  }
  let mode = output.split(" ").to_array()[0].to_owned()
  mode.length() >= 9 && mode[8] == 'w'
}

///|
async test "agent home is normalized after auth creates new directories" {
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
  ignore(run_process_quiet("chmod", ["755", codex_home]))
  inspect(path_is_other_writable(codex_home), content="false")
  prepare_agent_mount_path(agent_home_path)
  inspect(path_is_other_writable(codex_home), content="true")
}

///|
async test "process log streaming waits on child process and reads output pipe" {
  let root = "/tmp/mooncraft-async-process-test-" + random_hex(6)
  let log_path = root + "/process.log"
  ensure_dir(root)
  ensure_dir(parent_dir(log_path))
  defer safe_remove_tree(root)
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-stream",
    "user-stream",
    "preview-stream",
    "Stream Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-stream",
    "codex",
    "openrouter/test-model",
    root + "/workspace",
  )
  let run = match store.start_run("project-stream", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let worker = store.next_run_worker_registration("project-stream", run.run_id)
  match
    store.register_run_worker(
      "project-stream",
      run.run_id,
      worker.worker_id,
      worker.attempt,
      1234,
    ) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  let (exit_code, output) = match
    run_streaming_command(
      store,
      root,
      "project-stream",
      run.run_id,
      worker.worker_id,
      worker.attempt,
      log_path,
      "sh",
      [
        "-c", "printf '{\"type\":\"turn.started\"}\\n'; sleep 1; printf '{\"type\":\"turn.completed\"}\\n'",
      ],
    ) {
    Ok(result) => result
    Err(message) => fail(message)
  }
  inspect(exit_code, content="0")
  let expected_output = "{\"type\":\"turn.started\"}\n{\"type\":\"turn.completed\"}\n"
  inspect(output, content=expected_output)
  inspect(safe_read_string_or(log_path, ""), content=expected_output)
  let project = store.get_project_detail("project-stream").unwrap()
  let message_code = match project.activity {
    Some(activity) => activity.message_code
    None => None
  }
  debug_inspect(message_code, content="Some(\"builder_ended\")")
}

///|
async test "runtime timeout watchdog does not own the streaming pipe" {
  let root = "/tmp/mooncraft-watchdog-pipe-test-" + random_hex(6)
  let bin_dir = root + "/bin"
  let stop_file = root + "/fake-docker.stop"
  let log_path = root + "/watchdog.log"
  ensure_dir(bin_dir)
  ensure_dir(parent_dir(log_path))
  defer safe_remove_tree(root)
  safe_write_string(
    bin_dir + "/docker",
    (
      #|#!/bin/sh
      #|if [ "$1" = "run" ]; then
      #|  printf 'docker started\n'
      #|  while [ ! -f "$MOONCRAFT_FAKE_DOCKER_STOP" ]; do
      #|    sleep 1
      #|  done
      #|  printf 'docker stopped\n'
      #|  exit 137
      #|fi
      #|if [ "$1" = "rm" ]; then
      #|  touch "$MOONCRAFT_FAKE_DOCKER_STOP"
      #|  exit 0
      #|fi
      #|exit 2
    ),
  )
  ignore(run_process_quiet("chmod", ["755", bin_dir + "/docker"]))
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-watchdog",
    "user-watchdog",
    "preview-watchdog",
    "Watchdog Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-watchdog",
    "codex",
    "openrouter/test-model",
    root + "/workspace",
  )
  let run = match store.start_run("project-watchdog", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let worker = store.next_run_worker_registration(
    "project-watchdog",
    run.run_id,
  )
  match
    store.register_run_worker(
      "project-watchdog",
      run.run_id,
      worker.worker_id,
      worker.attempt,
      5678,
    ) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  let script = "PATH=" +
    shell_quote(bin_dir) +
    ":$PATH\nexport PATH\nMOONCRAFT_FAKE_DOCKER_STOP=" +
    shell_quote(stop_file) +
    "\nexport MOONCRAFT_FAKE_DOCKER_STOP\n" +
    docker_run_timeout_script(["run"], "fake-container", 1)
  let (exit_code, output) = match
    run_streaming_command(
      store,
      root,
      "project-watchdog",
      run.run_id,
      worker.worker_id,
      worker.attempt,
      log_path,
      "sh",
      ["-c", script],
    ) {
    Ok(result) => result
    Err(message) => fail(message)
  }
  inspect(exit_code, content="137")
  let expected_output = "docker started\n" +
    "docker stopped\n" +
    "MoonCraft builder exceeded the configured runtime limit of 1 seconds; stopping the Runtime container.\n"
  inspect(output, content=expected_output)
  inspect(safe_read_string_or(log_path, ""), content=expected_output)
}
