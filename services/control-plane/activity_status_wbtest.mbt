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
