///|
async test "starting a run sets activity without replacing final project status" {
  let root = "/tmp/mooncraft-activity-status-test-" + random_hex(6)
  ensure_dir(root)
  defer safe_remove_tree(root)
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-activity",
    "user-activity",
    "preview-activity",
    "Activity Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-activity",
    "codex",
    "openrouter/test-model",
    root + "/workspace",
  )
  let run = match store.start_run("project-activity", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  debug_inspect(run.state, content="Running")
  let project = store.get_project_detail("project-activity").unwrap()
  debug_inspect(project.status, content="Idle")
  debug_inspect(project.is_processing, content="true")
  debug_inspect(
    project.activity.map(fn(activity) { activity.run_id }),
    content="Some(\"" + run.run_id + "\")",
  )
  store.append_run_event(
    "project-activity",
    run.run_id,
    "status",
    @sdk.run_event_code_turn_planning(),
    "Planning the change.",
  )
  let updated = store.get_project_detail("project-activity").unwrap()
  let message_code = match updated.activity {
    Some(activity) => activity.message_code
    None => None
  }
  debug_inspect(message_code, content="Some(\"turn_planning\")")
}

///|
async test "reading a new run does not recover it before worker registration" {
  let root = "/tmp/mooncraft-run-read-test-" + random_hex(6)
  ensure_dir(root)
  defer safe_remove_tree(root)
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-run-read",
    "user-run-read",
    "preview-run-read",
    "Run Read Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-run-read",
    "codex",
    "openrouter/test-model",
    root + "/workspace",
  )
  let run = match store.start_run("project-run-read", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let fetched = store.get_run("project-run-read", run.run_id).unwrap()
  debug_inspect(fetched.state, content="Running")
  let recent_runs = store.list_recent_runs(10)
  inspect(recent_runs.length(), content="1")
  debug_inspect(recent_runs[0].state, content="Running")
  let project_runs = store.list_project_runs("project-run-read", 10)
  inspect(project_runs.length(), content="1")
  debug_inspect(project_runs[0].state, content="Running")
  let project = store.get_project_detail("project-run-read").unwrap()
  debug_inspect(project.is_processing, content="true")
}

///|
async test "worker pid registration must target an active run" {
  let root = "/tmp/mooncraft-worker-pid-test-" + random_hex(6)
  ensure_dir(root)
  defer safe_remove_tree(root)
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-worker-pid",
    "user-worker-pid",
    "preview-worker-pid",
    "Worker Pid Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-worker-pid",
    "codex",
    "openrouter/test-model",
    root + "/workspace",
  )
  let run = match store.start_run("project-worker-pid", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  match store.set_run_worker_pid("project-worker-pid", run.run_id, 1234) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  let worker = store
    .get_running_run_worker("project-worker-pid", run.run_id)
    .unwrap()
  inspect(worker.worker_pid, content="1234")
  store.finish_run_failure(
    "project-worker-pid",
    run.run_id,
    "Stopped",
    "Stopped for test.",
    None,
  )
  match store.set_run_worker_pid("project-worker-pid", run.run_id, 5678) {
    Ok(_) => fail("Expected worker pid registration to reject a finished run.")
    Err(message) =>
      inspect(
        message,
        content="The run is no longer active while registering its worker.",
      )
  }
}
