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
fn runtime_service_client_test_project(
  source_repository : @sdk.ProjectSourceRepository?,
) -> @sdk.ProjectDetail {
  {
    id: "project-init",
    preview_public_id: "preview-init",
    display_name: "Init Project",
    runtime_id: "agent-runtime-init",
    runtime_name: "Runtime",
    runtime_config: None,
    agent_session_id: "",
    runtime_session_id: None,
    agent_cli: "",
    model: "",
    workspace_path: "/tmp/project-init",
    status: Idle,
    is_processing: false,
    activity: None,
    current_run_phase: NoPhase,
    preview: None,
    source_repository,
    current_run_id: None,
    last_error: None,
    created_at: "1",
    updated_at: "1",
  }
}

///|
fn runtime_service_client_test_source(
  status : String,
) -> @sdk.ProjectSourceRepository {
  {
    host: "github",
    repository_id: "123",
    owner: "milky",
    name: "mooncraft-project-init",
    clone_url: "https://github.com/milky/mooncraft-project-init.git",
    default_branch: "main",
    ready_commit_sha: Some("abc123"),
    status,
    last_error: None,
  }
}

///|
test "runtime service init request uses source credential and opaque secrets" {
  let credential : RuntimeServiceSourceCredential = {
    kind: "git_https_token",
    username: "x-access-token",
    password: "github-token",
  }
  let secrets : Array[ResolvedRuntimeSecret] = [
    { name: "OPENROUTER_API_KEY", value: "runtime-key" },
  ]
  match
    runtime_service_init_request(
      runtime_service_client_test_project(
        Some(runtime_service_client_test_source("connected")),
      ),
      credential,
      secrets,
    ) {
    Ok(request) =>
      debug_inspect(
        request,
        content=(
          #|{
          #|  project: { id: "project-init" },
          #|  source_repository: {
          #|    url: "https://github.com/milky/mooncraft-project-init.git",
          #|    default_branch: "main",
          #|    current_commit_sha: Some("abc123"),
          #|  },
          #|  source_credential: {
          #|    kind: "git_https_token",
          #|    username: "x-access-token",
          #|    password: "github-token",
          #|  },
          #|  secrets: [{ name: "OPENROUTER_API_KEY", value: "runtime-key" }],
          #|}
        ),
      )
    Err(message) => abort(message)
  }
}

///|
test "runtime service init request rejects source disconnected projects" {
  let credential : RuntimeServiceSourceCredential = {
    kind: "git_https_token",
    username: "x-access-token",
    password: "github-token",
  }
  debug_inspect(
    runtime_service_init_request(
      runtime_service_client_test_project(
        Some(runtime_service_client_test_source("source_disconnected")),
      ),
      credential,
      [],
    ),
    content="Err(\"Project Source Repository is disconnected.\")",
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
