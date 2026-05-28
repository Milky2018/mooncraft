///|
async test "runtime seeding allows an empty built-in catalog" {
  let root = "/tmp/mooncraft-runtime-store-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let spec_json =
    #|{
    #|  "protocol_version": 3,
    #|  "image": "runtime:test",
    #|  "secrets": [
    #|    {
    #|      "source": "mooncraft_ai_api_key",
    #|      "target": {
    #|        "type": "env",
    #|        "name": "OPENROUTER_API_KEY"
    #|      }
    #|    }
    #|  ]
    #|}
  ignore(
    store.save_admin_runtime(
      "agent-runtime-custom-test", "Custom", spec_json, true, false,
    ),
  )
  if store.ensure_agent_runtime_tables() is Err(message) {
    abort(message)
  }
  let custom = store.get_runtime_detail("agent-runtime-custom-test").unwrap()
  inspect(custom is Some(_), content="true")
  let default_id = store.get_default_runtime_id()
  inspect(default_id is Ok(_), content="true")
}

///|
async test "runtime table migration drops retired agent and model columns" {
  let root = "/tmp/mooncraft-runtime-store-legacy-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  if store.exec_or_error(
      "ALTER TABLE agent_runtimes ADD COLUMN agent TEXT NOT NULL DEFAULT '';", "add legacy agent column",
    )
    is Err(message) {
    abort(message)
  }
  if store.exec_or_error(
      "ALTER TABLE agent_runtimes ADD COLUMN model TEXT NOT NULL DEFAULT '';", "add legacy model column",
    )
    is Err(message) {
    abort(message)
  }
  if store.ensure_agent_runtime_tables() is Err(message) {
    abort(message)
  }
  match store.column_exists("agent_runtimes", "agent") {
    Ok(exists) => inspect(exists, content="false")
    Err(message) => abort(message)
  }
  match store.column_exists("agent_runtimes", "model") {
    Ok(exists) => inspect(exists, content="false")
    Err(message) => abort(message)
  }
  let spec_json =
    #|{
    #|  "protocol_version": 3,
    #|  "image": "runtime:test",
    #|  "env": {},
    #|  "secrets": []
    #|}
  match
    store.save_admin_runtime(
      "agent-runtime-legacy-test", "Legacy migrated", spec_json, true, true,
    ) {
    Ok(_) => ignore(())
    Err(message) => abort(message)
  }
}
