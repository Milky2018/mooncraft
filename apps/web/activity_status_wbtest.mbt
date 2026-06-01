///|
fn activity_test_project(
  status : @sdk.RunState,
  activity : @sdk.ProjectActivity?,
) -> @sdk.ProjectDetail {
  {
    id: "project-activity",
    preview_public_id: "preview-activity",
    display_name: "Activity Project",
    runtime_id: "agent-runtime-001",
    runtime_name: "Runtime",
    runtime_config: None,
    agent_session_id: "agent-session-activity",
    runtime_session_id: None,
    agent_cli: "codex",
    model: "openrouter/test-model",
    workspace_path: "/tmp/project-activity",
    status,
    is_processing: activity is Some(_),
    activity,
    current_run_phase: match activity {
      Some(value) => value.phase
      None => NoPhase
    },
    preview: None,
    current_run_id: match activity {
      Some(value) => Some(value.run_id)
      None => None
    },
    last_error: None,
    created_at: "1",
    updated_at: "2",
  }
}

///|
test "active project status remains final while activity is processing" {
  let activity = Some(@sdk.ProjectActivity::{
    run_id: "run-1",
    phase: RuntimeRunning,
    message_code: None,
    message: None,
  })
  let model = {
    ..initial_model(),
    selected_project_id: Some("project-activity"),
    project_detail: Some(activity_test_project(Succeeded, activity)),
  }
  debug_inspect(active_project_status(model), content="Succeeded")
  debug_inspect(
    active_run(model).map(fn(run) { run.state }),
    content="Some(Running)",
  )
}

///|
test "summary run update does not turn project final status into running" {
  let project = project_summary_from_detail(
    activity_test_project(Succeeded, None),
  )
  let run : @sdk.RunStatusResponse = {
    run_id: "run-2",
    project_id: "project-activity",
    state: Running,
    phase: Checking,
    summary: None,
    error_message: None,
    failure_debug: None,
    preview: None,
    started_at: "2",
    finished_at: None,
  }
  let updated = replace_project_summary_run_status([project], run)
  debug_inspect(updated[0].status, content="Succeeded")
  debug_inspect(updated[0].is_processing, content="true")
  debug_inspect(
    updated[0].activity.map(fn(activity) { activity.phase }),
    content="Some(Checking)",
  )
}
