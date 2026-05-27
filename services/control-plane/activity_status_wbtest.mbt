///|
async test "starting a run sets activity without replacing final project status" {
  let root = "/tmp/mooncraft-activity-status-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
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
    "\{root}/workspace",
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
    content="Some(\"\{run.run_id}\")",
  )
  let worker = store.next_run_worker_registration(
    "project-activity",
    run.run_id,
  )
  match
    store.register_run_worker(
      "project-activity",
      run.run_id,
      worker.worker_id,
      worker.attempt,
      1234,
    ) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  store.append_worker_run_event(
    "project-activity",
    run.run_id,
    worker.worker_id,
    worker.attempt,
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
  let root = "/tmp/mooncraft-run-read-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
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
    "\{root}/workspace",
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
  let root = "/tmp/mooncraft-worker-pid-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
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
    "\{root}/workspace",
  )
  let run = match store.start_run("project-worker-pid", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let registration = store.next_run_worker_registration(
    "project-worker-pid",
    run.run_id,
  )
  match
    store.register_run_worker(
      "project-worker-pid",
      run.run_id,
      registration.worker_id,
      registration.attempt,
      1234,
    ) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  let worker = store
    .get_running_run_worker("project-worker-pid", run.run_id)
    .unwrap()
  inspect(worker.worker_id, content=registration.worker_id)
  inspect(worker.attempt, content="1")
  inspect(worker.worker_pid, content="1234")
  store.finish_run_failure(
    "project-worker-pid",
    run.run_id,
    "Stopped",
    "Stopped for test.",
    None,
  )
  let rejected = store.next_run_worker_registration(
    "project-worker-pid",
    run.run_id,
  )
  match
    store.register_run_worker(
      "project-worker-pid",
      run.run_id,
      rejected.worker_id,
      rejected.attempt,
      5678,
    ) {
    Ok(_) => fail("Expected worker pid registration to reject a finished run.")
    Err(message) =>
      inspect(
        message,
        content="The run is no longer active while registering its worker.",
      )
  }
}

///|
async test "reading a registered run does not recover dead worker pids" {
  let root = "/tmp/mooncraft-read-pure-run-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-read-pure",
    "user-read-pure",
    "preview-read-pure",
    "Read Pure Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-read-pure",
    "codex",
    "openrouter/test-model",
    "\{root}/workspace",
  )
  let run = match store.start_run("project-read-pure", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let registration = store.next_run_worker_registration(
    "project-read-pure",
    run.run_id,
  )
  match
    store.register_run_worker(
      "project-read-pure",
      run.run_id,
      registration.worker_id,
      registration.attempt,
      99999999,
    ) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  let fetched = store.get_run("project-read-pure", run.run_id).unwrap()
  debug_inspect(fetched.state, content="Running")
  let project = store.get_project_detail("project-read-pure").unwrap()
  debug_inspect(project.is_processing, content="true")
  debug_inspect(project.current_run_id, content="Some(\"\{run.run_id}\")")
}

///|
async test "reconciler expires stale worker leases outside read paths" {
  @env.set_env_var("MOONCRAFT_RUN_WORKER_STARTUP_GRACE_MS", "0")
  @env.set_env_var("MOONCRAFT_RUN_WORKER_HEARTBEAT_TTL_MS", "0")
  defer @env.unset_env_var("MOONCRAFT_RUN_WORKER_STARTUP_GRACE_MS")
  defer @env.unset_env_var("MOONCRAFT_RUN_WORKER_HEARTBEAT_TTL_MS")
  let root = "/tmp/mooncraft-worker-reconcile-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-worker-reconcile",
    "user-worker-reconcile",
    "preview-worker-reconcile",
    "Worker Reconcile Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-worker-reconcile",
    "codex",
    "openrouter/test-model",
    "\{root}/workspace",
  )
  let run = match
    store.start_run("project-worker-reconcile", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let worker = store.next_run_worker_registration(
    "project-worker-reconcile",
    run.run_id,
  )
  match
    store.register_run_worker(
      "project-worker-reconcile",
      run.run_id,
      worker.worker_id,
      worker.attempt,
      99999999,
    ) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  let before = store.get_run("project-worker-reconcile", run.run_id).unwrap()
  debug_inspect(before.state, content="Running")
  inspect(store.reconcile_expired_run_workers(), content="1")
  let after = store.get_run("project-worker-reconcile", run.run_id).unwrap()
  debug_inspect(after.state, content="Failed")
  let project = store.get_project_detail("project-worker-reconcile").unwrap()
  debug_inspect(project.is_processing, content="false")
  debug_inspect(project.current_run_id, content="None")
  inspect(store.list_messages("project-worker-reconcile").length(), content="2")
}

///|
async test "expired worker cannot overwrite recovered run success" {
  @env.set_env_var("MOONCRAFT_RUN_WORKER_STARTUP_GRACE_MS", "0")
  @env.set_env_var("MOONCRAFT_RUN_WORKER_HEARTBEAT_TTL_MS", "0")
  defer @env.unset_env_var("MOONCRAFT_RUN_WORKER_STARTUP_GRACE_MS")
  defer @env.unset_env_var("MOONCRAFT_RUN_WORKER_HEARTBEAT_TTL_MS")
  let root = "/tmp/mooncraft-worker-cas-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let _ = store.create_project_with_runtime(
    "project-worker-cas",
    "user-worker-cas",
    "preview-worker-cas",
    "Worker CAS Project",
    "agent-runtime-001",
    "Runtime",
    "{}",
    "agent-session-worker-cas",
    "codex",
    "openrouter/test-model",
    "\{root}/workspace",
  )
  let run = match store.start_run("project-worker-cas", "Build something") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let worker = store.next_run_worker_registration(
    "project-worker-cas",
    run.run_id,
  )
  match
    store.register_run_worker(
      "project-worker-cas",
      run.run_id,
      worker.worker_id,
      worker.attempt,
      1234,
    ) {
    Ok(_) => ignore(())
    Err(message) => fail(message)
  }
  inspect(store.reconcile_expired_run_workers(), content="1")
  store.finish_run_success_for_worker(
    "project-worker-cas",
    run.run_id,
    worker.worker_id,
    worker.attempt,
    "Late success",
    Some("late-session"),
    { url: "/p/late/", port: 4300, healthy: true },
  )
  let after = store.get_run("project-worker-cas", run.run_id).unwrap()
  debug_inspect(after.state, content="Failed")
  inspect(store.list_messages("project-worker-cas").length(), content="2")
}

///|
async test "start run rolls back partial writes when project update fails" {
  let root = "/tmp/mooncraft-start-run-rollback-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
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
    "\{root}/workspace",
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
  if store.start_run("project-start-rollback", "Build something") is Ok(_) {
    fail("Expected start_run to fail when project update fails.")
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
