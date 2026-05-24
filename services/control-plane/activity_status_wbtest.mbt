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

///|
async test "registered dead worker is recovered without blocking retry" {
  let root = "/tmp/mooncraft-dead-worker-recovery-test-" + random_hex(6)
  ensure_dir(root)
  defer safe_remove_tree(root)
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-dead-worker",
    "user-dead-worker",
    "preview-dead-worker",
    "Dead Worker Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-dead-worker",
    "codex",
    "openrouter/test-model",
    root + "/workspace",
  )
  let run = match store.start_run("project-dead-worker", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  match store.set_run_worker_pid("project-dead-worker", run.run_id, 99999999) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  let recovered = store.get_run("project-dead-worker", run.run_id).unwrap()
  debug_inspect(recovered.state, content="Failed")
  debug_inspect(recovered.phase, content="NoPhase")
  let project = store.get_project_detail("project-dead-worker").unwrap()
  debug_inspect(project.is_processing, content="false")
  debug_inspect(project.current_run_id, content="None")
  let retry = match store.start_run("project-dead-worker", "Try again") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  debug_inspect(retry.state, content="Running")
}

///|
async test "start run rolls back partial writes when project update fails" {
  let root = "/tmp/mooncraft-start-run-rollback-test-" + random_hex(6)
  ensure_dir(root)
  defer safe_remove_tree(root)
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-start-rollback",
    "user-start-rollback",
    "preview-start-rollback",
    "Start Rollback Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-start-rollback",
    "codex",
    "openrouter/test-model",
    root + "/workspace",
  )
  match
    store.exec_or_error(
      (
        #|CREATE TRIGGER fail_start_run_project_update
        #|BEFORE UPDATE OF current_run_id ON projects
        #|BEGIN
        #|  SELECT RAISE(FAIL, 'blocked project update');
        #|END;
      ),
      "install start run rollback trigger",
    ) {
    Ok(_) => ignore(())
    Err(message) => abort(message)
  }
  match store.start_run("project-start-rollback", "Build something") {
    Ok(_) => fail("Expected start_run to fail when project update fails.")
    Err(_) => ignore(())
  }
  inspect(store.list_messages("project-start-rollback").length(), content="0")
  inspect(
    store.list_project_runs("project-start-rollback", 10).length(),
    content="0",
  )
  let project = store.get_project_detail("project-start-rollback").unwrap()
  debug_inspect(project.is_processing, content="false")
  debug_inspect(project.current_run_id, content="None")
}
