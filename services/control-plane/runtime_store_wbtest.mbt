///|
async test "runtime seeding allows an empty built-in catalog" {
  let root = "/tmp/mooncraft-runtime-store-test-\{random_hex(6)}"
  ensure_dir(root)
  defer safe_remove_tree(root)
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
  match store.ensure_agent_runtime_tables() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let custom = store.get_runtime_detail("agent-runtime-custom-test").unwrap()
  inspect(custom is Some(_), content="true")
  let default_id = store.get_default_runtime_id()
  inspect(default_id is Ok(_), content="true")
}
