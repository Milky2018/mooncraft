///|
struct RuntimeServiceExecRequest {
  run_id : String
  prompt : String
} derive(ToJson)

///|
struct RuntimeServiceRun {
  run_id : String
  status : String
  message : String
} derive(@json.FromJson)

///|
struct RuntimeServiceEvent {
  id : Int
  time : String
  level : String
  message : String
} derive(@json.FromJson)

///|
struct RuntimeServiceEventsResponse {
  events : Array[RuntimeServiceEvent]
} derive(@json.FromJson)

///|
struct RuntimeServiceError {
  message : String
} derive(@json.FromJson)

///|
fn runtime_service_api_url(
  endpoint : RuntimeServiceEndpoint,
  path : String,
) -> String {
  "\{endpoint.url}\{path}"
}

///|
fn runtime_service_json_headers() -> Map[String, String] {
  { "Accept": "application/json", "Content-Type": "application/json" }
}

///|
fn runtime_service_response_text(response : @mocket.HttpResponse) -> String {
  if response.raw_body.length() > 0 {
    bytes_to_string(response.raw_body)
  } else {
    response.read_body() catch {
      _ => ""
    }
  }
}

///|
fn runtime_service_error_message(
  response : @mocket.HttpResponse,
  fallback : String,
) -> String {
  let body = runtime_service_response_text(response)
  let parsed = @json.parse(body) catch { _ => return fallback }
  let error : RuntimeServiceError = @json.from_json(parsed) catch {
    _ => return fallback
  }
  if error.message.trim() == "" {
    fallback
  } else {
    error.message
  }
}

///|
fn[T : @json.FromJson] decode_runtime_service_json(
  body : String,
  label : String,
) -> Result[T, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("\{label} returned invalid JSON.")
  }
  Ok(
    @json.from_json(parsed) catch {
      _ => return Err("\{label} returned an unexpected response shape.")
    },
  )
}

///|
fn validate_runtime_service_run_id(
  run : RuntimeServiceRun,
  expected_run_id : String,
  label : String,
) -> Result[RuntimeServiceRun, String] {
  if run.run_id == expected_run_id {
    Ok(run)
  } else {
    Err("\{label} returned a different run id.")
  }
}

///|
async fn runtime_service_post_exec(
  endpoint : RuntimeServiceEndpoint,
  run_id : String,
  prompt : String,
) -> Result[RuntimeServiceRun, String] noraise {
  let body = RuntimeServiceExecRequest::{ run_id, prompt }.to_json().stringify()
  let headers = runtime_service_json_headers()
  let response = try
    @mocket.fetch(
      runtime_service_api_url(endpoint, "/exec"),
      POST,
      body~,
      headers~,
    )
  catch {
    _ => return Err("Runtime Service /exec is not reachable.")
  } noraise {
    response => response
  }
  let code = response.status_code.to_int()
  if code != 200 && code != 202 {
    let fallback = if code == 409 {
      "Runtime Service rejected the run because another run is active or this run id was already used differently."
    } else {
      "Runtime Service rejected the run request."
    }
    return Err(runtime_service_error_message(response, fallback))
  }
  let run : RuntimeServiceRun = match
    decode_runtime_service_json(
      runtime_service_response_text(response),
      "Runtime Service /exec",
    ) {
    Ok(run) => run
    Err(message) => return Err(message)
  }
  validate_runtime_service_run_id(run, run_id, "Runtime Service /exec")
}

///|
async fn runtime_service_get_run(
  endpoint : RuntimeServiceEndpoint,
  run_id : String,
) -> Result[RuntimeServiceRun, String] noraise {
  let headers = runtime_service_json_headers()
  let response = try
    @mocket.fetch(
      runtime_service_api_url(endpoint, "/runs/\{run_id}"),
      GET,
      headers~,
    )
  catch {
    _ => return Err("Runtime Service run status is not reachable.")
  } noraise {
    response => response
  }
  if !http_status_success(response.status_code) {
    return Err(
      runtime_service_error_message(
        response, "Runtime Service could not return the run status.",
      ),
    )
  }
  let run : RuntimeServiceRun = match
    decode_runtime_service_json(
      runtime_service_response_text(response),
      "Runtime Service run status",
    ) {
    Ok(run) => run
    Err(message) => return Err(message)
  }
  validate_runtime_service_run_id(run, run_id, "Runtime Service run status")
}

///|
async fn runtime_service_get_events(
  endpoint : RuntimeServiceEndpoint,
  run_id : String,
  after : Int,
) -> Result[RuntimeServiceEventsResponse, String] noraise {
  let headers = runtime_service_json_headers()
  let response = try
    @mocket.fetch(
      runtime_service_api_url(endpoint, "/runs/\{run_id}/events?after=\{after}"),
      GET,
      headers~,
    )
  catch {
    _ => return Err("Runtime Service run events are not reachable.")
  } noraise {
    response => response
  }
  if !http_status_success(response.status_code) {
    return Err(
      runtime_service_error_message(
        response, "Runtime Service could not return run events.",
      ),
    )
  }
  decode_runtime_service_json(
    runtime_service_response_text(response),
    "Runtime Service run events",
  )
}

///|
async fn runtime_service_get_preview(
  endpoint : RuntimeServiceEndpoint,
) -> Result[Unit, String] noraise {
  let response = try
    @mocket.fetch(runtime_service_api_url(endpoint, "/preview"), GET)
  catch {
    _ => return Err("Runtime Service preview readiness is not reachable.")
  } noraise {
    response => response
  }
  if http_status_success(response.status_code) {
    Ok(())
  } else {
    Err(
      runtime_service_error_message(
        response, "Runtime Service preview is not ready.",
      ),
    )
  }
}

///|
fn runtime_service_event_code(event : RuntimeServiceEvent) -> String {
  match event.level {
    "error" => @sdk.run_event_code_activity_tool_error()
    "warning" => @sdk.run_event_code_activity_message()
    _ => @sdk.run_event_code_activity_message()
  }
}

///|
async fn append_runtime_service_events(
  store : Store,
  project_id : String,
  run_id : String,
  worker_id : String,
  attempt : Int,
  events : Array[RuntimeServiceEvent],
  after : Ref[Int],
) -> Unit noraise {
  for event in events {
    ignore(event.time)
    if event.id > after.val {
      after.val = event.id
    }
    store.append_worker_run_event(
      project_id,
      run_id,
      worker_id,
      attempt,
      "status",
      runtime_service_event_code(event),
      event.message,
    )
  }
}

///|
fn runtime_service_status_message(run : RuntimeServiceRun) -> String {
  trim_or_default(run.message, "Runtime Service is working.")
}
