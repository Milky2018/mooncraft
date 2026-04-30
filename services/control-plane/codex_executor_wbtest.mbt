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
  debug_inspect(
    extract_thread_id(events),
    content="Some(\"019db86f-4b45-75c3-a409-984993d1f897\")",
  )
}

///|
test "fake codex extracts only the user request from wrapped prompts" {
  let bootstrap = bootstrap_prompt("Build a todo app")
  inspect(fake_codex_user_request(bootstrap), content="Build a todo app")
  assert_false(fake_codex_user_request(bootstrap).contains("Working rules"))
  let followup = followup_prompt("Add labels and due dates")
  inspect(fake_codex_user_request(followup), content="Add labels and due dates")
  let recovery = recovery_prompt("Build a todo app", "Add labels and due dates")
  inspect(fake_codex_user_request(recovery), content="Add labels and due dates")
}

///|
test "success summary copy is shared across run completion paths" {
  inspect(
    default_success_summary(),
    content="The app is updated and the preview is ready.",
  )
  inspect(
    successful_preview_assistant_message(),
    content="The app is updated and the preview is ready.",
  )
}

///|
test "fake codex forced failure is disabled unless configured" {
  debug_inspect(fake_codex_forced_failure("Force fake failure"), content="None")
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
  let exec_command = codex_exec_command("gpt-5.5", "Build a todo app")
  inspect(exec_command[2], content="--model")
  inspect(exec_command[3], content="gpt-5.5")
  let resume_command = codex_resume_command(
    "gpt-5.5", "local-thread", "Add labels",
  )
  assert_true(codex_command_is_resume(resume_command))
  inspect(resume_command[3], content="--model")
  inspect(resume_command[4], content="gpt-5.5")
}

///|
test "docker validation uses initialized image registry in one shell" {
  let script = validation_shell_script(include_update=false)
  assert_true(script.has_prefix("set -e"))
  assert_true(required_user_project_fetches().length() > 0)
  for module_name in required_user_project_fetches() {
    assert_true(script.contains("moon fetch --no-update " + module_name))
  }
  assert_true(script.contains("moon fmt"))
  assert_true(script.contains("moon check"))
  assert_true(script.contains("moon build"))
  assert_true(script.contains("moon test"))
}

///|
test "docker codex command fetches reference modules before codex starts" {
  let command = docker_codex_entry_command(["codex", "exec", "Build an app"])
  inspect(command[0], content="sh")
  inspect(command[1], content="-lc")
  assert_true(required_user_project_fetches().length() > 0)
  for module_name in required_user_project_fetches() {
    assert_true(command[2].contains("moon fetch --no-update " + module_name))
  }
  assert_true(command[2].contains("exec \"$@\""))
  inspect(command[3], content="mooncraft-codex")
  inspect(command[4], content="codex")
  inspect(command[5], content="exec")
}

///|
test "reference module versions come from the single config file" {
  let mocket_version = required_reference_module_version("oboard/mocket")
  let x_version = required_reference_module_version("moonbitlang/x")
  assert_true(mocket_version.length() > 0)
  assert_true(x_version.length() > 0)
  assert_true(
    required_user_project_fetches().contains("oboard/mocket@" + mocket_version),
  )
  assert_true(
    required_user_project_fetches().contains("moonbitlang/x@" + x_version),
  )
}

///|
test "mooncakes tls failures get a user friendly assistant message" {
  let output =
    #|Error: error sending request for url (https://download.mooncakes.io/user/oboard%2Fmocket%2Fpackage.zip)
    #|
    #|Caused by:
    #|    0: client error (Connect)
    #|    1: tls handshake eof
  assert_true(moonbit_registry_fetch_failed(output))
  assert_true(
    dependency_fetch_failure_assistant_message(output, "fallback").contains(
      "temporary network or package-registry issue",
    ),
  )
}

///|
test "github oauth helpers build pkce authorization url" {
  let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  let url = github_authorization_url(
    "client-id", "http://localhost:3000/auth/github/callback", "state value", verifier,
  )
  assert_true(url.has_prefix("https://github.com/login/oauth/authorize?"))
  assert_true(url.contains("response_type=code"))
  assert_true(url.contains("client_id=client-id"))
  assert_true(
    url.contains(
      "redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Fgithub%2Fcallback",
    ),
  )
  assert_true(url.contains("scope=read%3Auser%20user%3Aemail"))
  assert_true(url.contains("state=state%20value"))
  assert_true(
    url.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"),
  )
  assert_true(url.contains("code_challenge_method=S256"))
}

