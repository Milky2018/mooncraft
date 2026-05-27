///|
test "runtime service validates authoritative run id" {
  let run : RuntimeServiceRun = {
    run_id: "run-1",
    status: "running",
    message: "working",
  }
  inspect(
    validate_runtime_service_run_id(run, "run-1", "Runtime Service run")
    is Ok(_),
    content="true",
  )
  inspect(
    validate_runtime_service_run_id(run, "run-2", "Runtime Service run")
    is Err(_),
    content="true",
  )
}

///|
test "runtime service event levels map to activity codes" {
  let info : RuntimeServiceEvent = {
    id: 1,
    time: "2026-05-27T00:00:00Z",
    level: "info",
    message: "Building",
  }
  let warning : RuntimeServiceEvent = {
    id: 2,
    time: "2026-05-27T00:00:01Z",
    level: "warning",
    message: "Slow",
  }
  let error : RuntimeServiceEvent = {
    id: 3,
    time: "2026-05-27T00:00:02Z",
    level: "error",
    message: "Failed",
  }
  inspect(runtime_service_event_code(info), content="activity_message")
  inspect(runtime_service_event_code(warning), content="activity_message")
  inspect(runtime_service_event_code(error), content="activity_tool_error")
}

///|
test "runtime service JSON decoder rejects malformed responses" {
  let run : RuntimeServiceRun = match
    decode_runtime_service_json(
      "{\"run_id\":\"run-1\",\"status\":\"succeeded\",\"message\":\"done\"}", "Runtime Service run",
    ) {
    Ok(run) => run
    Err(message) => abort(message)
  }
  inspect(run.status, content="succeeded")
  let invalid : Result[RuntimeServiceRun, String] = decode_runtime_service_json(
    "{\"run_id\":\"run-1\",\"status\":\"running\"}", "Runtime Service run",
  )
  inspect(invalid is Err(_), content="true")
}
