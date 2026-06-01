///|
test "github repository response becomes project source repository" {
  let body =
    #|{
    #|  "id": 12345,
    #|  "name": "mooncraft-project-123",
    #|  "clone_url": "https://github.com/example-user/mooncraft-project-123.git",
    #|  "default_branch": "main",
    #|  "owner": {
    #|    "login": "example-user"
    #|  }
    #|}
  match github_repository_from_response(body) {
    Ok(source) =>
      debug_inspect(
        source,
        content=(
          #|{
          #|  host: "github",
          #|  repository_id: "12345",
          #|  owner: "example-user",
          #|  name: "mooncraft-project-123",
          #|  clone_url: "https://github.com/example-user/mooncraft-project-123.git",
          #|  default_branch: "main",
          #|  ready_commit_sha: None,
          #|  status: "connected",
          #|  last_error: None,
          #|}
        ),
      )
    Err(message) => abort(message)
  }
}

///|
test "github create repository request creates private empty repository" {
  debug_inspect(
    github_create_repository_body("project-123", "Tank Game"),
    content=(
      #|"{\"name\":\"mooncraft-project-123\",\"description\":\"MoonCraft project: Tank Game\",\"private\":true,\"auto_init\":false}"
    ),
  )
}

///|
async test "create source repository requires github credential" {
  let root = "/tmp/mooncraft-source-create-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let user = match
    store.create_user(
      "source-create@example.com",
      None,
      "Source Create",
      Some("example-user"),
      true,
    ) {
    Ok(user) => user
    Err(message) => abort(message)
  }
  let ctx = {
    root,
    build_profile: Debug,
    store,
    runtime_gateway: new_runtime_gateway(root),
  }
  debug_inspect(
    ctx.create_project_source_repository(user, "project-source-create", "Todo"),
    content=(
      #|Err("GitHub repository access is not connected. Sign in with GitHub again.")
    ),
  )
}

///|
async test "refresh marks source repository disconnected without github token" {
  let root = "/tmp/mooncraft-source-refresh-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let user = match
    store.create_user(
      "source-refresh@example.com",
      None,
      "Source Refresh",
      Some("example-user"),
      true,
    ) {
    Ok(user) => user
    Err(message) => abort(message)
  }
  let project = store.create_project_with_runtime(
    "project-source-refresh",
    user.id,
    "preview-source-refresh",
    "Source Refresh Project",
    "agent-runtime-source-refresh",
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
    name: "mooncraft-project-source-refresh",
    clone_url: "https://github.com/example-user/mooncraft-project-source-refresh.git",
    default_branch: "main",
    ready_commit_sha: None,
    status: "connected",
    last_error: None,
  }
  if store.save_project_source_repository(project.id, source) is Err(message) {
    abort(message)
  }
  let project = match store.get_project_detail(project.id) {
    Some(project) => project
    None => abort("expected project")
  }
  let ctx = {
    root,
    build_profile: Debug,
    store,
    runtime_gateway: new_runtime_gateway(root),
  }
  debug_inspect(
    ctx.refresh_project_source_repository(user, project),
    content="Err(\"Project Source Repository is disconnected.\")",
  )
  let disconnected = match
    ctx.store.get_project_detail("project-source-refresh") {
    Some(project) => project.source_repository
    None => abort("expected project")
  }
  match disconnected {
    Some(source) =>
      debug_inspect(
        source,
        content=(
          #|{
          #|  host: "github",
          #|  repository_id: "12345",
          #|  owner: "example-user",
          #|  name: "mooncraft-project-source-refresh",
          #|  clone_url: "https://github.com/example-user/mooncraft-project-source-refresh.git",
          #|  default_branch: "main",
          #|  ready_commit_sha: None,
          #|  status: "source_disconnected",
          #|  last_error: Some("GitHub repository access is not connected. Sign in with GitHub again."),
          #|}
        ),
      )
    None => abort("expected source repository")
  }
}
