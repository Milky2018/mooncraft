///|
fn preview_test_project(preview : @sdk.PreviewTarget?) -> @sdk.ProjectDetail {
  {
    id: "project-1",
    preview_public_id: "preview-1",
    display_name: "Test project",
    runtime_id: "agent-runtime-001",
    runtime_name: "Runtime",
    runtime_config: None,
    agent_session_id: "agent-session-1",
    runtime_session_id: None,
    agent_cli: "codex",
    model: "openrouter/test-model",
    workspace_path: "/tmp/project-1",
    status: Idle,
    is_processing: false,
    activity: None,
    current_run_phase: NoPhase,
    preview,
    current_run_id: None,
    last_error: None,
    created_at: "1",
    updated_at: "1",
  }
}

///|
test "preview open target only returns healthy preview targets" {
  let no_preview_model = {
    ..initial_model(),
    project_detail: Some(preview_test_project(None)),
  }
  debug_inspect(preview_open_target(no_preview_model), content="None")
  let unhealthy_model = {
    ..initial_model(),
    project_detail: Some(
      preview_test_project(
        Some({ url: "/p/preview-1/", port: 4300, healthy: false }),
      ),
    ),
  }
  debug_inspect(
    preview_open_target(unhealthy_model).map(fn(target) { target.url }),
    content="None",
  )
  let healthy_model = {
    ..initial_model(),
    project_detail: Some(
      preview_test_project(
        Some({ url: "/p/preview-1/", port: 4300, healthy: true }),
      ),
    ),
  }
  debug_inspect(
    preview_open_target(healthy_model).map(fn(target) { target.url }),
    content="Some(\"/p/preview-1/\")",
  )
}

///|
test "run event display uses structured code instead of content matching" {
  let events : Array[@sdk.RunEvent] = [
    {
      seq: 1,
      kind: "status",
      code: @sdk.run_event_code_turn_planning(),
      content: "Started the builder session.",
      created_at: "1",
    },
  ]
  inspect(latest_run_event_text(events), content="Planning")
  let fallback_events : Array[@sdk.RunEvent] = [
    {
      seq: 1,
      kind: "status",
      code: "",
      content: "Planning appears in arbitrary text",
      created_at: "1",
    },
  ]
  inspect(
    latest_run_event_text(fallback_events),
    content="Planning appears in arbitrary text",
  )
  inspect(
    @sdk.run_event_display_text(
      @sdk.run_event_code_builder_ended(),
      "Builder session ended.",
    ),
    content="Builder finished",
  )
  inspect(
    @sdk.run_event_display_text(
      @sdk.run_event_code_workspace_saving(),
      "Saving the updated workspace.",
    ),
    content="Saving workspace",
  )
  inspect(
    @sdk.run_event_display_text(
      @sdk.run_event_code_workspace_restoring(),
      "Restoring the updated workspace.",
    ),
    content="Restoring workspace",
  )
  inspect(
    @sdk.run_event_display_text(
      @sdk.run_event_code_preview_starting(),
      "Starting the live preview.",
    ),
    content="Starting preview",
  )
  inspect(
    @sdk.run_event_display_text(
      @sdk.run_event_code_preview_publishing(),
      "Publishing the live preview.",
    ),
    content="Publishing preview",
  )
}
