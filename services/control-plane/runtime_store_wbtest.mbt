///|
async test "runtime seeding removes retired built-in ids only" {
  let root = "/tmp/mooncraft-runtime-store-test-" + random_hex(6)
  ensure_dir(root)
  defer safe_remove_tree(root)
  let store = match try_new_async(root + "/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let spec_json =
    #|{
    #|  "protocol_version": 1,
    #|  "image": "runtime:test",
    #|  "agent": "codex",
    #|  "model": "openai/test",
    #|  "provider": "openrouter",
    #|  "send": ["mooncraft-runtime-send"],
    #|  "container_home": "/root",
    #|  "secrets": [
    #|    {
    #|      "source": "mooncraft_ai_api_key",
    #|      "env": "MOONCRAFT_AI_API_KEY"
    #|    }
    #|  ]
    #|}
  ignore(
    store.save_admin_runtime(
      "agent-runtime-999", "Retired", spec_json, true, false,
    ),
  )
  ignore(
    store.save_admin_runtime(
      "agent-runtime-custom-test", "Custom", spec_json, true, false,
    ),
  )
  match store.ensure_agent_runtime_tables() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  let retired = store.get_runtime_detail("agent-runtime-999").unwrap()
  let custom = store.get_runtime_detail("agent-runtime-custom-test").unwrap()
  inspect(retired is None, content="true")
  inspect(custom is Some(_), content="true")
}
