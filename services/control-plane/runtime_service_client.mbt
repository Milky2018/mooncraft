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
fn runtime_service_secret_from_resolved(
  secret : ResolvedRuntimeSecret,
) -> @runtime_protocol.RuntimeServiceSecret {
  { name: secret.name, value: secret.value }
}

///|
fn runtime_service_init_request(
  project : @sdk.ProjectDetail,
  source_credential : @runtime_protocol.RuntimeServiceSourceCredential,
  secrets : Array[ResolvedRuntimeSecret],
) -> Result[@runtime_protocol.RuntimeServiceInitRequest, String] {
  let source = match project.source_repository {
    Some(source) => source
    None => return Err("Project Source Repository is not configured.")
  }
  if source.status == "source_disconnected" {
    return Err("Project Source Repository is disconnected.")
  }
  let protocol_secrets : Array[@runtime_protocol.RuntimeServiceSecret] = []
  for secret in secrets {
    protocol_secrets.push(runtime_service_secret_from_resolved(secret))
  }
  Ok({
    project: { id: project.id },
    source_repository: {
      url: source.clone_url,
      default_branch: source.default_branch,
      current_commit_sha: source.ready_commit_sha,
    },
    source_credential,
    secrets: protocol_secrets,
  })
}

///|
fn runtime_service_error_message(
  response : UpstreamHttpResponse,
  fallback : String,
) -> String {
  @runtime_protocol.runtime_service_error_message_from_body(
    http_response_text(response),
    fallback,
  )
}

///|
fn[T : @json.FromJson] decode_runtime_service_json(
  body : String,
  label : String,
) -> Result[T, String] {
  @runtime_protocol.runtime_service_json_decode(body, label)
}

///|
fn validate_runtime_service_run_id(
  run : @runtime_protocol.RuntimeServiceRun,
  expected_run_id : String,
  label : String,
) -> Result[@runtime_protocol.RuntimeServiceRun, String] {
  @runtime_protocol.runtime_service_validate_run_id(run, expected_run_id, label)
}

///|
fn runtime_service_ready_commit(
  run : @runtime_protocol.RuntimeServiceRun,
) -> Result[String, String] {
  @runtime_protocol.runtime_service_ready_commit(run)
}

///|
async fn runtime_service_post_exec(
  endpoint : RuntimeServiceEndpoint,
  run_id : String,
  prompt : String,
) -> Result[@runtime_protocol.RuntimeServiceRun, String] noraise {
  let body = @runtime_protocol.RuntimeServiceExecRequest::{ run_id, prompt }
    .to_json()
    .stringify()
  let headers = runtime_service_json_headers()
  let response = match
    http_post(
      runtime_service_api_url(
        endpoint,
        @runtime_protocol.runtime_service_exec_path(),
      ),
      body,
      headers~,
    ) {
    Ok(response) => response
    Err(_) => return Err("Runtime Service /exec is not reachable.")
  }
  let code = response.code
  if code != 200 && code != 202 {
    let fallback = if code == 409 {
      "Runtime Service rejected the run because another run is active or this run id was already used differently."
    } else {
      "Runtime Service rejected the run request."
    }
    return Err(runtime_service_error_message(response, fallback))
  }
  let run : @runtime_protocol.RuntimeServiceRun = match
    decode_runtime_service_json(
      http_response_text(response),
      "Runtime Service /exec",
    ) {
    Ok(run) => run
    Err(message) => return Err(message)
  }
  validate_runtime_service_run_id(run, run_id, "Runtime Service /exec")
}

///|
async fn runtime_service_post_init(
  endpoint : RuntimeServiceEndpoint,
  request : @runtime_protocol.RuntimeServiceInitRequest,
) -> Result[@runtime_protocol.RuntimeServiceInitResponse, String] noraise {
  let body = request.to_json().stringify()
  let headers = runtime_service_json_headers()
  let response = match
    http_post(
      runtime_service_api_url(
        endpoint,
        @runtime_protocol.runtime_service_init_path(),
      ),
      body,
      headers~,
    ) {
    Ok(response) => response
    Err(_) => return Err("Runtime Service /init is not reachable.")
  }
  if !http_status_success(response.code) {
    let fallback = if response.code == 409 {
      "Runtime Service cannot be initialized while a run is active."
    } else {
      "Runtime Service initialization failed."
    }
    return Err(runtime_service_error_message(response, fallback))
  }
  let init : @runtime_protocol.RuntimeServiceInitResponse = match
    decode_runtime_service_json(
      http_response_text(response),
      "Runtime Service /init",
    ) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if init.status == @runtime_protocol.runtime_service_health_status_ready() {
    ignore(init.current_commit_sha)
    ignore(init.message)
    Ok(init)
  } else {
    Err("Runtime Service /init did not return ready status.")
  }
}

