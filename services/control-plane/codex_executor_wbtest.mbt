///|
test "bootstrap prompt includes the core execution rules" {
  let prompt = bootstrap_prompt("Build a todo app")
  assert_true(
    prompt.contains(
      "Default to MoonBit unless the user explicitly asks for another technology.",
    ),
  )
  assert_true(
    prompt.contains(
      "Use subagents only for concrete, bounded implementation tasks.",
    ),
  )
  assert_true(prompt.contains("moon fmt"))
  assert_true(prompt.contains("Build a todo app"))
}

///|
test "extract thread id from codex json event" {
  let events = "{\"type\":\"thread.started\",\"thread_id\":\"019db86f-4b45-75c3-a409-984993d1f897\"}\n{\"type\":\"turn.started\"}"
  inspect(
    extract_thread_id(events),
    content="Some(\"019db86f-4b45-75c3-a409-984993d1f897\")",
  )
}

///|
test "resume session missing detection matches codex cli error" {
  inspect(
    resume_session_missing(
      "Error: thread/resume: thread/resume failed: no rollout found for thread id 00000000-0000-0000-0000-000000000000",
    ),
    content="true",
  )
}

///|
test "codex commands pin the configured model" {
  let exec_command = codex_exec_command("gpt-5.4", "Build a todo app")
  inspect(exec_command[2], content="--model")
  inspect(exec_command[3], content="gpt-5.4")
  let resume_command = codex_resume_command(
    "gpt-5.4", "local-thread", "Add labels",
  )
  assert_true(codex_command_is_resume(resume_command))
  inspect(resume_command[3], content="--model")
  inspect(resume_command[4], content="gpt-5.4")
}

///|
test "recovery prompt includes original and latest requests" {
  let prompt = recovery_prompt("Build a todo app", "Add labels and due dates")
  assert_true(prompt.contains("Original project requirement"))
  assert_true(prompt.contains("Build a todo app"))
  assert_true(prompt.contains("Latest user request"))
  assert_true(prompt.contains("Add labels and due dates"))
}

///|
fn cleanup_test_db(db_path : String) -> Unit {
  safe_remove_tree(db_path)
  safe_remove_tree(db_path + "-shm")
  safe_remove_tree(db_path + "-wal")
}

///|
fn new_test_store(root : String, prefix : String) -> (Store, String) {
  let db_dir = root + "/data/control-plane-test-dbs"
  ensure_dir(db_dir)
  let db_path = db_dir + "/" + next_id(prefix) + ".sqlite"
  cleanup_test_db(db_path)
  (Store::try_new(db_path).unwrap(), db_path)
}

///|
test "store reports database open failures" {
  let root = @env.current_dir().unwrap_or(".")
  let db_dir = root + "/data/control-plane-test-dbs"
  ensure_dir(db_dir)
  let db_path = db_dir + "/" + next_id("db-open-failure")
  safe_remove_tree(db_path)
  ensure_dir(db_path)

  let result = Store::try_new(db_path)

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  safe_remove_tree(db_path)
}

///|
test "app context cleans legacy project workspaces at startup" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/control-plane-test-roots/" +
    next_id("legacy-cleanup")
  let legacy_root = legacy_project_workspaces_root(root)
  safe_remove_tree(root)
  ensure_dir(legacy_root + "/project-legacy/workspace")
  safe_write_string(
    legacy_root + "/project-legacy/workspace/README.md",
    "legacy\n",
  )

  let result = AppContext::try_new_with_recovery(root, false)

  inspect(
    match result {
      Ok(_) => @fs.path_exists(legacy_root)
      Err(_) => true
    },
    content="false",
  )
  safe_remove_tree(root)
}

///|
test "start_run persists the initial project prompt once" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "initial-project-prompt")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      Some("Prompt Test"),
      project_workspace(root, project_id),
      default_template_id(),
      default_template_version(),
    ),
  )

  inspect(store.get_initial_project_prompt(project_id), content="None")
  let first_run = store.start_run(project_id, "Build a todo app").unwrap()
  inspect(
    store.get_initial_project_prompt(project_id),
    content="Some(\"Build a todo app\")",
  )
  store.finish_run_failure(
    project_id,
    first_run.run_id,
    "first failed",
    "first failed",
    None,
  )
  let second_run = store.start_run(project_id, "Add labels").unwrap()
  let _ = second_run
  inspect(
    store.get_initial_project_prompt(project_id),
    content="Some(\"Build a todo app\")",
  )
  cleanup_test_db(db_path)
}

///|
test "run events append and list after sequence" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "run-events")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      Some("Events Test"),
      project_workspace(root, project_id),
      default_template_id(),
      default_template_version(),
    ),
  )
  let run = store.start_run(project_id, "Build a todo app").unwrap()

  store.append_run_event(
    project_id,
    run.run_id,
    "status",
    "Starting Codex CLI.",
  )
  store.append_run_event(
    project_id,
    run.run_id,
    "codex",
    "{\"type\":\"turn.started\"}",
  )
  let first_page = store.list_run_events(project_id, run.run_id, 0)
  inspect(first_page.length(), content="2")
  inspect(first_page[0].seq, content="1")
  inspect(first_page[1].kind, content="codex")
  let second_page = store.list_run_events(project_id, run.run_id, 1)
  inspect(second_page.length(), content="1")
  inspect(second_page[0].content, content="{\"type\":\"turn.started\"}")
  cleanup_test_db(db_path)
}

