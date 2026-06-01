///|
async test "runtime settings resolve source credential and opaque secrets for init" {
  let root = "/tmp/mooncraft-runtime-settings-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let user = match
    store.create_user(
      "runtime-settings@example.com",
      None,
      "Runtime Settings",
      Some("milky"),
      true,
    ) {
    Ok(user) => user
    Err(message) => abort(message)
  }
  store.link_oauth_account(user.id, "github", "123", "github-token")
  match store.create_admin_secret("runtime_api_key", "runtime-key") {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let config_json =
    #|{
    #|  "config_version": 3,
    #|  "launcher": {
    #|    "kind": "docker",
    #|    "image": "runtime:test"
    #|  },
    #|  "env": {
    #|    "MODEL": "gpt-5.4-mini"
    #|  },
    #|  "secrets": {
    #|    "OPENROUTER_API_KEY": "runtime_api_key"
    #|  }
    #|}
  let project = store.create_project_with_runtime(
    "project-runtime-settings",
    user.id,
    "preview-runtime-settings",
    "Runtime Settings Project",
    "agent-runtime-settings",
    "Runtime",
    config_json,
    "",
    "",
    "",
    "\{root}/workspace",
  )
  let source : @sdk.ProjectSourceRepository = {
    host: "github",
    repository_id: "12345",
    owner: "milky",
    name: "mooncraft-project-runtime-settings",
    clone_url: "https://github.com/milky/mooncraft-project-runtime-settings.git",
    default_branch: "main",
    ready_commit_sha: None,
    status: "connected",
    last_error: None,
  }
  if store.save_project_source_repository(project.id, source) is Err(message) {
    abort(message)
  }
  let settings = match store.lease_runtime_settings_for_project(project.id) {
    Ok(settings) => settings
    Err(message) => abort(message)
  }
  debug_inspect(
    settings.source_credential,
    content=(
      #|{
      #|  kind: "git_https_token",
      #|  username: "x-access-token",
      #|  password: "github-token",
      #|}
    ),
  )
  debug_inspect(
    settings.secrets,
    content=(
      #|[{ name: "OPENROUTER_API_KEY", value: "runtime-key" }]
    ),
  )
}
