///|
async test "project detail includes source repository metadata" {
  let root = "/tmp/mooncraft-source-repository-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let project = store.create_project_with_runtime(
    "project-source",
    "user-source",
    "preview-source",
    "Source Project",
    "agent-runtime-source",
    "Runtime",
    @sdk.default_runtime_config_json(),
    "",
    "",
    "",
    "\{root}/workspace",
  )
  debug_inspect(project.source_repository, content="None")
  let source : @sdk.ProjectSourceRepository = {
    host: "github",
    repository_id: "12345",
    owner: "example-user",
    name: "mooncraft-project-source",
    clone_url: "https://github.com/example-user/mooncraft-project-source.git",
    default_branch: "main",
    ready_commit_sha: Some("abc123"),
    status: "connected",
    last_error: None,
  }
  if store.save_project_source_repository("project-source", source)
    is Err(message) {
    abort(message)
  }
  let loaded = match store.get_project_detail("project-source") {
    Some(project) => project
    None => abort("expected project")
  }
  debug_inspect(
    loaded.source_repository,
    content=(
      #|Some(
      #|  {
      #|    host: "github",
      #|    repository_id: "12345",
      #|    owner: "example-user",
      #|    name: "mooncraft-project-source",
      #|    clone_url: "https://github.com/example-user/mooncraft-project-source.git",
      #|    default_branch: "main",
      #|    ready_commit_sha: Some("abc123"),
      #|    status: "connected",
      #|    last_error: None,
      #|  },
      #|)
    ),
  )
  if store.delete_project("project-source") is Err(message) {
    abort(message)
  }
  debug_inspect(store.get_project_detail("project-source"), content="None")
}

///|
async test "successful run stores ready source commit" {
  let root = "/tmp/mooncraft-ready-commit-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let project = store.create_project_with_runtime(
    "project-ready-commit",
    "user-ready-commit",
    "preview-ready-commit",
    "Ready Commit Project",
    "agent-runtime-ready-commit",
    "Runtime",
    @sdk.default_runtime_config_json(),
    "",
    "",
    "",
    "\{root}/workspace",
  )
  let source : @sdk.ProjectSourceRepository = {
    host: "github",
    repository_id: "12345",
    owner: "example-user",
    name: "mooncraft-project-ready-commit",
    clone_url: "https://github.com/example-user/mooncraft-project-ready-commit.git",
    default_branch: "main",
    ready_commit_sha: None,
    status: "connected",
    last_error: None,
  }
  if store.save_project_source_repository(project.id, source) is Err(message) {
    abort(message)
  }
  let run = match store.start_run(project.id, "build todo app") {
    Ok(run) => run
    Err(message) => abort(message)
  }
  let worker = store.next_run_worker_registration(project.id, run.run_id)
  match
    store.register_run_worker(
      project.id,
      run.run_id,
      worker.worker_id,
      worker.attempt,
      1234,
    ) {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  store.finish_run_success_for_worker(
    project.id,
    run.run_id,
    worker.worker_id,
    worker.attempt,
    "Done",
    None,
    { url: "/p/ready-commit/", port: 4792, healthy: true },
    Some("def456"),
  )
  let loaded = match store.get_project_detail(project.id) {
    Some(project) => project
    None => abort("expected project")
  }
  debug_inspect(
    loaded.source_repository,
    content=(
      #|Some(
      #|  {
      #|    host: "github",
      #|    repository_id: "12345",
      #|    owner: "example-user",
      #|    name: "mooncraft-project-ready-commit",
      #|    clone_url: "https://github.com/example-user/mooncraft-project-ready-commit.git",
      #|    default_branch: "main",
      #|    ready_commit_sha: Some("def456"),
      #|    status: "connected",
      #|    last_error: None,
      #|  },
      #|)
    ),
  )
}
