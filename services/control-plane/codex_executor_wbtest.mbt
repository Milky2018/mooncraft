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
test "recovery prompt includes original and latest requests" {
  let prompt = recovery_prompt("Build a todo app", "Add labels and due dates")
  assert_true(prompt.contains("Original project requirement"))
  assert_true(prompt.contains("Build a todo app"))
  assert_true(prompt.contains("Latest user request"))
  assert_true(prompt.contains("Add labels and due dates"))
}

///|
test "start_run persists the initial project prompt once" {
  let root = @env.current_dir().unwrap_or(".")
  let db_dir = root + "/data/control-plane-test-dbs"
  ensure_dir(db_dir)
  let db_path = db_dir + "/" + next_id("initial-project-prompt") + ".sqlite"
  safe_remove_tree(db_path)
  safe_remove_tree(db_path + "-shm")
  safe_remove_tree(db_path + "-wal")
  let store = Store::new(db_path)
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
  safe_remove_tree(db_path)
  safe_remove_tree(db_path + "-shm")
  safe_remove_tree(db_path + "-wal")
}

///|
test "workspace snapshot round-trips project files and excludes build outputs" {
  let root = @env.current_dir().unwrap_or(".")
  let project_id = next_id("snapshot-roundtrip")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path + "/frontend")
  ensure_dir(workspace_path + "/_build/cache")
  safe_write_string(workspace_path + "/frontend/main.mbt", "first version\n")
  safe_write_string(workspace_path + "/_build/cache/output.txt", "generated\n")

  snapshot_workspace(root, project_id, workspace_path).unwrap()
  safe_write_string(workspace_path + "/frontend/main.mbt", "second version\n")
  restore_workspace_snapshot(root, project_id, workspace_path).unwrap()

  inspect(
    safe_read_string_or(workspace_path + "/frontend/main.mbt", ""),
    content="first version\n",
  )
  inspect(
    @fs.path_exists(workspace_path + "/_build/cache/output.txt"),
    content="false",
  )
  safe_remove_tree(project_root(root, project_id))
}

///|
test "restoring a project without a snapshot snapshots the existing workspace" {
  let root = @env.current_dir().unwrap_or(".")
  let project_id = next_id("snapshot-migration")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path)
  safe_write_string(workspace_path + "/README.md", "persist me\n")

  restore_workspace_snapshot(root, project_id, workspace_path).unwrap()

  inspect(
    @fs.path_exists(project_workspace_snapshot_path(root, project_id)),
    content="true",
  )
  inspect(
    safe_read_string_or(workspace_path + "/README.md", ""),
    content="persist me\n",
  )
  safe_remove_tree(project_root(root, project_id))
}

///|
test "hydrate run workspace restores the saved snapshot into an isolated path" {
  let root = @env.current_dir().unwrap_or(".")
  let project_id = next_id("snapshot-hydrate")
  let run_id = next_id("run")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path)
  safe_write_string(workspace_path + "/README.md", "from snapshot\n")
  snapshot_workspace(root, project_id, workspace_path).unwrap()
  safe_write_string(workspace_path + "/README.md", "changed cache\n")

  let run_workspace_path = hydrate_run_workspace(root, project_id, run_id).unwrap()

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
}

///|
test "hydrate run workspace snapshots the canonical workspace for older projects" {
  let root = @env.current_dir().unwrap_or(".")
  let project_id = next_id("snapshot-hydrate-migration")
  let run_id = next_id("run")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path)
  safe_write_string(workspace_path + "/README.md", "legacy workspace\n")

  let run_workspace_path = hydrate_run_workspace(root, project_id, run_id).unwrap()

  inspect(
    @fs.path_exists(project_workspace_snapshot_path(root, project_id)),
    content="true",
  )
  inspect(
    safe_read_string_or(run_workspace_path + "/README.md", ""),
    content="legacy workspace\n",
  )
  remove_run_workspace(root, project_id, run_id)
  safe_remove_tree(project_root(root, project_id))
}
