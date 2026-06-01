///|
test "runtime protocol routes are stable" {
  debug_inspect(
    [
      runtime_service_health_path(),
      runtime_service_init_path(),
      runtime_service_exec_path(),
      runtime_service_run_path("run-1"),
      runtime_service_run_events_path("run-1", 12),
      runtime_service_preview_path(),
    ],
    content=(
      #|[
      #|  "/health",
      #|  "/init",
      #|  "/exec",
      #|  "/runs/run-1",
      #|  "/runs/run-1/events?after=12",
      #|  "/preview/",
      #|]
    ),
  )
}

///|
test "runtime protocol decodes and validates init request" {
  let body =
    #|{
    #|  "project": { "id": "project-1" },
    #|  "source_repository": {
    #|    "url": "https://github.com/milky/project.git",
    #|    "default_branch": "main",
    #|    "current_commit_sha": null
    #|  },
    #|  "source_credential": {
    #|    "kind": "git_https_token",
    #|    "username": "x-access-token",
    #|    "password": "github-token"
    #|  },
    #|  "secrets": [{ "name": "CODEX_AUTH_JSON", "value": "{}" }]
    #|}
  match runtime_service_init_request_from_json_text(body) {
    Ok(request) =>
      debug_inspect(
        request,
        content=(
          #|{
          #|  project: { id: "project-1" },
          #|  source_repository: {
          #|    url: "https://github.com/milky/project.git",
          #|    default_branch: "main",
          #|    current_commit_sha: None,
          #|  },
          #|  source_credential: {
          #|    kind: "git_https_token",
          #|    username: "x-access-token",
          #|    password: "github-token",
          #|  },
          #|  secrets: [{ name: "CODEX_AUTH_JSON", value: "{}" }],
          #|}
        ),
      )
    Err(message) => fail(message)
  }
}

///|
test "runtime protocol rejects extra init fields" {
  let body =
    #|{
    #|  "project": { "id": "project-1", "extra": true },
    #|  "source_repository": {
    #|    "url": "https://github.com/milky/project.git",
    #|    "default_branch": "main"
    #|  },
    #|  "source_credential": {
    #|    "kind": "git_https_token",
    #|    "username": "x-access-token",
    #|    "password": "github-token"
    #|  },
    #|  "secrets": []
    #|}
  debug_inspect(
    runtime_service_init_request_from_json_text(body),
    content=(
      #|Err("Runtime Service /init project field is not supported: extra")
    ),
  )
}

///|
test "runtime protocol requires ready commit for succeeded run" {
  let succeeded : RuntimeServiceRun = match
    runtime_service_json_decode(
      "{\"run_id\":\"run-1\",\"status\":\"succeeded\",\"message\":\"done\",\"ready_commit_sha\":\"abc123\"}",
      "Runtime Service run",
    ) {
    Ok(run) => run
    Err(message) => abort(message)
  }
  debug_inspect(
    runtime_service_ready_commit(succeeded),
    content="Ok(\"abc123\")",
  )
  let missing : RuntimeServiceRun = match
    runtime_service_json_decode(
      "{\"run_id\":\"run-1\",\"status\":\"succeeded\",\"message\":\"done\"}", "Runtime Service run",
    ) {
    Ok(run) => run
    Err(message) => abort(message)
  }
  debug_inspect(
    runtime_service_ready_commit(missing),
    content=(
      #|Err("Runtime Service reported success without a ready_commit_sha. The project source was not marked ready.")
    ),
  )
}

///|
test "runtime protocol preview paths map to upstream paths" {
  debug_inspect(
    [
      runtime_service_preview_upstream_path("/preview"),
      runtime_service_preview_upstream_path("/preview/"),
      runtime_service_preview_upstream_path("/preview/assets/app.js"),
    ],
    content=(
      #|["/", "/", "/assets/app.js"]
    ),
  )
}