///|
test "startup recovery makes stale running runs retryable" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "stale-running-run")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      Some("Recovery Test"),
      project_workspace(root, project_id),
      default_template_id(),
      default_template_version(),
    ),
  )
  let stale_run = store.start_run(project_id, "Build a todo app").unwrap()

  inspect(store.fail_stale_running_runs_on_startup(), content="1")
  let recovered_run = store.get_run(project_id, stale_run.run_id).unwrap()
  inspect(recovered_run.state == @sdk.Failed, content="true")
  inspect(
    recovered_run.summary,
    content="Some(\"The previous worker was interrupted before it could finish. Send another message to retry this project.\")",
  )
  inspect(
    recovered_run.failure_debug.map(fn(debug) { debug.stage }),
    content="Some(\"Worker recovery\")",
  )
  let project = store.get_project_detail(project_id).unwrap()
  inspect(project.status == @sdk.Failed, content="true")
  inspect(project.current_run_id, content="None")
  let retry_run = store.start_run(project_id, "Retry the app")
  inspect(
    match retry_run {
      Ok(_) => true
      Err(_) => false
    },
    content="true",
  )
  cleanup_test_db(db_path)
}

///|
test "workspace snapshot round-trips project files and excludes build outputs" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-roundtrip-db")
  let project_id = next_id("snapshot-roundtrip")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path + "/frontend")
  ensure_dir(workspace_path + "/_build/cache")
  safe_write_string(workspace_path + "/frontend/main.mbt", "first version\n")
  safe_write_string(workspace_path + "/_build/cache/output.txt", "generated\n")

  snapshot_workspace(store, root, project_id, workspace_path).unwrap()
  safe_write_string(workspace_path + "/frontend/main.mbt", "second version\n")
  restore_workspace_snapshot(store, root, project_id, workspace_path).unwrap()

  inspect(store.get_workspace_snapshot(project_id) is Some(_), content="true")
  inspect(
    safe_read_string_or(workspace_path + "/frontend/main.mbt", ""),
    content="first version\n",
  )
  inspect(
    @fs.path_exists(workspace_path + "/_build/cache/output.txt"),
    content="false",
  )
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
test "restore without a database snapshot fails without legacy fallback" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-migration-db")
  let project_id = next_id("snapshot-migration")
  let workspace_path = project_workspace(root, project_id)
  let legacy_root = legacy_project_workspaces_root(root) + "/" + project_id
  safe_remove_tree(project_root(root, project_id))
  safe_remove_tree(legacy_root)
  ensure_dir(legacy_root)
  safe_write_string(legacy_root + "/README.md", "legacy\n")

  let result = restore_workspace_snapshot(
    store, root, project_id, workspace_path,
  )

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  inspect(@fs.path_exists(legacy_root), content="true")
  safe_remove_tree(legacy_root)
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
test "hydrate run workspace restores the saved snapshot into an isolated path" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-hydrate-db")
  let project_id = next_id("snapshot-hydrate")
  let run_id = next_id("run")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path)
  safe_write_string(workspace_path + "/README.md", "from snapshot\n")
  snapshot_workspace(store, root, project_id, workspace_path).unwrap()
  safe_write_string(workspace_path + "/README.md", "changed cache\n")

  let run_workspace_path = hydrate_run_workspace(
    store, root, project_id, run_id,
  ).unwrap()

  inspect(run_workspace_path == workspace_path, content="false")
  inspect(
    safe_read_string_or(run_workspace_path + "/README.md", ""),
    content="from snapshot\n",
  )
  inspect(
    safe_read_string_or(workspace_path + "/README.md", ""),
    content="changed cache\n",
  )
  remove_run_workspace(root, project_id, run_id)
  inspect(@fs.path_exists(run_workspace_path), content="false")
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
test "hydrate without a database snapshot fails without legacy fallback" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-hydrate-legacy-db")
  let project_id = next_id("snapshot-hydrate-legacy")
  let run_id = next_id("run")
  let legacy_root = legacy_project_workspaces_root(root) + "/" + project_id
  safe_remove_tree(project_root(root, project_id))
  safe_remove_tree(legacy_root)
  ensure_dir(legacy_root)
  safe_write_string(legacy_root + "/README.md", "legacy\n")

  let result = hydrate_run_workspace(store, root, project_id, run_id)

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  inspect(@fs.path_exists(legacy_root), content="true")
  inspect(
    @fs.path_exists(project_run_workspace_path(root, project_id, run_id)),
    content="false",
  )
  safe_remove_tree(legacy_root)
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
test "hydrate requires a database snapshot" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-hydrate-migration-db")
  let project_id = next_id("snapshot-hydrate-migration")
  let run_id = next_id("run")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path)
  safe_write_string(workspace_path + "/README.md", "local cache only\n")

  let result = hydrate_run_workspace(store, root, project_id, run_id)

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  inspect(store.get_workspace_snapshot(project_id) is Some(_), content="false")
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}