///|
async fn runtime_service_get_health(
  endpoint : RuntimeServiceEndpoint,
) -> Result[@runtime_protocol.RuntimeServiceHealthResponse, String] noraise {
  let headers = runtime_service_json_headers()
  let response = match
    http_get(
      runtime_service_api_url(
        endpoint,
        @runtime_protocol.runtime_service_health_path(),
      ),
      headers~,
    ) {
    Ok(response) => response
    Err(_) => return Err("Runtime Service /health is not reachable.")
  }
  if !http_status_success(response.code) {
    return Err(
      runtime_service_error_message(
        response, "Runtime Service health check failed.",
      ),
    )
  }
  decode_runtime_service_json(
    http_response_text(response),
    "Runtime Service /health",
  )
}

///|
async fn runtime_service_get_run(
  endpoint : RuntimeServiceEndpoint,
  run_id : String,
) -> Result[@runtime_protocol.RuntimeServiceRun, String] noraise {
  let headers = runtime_service_json_headers()
  let response = match
    http_get(
      runtime_service_api_url(
        endpoint,
        @runtime_protocol.runtime_service_run_path(run_id),
      ),
      headers~,
    ) {
    Ok(response) => response
    Err(_) => return Err("Runtime Service run status is not reachable.")
  }
  if !http_status_success(response.code) {
    return Err(
      runtime_service_error_message(
        response, "Runtime Service could not return the run status.",
      ),
    )
  }
  let run : @runtime_protocol.RuntimeServiceRun = match
    decode_runtime_service_json(
      http_response_text(response),
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
) -> Result[@runtime_protocol.RuntimeServiceEventsResponse, String] noraise {
  let headers = runtime_service_json_headers()
  let response = match
    http_get(
      runtime_service_api_url(
        endpoint,
        @runtime_protocol.runtime_service_run_events_path(run_id, after),
      ),
      headers~,
    ) {
    Ok(response) => response
    Err(_) => return Err("Runtime Service run events are not reachable.")
  }
  if !http_status_success(response.code) {
    return Err(
      runtime_service_error_message(
        response, "Runtime Service could not return run events.",
      ),
    )
  }
  decode_runtime_service_json(
    http_response_text(response),
    "Runtime Service run events",
  )
}

///|
async fn runtime_service_serve(
  endpoint : RuntimeServiceEndpoint,
) -> Result[Unit, String] noraise {
  let headers = runtime_service_json_headers()
  let response = match
    http_post(
      runtime_service_api_url(
        endpoint,
        @runtime_protocol.runtime_service_serve_path(),
      ),
      "",
      headers~,
    ) {
    Ok(response) => response
    Err(_) => return Err("Runtime Service serve endpoint is not reachable.")
  }
  if !http_status_success(response.code) {
    return Err(
      runtime_service_error_message(response, "Runtime Service serve failed."),
    )
  }
  let preview : @runtime_protocol.RuntimeServiceServeResponse = match
    decode_runtime_service_json(
      http_response_text(response),
      "Runtime Service /serve",
    ) {
    Ok(preview) => preview
    Err(message) => return Err(message)
  }
  if preview.status == @runtime_protocol.runtime_service_health_status_ready() {
    Ok(())
  } else {
    Err("Runtime Service serve did not return ready status.")
  }
}

///|
fn runtime_service_event_code(
  event : @runtime_protocol.RuntimeServiceEvent,
) -> String {
  match event.level {
    level if level == @runtime_protocol.runtime_service_event_level_error() =>
      @sdk.run_event_code_activity_tool_error()
    level if level == @runtime_protocol.runtime_service_event_level_warning() =>
      @sdk.run_event_code_activity_message()
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
  events : Array[@runtime_protocol.RuntimeServiceEvent],
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
fn runtime_service_status_message(
  run : @runtime_protocol.RuntimeServiceRun,
) -> String {
  trim_or_default(run.message, "Runtime Service is working.")
}