///|
test "github oauth helpers build token request and parse access token" {
  let body = github_token_request_body(
    "client-id", "client secret", "code value", "http://localhost:3000/auth/github/callback",
    "verifier value",
  )
  assert_true(body.contains("grant_type=authorization_code"))
  assert_true(body.contains("client_id=client-id"))
  assert_true(body.contains("client_secret=client%20secret"))
  assert_true(body.contains("code=code%20value"))
  assert_true(
    body.contains(
      "redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Fgithub%2Fcallback",
    ),
  )
  assert_true(body.contains("code_verifier=verifier%20value"))
  inspect(
    github_access_token_from_response(
      "{\"access_token\":\"token-123\",\"token_type\":\"bearer\"}",
    ),
    content="Ok(\"token-123\")",
  )
  assert_true(github_access_token_from_response("{}") is Err(_))
}

///|
test "docker command receives user scoped AI settings" {
  let config : CodexDockerConfig = {
    image: "codex:test",
    provider: "openrouter",
    model: "openai/gpt-5.5",
    api_key: "user-key",
    container_home: "/root",
  }
  let artifacts : RunArtifacts = {
    dir: "/tmp/artifacts",
    last_message_path: "/tmp/artifacts/last_message.txt",
    codex_log_path: "/tmp/artifacts/codex.log",
    validation_log_path: "/tmp/artifacts/validation.log",
  }
  let args = docker_command_args(
    config,
    "/tmp/workspace",
    Some("/tmp/mooncraft-codex-home"),
    artifacts,
    ["codex", "exec", "Build an app"],
  )
  assert_true(args.contains("MOONCRAFT_AI_PROVIDER=openrouter"))
  assert_true(args.contains("MOONCRAFT_AI_MODEL=openai/gpt-5.5"))
  assert_true(args.contains("MOONCRAFT_AI_API_KEY=user-key"))
  assert_true(args.contains("CODEX_HOME=/root/.codex"))
  assert_true(args.contains("/tmp/mooncraft-codex-home:/root/.codex"))
  assert_false(args.contains("OPENAI_API_KEY"))
}

///|
test "project Codex home is platform managed and outside the runtime workspace cache" {
  let root = "/tmp/mooncraft-root"
  let project_id = "project-123"
  inspect(
    project_codex_home(root, project_id),
    content="/tmp/mooncraft-root/data/codex-sessions/project-123/.codex",
  )
  assert_false(
    project_codex_home(root, project_id).contains("/runtime/projects/"),
  )
  assert_false(project_codex_home(root, project_id).contains("/workspace"))
}

///|
async test "delete project removes the persisted Codex home" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/control-plane-test-roots/" +
    next_id("codex-home-delete")
  safe_remove_tree(root)
  let db_path = root + "/data/control-plane/state-v2.sqlite"
  ensure_dir(parent_dir(db_path))
  let store = Store::try_new_async(db_path).unwrap()
  let ctx = AppContext::{
    root,
    build_profile: Debug,
    store,
    previews: PreviewManager::new(root, Debug),
    agent_gateway: AgentGateway::new(root),
  }
  let project_id = next_id("project")
  ignore(
    ctx.store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      Some("Codex Home Delete Test"),
      project_workspace(root, project_id),
    ),
  )
  let codex_home = project_codex_home(root, project_id)
  ensure_dir(codex_home)
  safe_write_string(codex_home + "/state.json", "{}")

  inspect(@fs.path_exists(codex_home + "/state.json"), content="true")
  ctx.delete_project(project_id).unwrap()
  inspect(
    @fs.path_exists(project_codex_session_root(root, project_id)),
    content="false",
  )
  safe_remove_tree(root)
}

