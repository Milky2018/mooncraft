///|
fn preview_test_project(preview : @sdk.PreviewTarget?) -> @sdk.ProjectDetail {
  {
    id: "project-1",
    preview_public_id: "preview-1",
    display_name: "Test project",
    agent_cli: "codex",
    model: "openrouter/test-model",
    workspace_path: "/tmp/project-1",
    codex_thread_id: None,
    status: Idle,
    preview,
    current_run_id: None,
    last_error: None,
    created_at: "1",
    updated_at: "1",
  }
}

///|
test "ready preview only returns healthy preview targets" {
  let no_preview_model = {
    ..initial_model(),
    project_detail: Some(preview_test_project(None)),
  }
  debug_inspect(ready_preview(no_preview_model), content="None")
  let unhealthy_model = {
    ..initial_model(),
    project_detail: Some(
      preview_test_project(
        Some({ url: "/p/preview-1/", port: 4300, healthy: false }),
      ),
    ),
  }
  debug_inspect(ready_preview(unhealthy_model), content="None")
  let healthy_model = {
    ..initial_model(),
    project_detail: Some(
      preview_test_project(
        Some({ url: "/p/preview-1/", port: 4300, healthy: true }),
      ),
    ),
  }
  debug_inspect(
    ready_preview(healthy_model).map(fn(target) { target.url }),
    content="Some(\"/p/preview-1/\")",
  )
}
