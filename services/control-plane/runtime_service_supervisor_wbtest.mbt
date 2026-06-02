///|
fn test_runtime_service_spec() -> RuntimeServiceSpec {
  {
    project_id: "project-runtime-test",
    image: "runtime:test",
    platform: "linux/arm64",
    env: { "RUNTIME_MODE": "test" },
    container_name: "mooncraft-runtime-project-runtime-test",
    network_name: "mooncraft-runtime",
    publish_ports: false,
  }
}

///|
test "runtime service container uses network without workspace volumes or published ports" {
  let args = runtime_service_create_args(
    test_runtime_service_spec(),
    "/tmp/runtime.env",
  )
  inspect(args.contains("-p"), content="false")
  inspect(args.contains("--publish"), content="false")
  inspect(args[0], content="create")
  inspect(args[2], content="mooncraft-runtime-project-runtime-test")
  inspect(args[6], content="mooncraft-runtime")
  inspect(args.contains("-v"), content="false")
  inspect(args[15], content="runtime:test")
}

///|
test "runtime service env file includes only launcher env" {
  inspect(
    runtime_service_env_file_content(test_runtime_service_spec()),
    content="RUNTIME_MODE=test\n",
  )
}

///|
test "runtime service existing health status controls init" {
  debug_inspect(
    runtime_service_existing_health_needs_init(
      @runtime_protocol.runtime_service_health_status_ready(),
    ),
    content="Ok(false)",
  )
  debug_inspect(
    runtime_service_existing_health_needs_init(
      @runtime_protocol.runtime_service_health_status_running(),
    ),
    content="Ok(false)",
  )
  debug_inspect(
    runtime_service_existing_health_needs_init(
      @runtime_protocol.runtime_service_health_status_not_initialized(),
    ),
    content="Ok(true)",
  )
  debug_inspect(
    runtime_service_existing_health_needs_init("unknown"),
    content=(
      #|Err("Runtime Service returned unsupported health status: unknown")
    ),
  )
}

///|
async test "runtime service records expose expired ready containers" {
  let root = "/tmp/mooncraft-runtime-service-store-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  match
    store.upsert_runtime_service_record(
      "project-runtime-test",
      "mooncraft-runtime-project-runtime-test",
      "mooncraft-runtime",
      runtime_service_state_ready(),
      Some("0"),
    ) {
    Ok(_) => ()
    Err(message) => fail(message)
  }
  let records = store.list_expired_ready_runtime_services()
  inspect(records.length(), content="1")
  inspect(records[0].project_id, content="project-runtime-test")
  inspect(
    records[0].container_name,
    content="mooncraft-runtime-project-runtime-test",
  )
}