///|
test "codex display events hide protocol noise" {
  debug_inspect(
    codex_display_event("Reading additional input from stdin..."),
    content="None",
  )
  debug_inspect(
    codex_display_event(
      "2026-04-27T07:31:22Z ERROR codex_core_skills::manager: failed to install system skills",
    ),
    content="None",
  )
  debug_inspect(
    codex_display_event(
      "{\"type\":\"thread.started\",\"thread_id\":\"local-thread\"}",
    ),
    content="Some((\"status\", \"Started Codex session.\"))",
  )
  debug_inspect(
    codex_display_event("{\"type\":\"turn.started\"}"),
    content="Some((\"status\", \"Planning the change.\"))",
  )
  debug_inspect(
    codex_display_event(
      "{\"type\":\"item.started\",\"item\":{\"type\":\"command_execution\",\"command\":\"/bin/bash -lc 'moon check'\",\"status\":\"in_progress\"}}",
    ),
    content="Some((\"status\", \"Checking the workspace.\"))",
  )
  debug_inspect(
    codex_display_event(
      "{\"type\":\"item.completed\",\"item\":{\"type\":\"file_change\",\"status\":\"completed\"}}",
    ),
    content="Some((\"status\", \"Updated project files.\"))",
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
fn cleanup_test_db(db_path : String) -> Unit {
  safe_remove_tree(db_path)
  safe_remove_tree(db_path + "-shm")
  safe_remove_tree(db_path + "-wal")
}

///|
async fn new_test_store(root : String, prefix : String) -> (Store, String) {
  let db_dir = root + "/data/control-plane-test-dbs"
  ensure_dir(db_dir)
  let db_path = db_dir + "/" + next_id(prefix) + ".sqlite"
  cleanup_test_db(db_path)
  (Store::try_new_async(db_path).unwrap(), db_path)
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
async test "start_run persists the initial project prompt once" {
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
    ),
  )

  debug_inspect(store.get_initial_project_prompt(project_id), content="None")
  let first_run = store.start_run(project_id, "Build a todo app").unwrap()
  debug_inspect(
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
  debug_inspect(
    store.get_initial_project_prompt(project_id),
    content="Some(\"Build a todo app\")",
  )
  cleanup_test_db(db_path)
}

///|
async test "run events append and list after sequence" {
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
    ),
  )
  let run = store.start_run(project_id, "Build a todo app").unwrap()

  store.append_run_event(
    project_id,
    run.run_id,
    "status",
    "Starting Codex session.",
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
async test "startup recovery makes stale running runs retryable" {
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
    ),
  )
  let stale_run = store.start_run(project_id, "Build a todo app").unwrap()

  inspect(store.fail_stale_running_runs_on_startup(), content="1")
  let recovered_run = store.get_run(project_id, stale_run.run_id).unwrap()
  inspect(recovered_run.state == @sdk.Failed, content="true")
  debug_inspect(
    recovered_run.summary,
    content="Some(\"The previous worker was interrupted before it could finish. Send another message to retry this project.\")",
  )
  debug_inspect(
    recovered_run.failure_debug.map(fn(debug) { debug.stage }),
    content="Some(\"Worker recovery\")",
  )
  let project = store.get_project_detail(project_id).unwrap()
  inspect(project.status == @sdk.Failed, content="true")
  debug_inspect(project.current_run_id, content="None")
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
async test "workspace snapshot round-trips project files and excludes build outputs" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-roundtrip-db")
  let project_id = next_id("snapshot-roundtrip")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path + "/app")
  ensure_dir(workspace_path + "/_build/cache")
  safe_write_string(workspace_path + "/app/main.mbt", "first version\n")
  safe_write_string(workspace_path + "/_build/cache/output.txt", "generated\n")

  snapshot_workspace(store, root, project_id, workspace_path).unwrap()
  safe_write_string(workspace_path + "/app/main.mbt", "second version\n")
  restore_workspace_snapshot(store, root, project_id, workspace_path).unwrap()

  inspect(store.get_workspace_snapshot(project_id) is Some(_), content="true")
  inspect(
    safe_read_string_or(workspace_path + "/app/main.mbt", ""),
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
async test "restore without a database snapshot fails without legacy fallback" {
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
async test "hydrate run workspace restores the saved snapshot into an isolated path" {
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
async test "hydrate without a database snapshot fails without legacy fallback" {
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
async test "hydrate requires a database snapshot" {
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
