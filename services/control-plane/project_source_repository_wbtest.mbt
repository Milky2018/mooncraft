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
    owner: "milky",
    name: "mooncraft-project-source",
    clone_url: "https://github.com/milky/mooncraft-project-source.git",
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
      #|    owner: "milky",
      #|    name: "mooncraft-project-source",
      #|    clone_url: "https://github.com/milky/mooncraft-project-source.git",
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
