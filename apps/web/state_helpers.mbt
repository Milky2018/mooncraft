///|
fn pick_selected_project_id(
  model : Model,
  projects : Array[@sdk.ProjectSummary],
) -> String? {
  match model.selected_project_id {
    Some(selected) => {
      for project in projects {
        if project.id == selected {
          return Some(selected)
        }
      }
      None
    }
    None => if projects.length() > 0 { Some(projects[0].id) } else { None }
  }
}

///|
fn active_run(model : Model) -> @sdk.RunStatusResponse? {
  match model.run_status {
    Some(run) if run.state is Running => Some(run)
    _ =>
      match model.project_detail {
        Some(project) if project.status is Running =>
          match project.current_run_id {
            Some(run_id) =>
              Some({
                run_id,
                project_id: project.id,
                state: Running,
                summary: None,
                error_message: None,
                failure_debug: None,
                preview: project.preview,
                started_at: project.updated_at,
                finished_at: None,
              })
            None => None
          }
        _ => None
      }
  }
}

///|
fn can_send(model : Model) -> Bool {
  model.current_user is Some(_) &&
  model.selected_project_id is Some(_) &&
  model.draft.trim() != "" &&
  !model.sending_message &&
  active_run(model) is None
}

///|
fn can_create_project(model : Model) -> Bool {
  model.current_user is Some(_) &&
  model.new_project_name.trim() != "" &&
  !model.create_project_pending
}

///|
fn model_id_compatible_with_agent(
  agent_cli : String,
  model_id : String,
) -> Bool {
  let value = model_id.trim().to_owned().to_lower()
  match agent_cli {
    "claude_code" => value.has_prefix("anthropic/")
    "kimi_code" => value.has_prefix("moonshotai/") || value.contains("kimi")
    _ => true
  }
}

///|
fn compatible_default_model(agent_cli : String, model : Model) -> String {
  if model_id_compatible_with_agent(agent_cli, model.new_project_model) {
    model.new_project_model
  } else if model_id_compatible_with_agent(
      agent_cli,
      model.ai_models_default_model,
    ) {
    model.ai_models_default_model
  } else {
    for item in model.ai_models {
      if model_id_compatible_with_agent(agent_cli, item.id) {
        return item.id
      }
    }
    ""
  }
}

///|
fn can_rename_project(model : Model) -> Bool {
  match model.project_detail {
    Some(project) => {
      let name = model.rename_project_name.trim().to_owned()
      name != "" &&
      name != project.display_name &&
      !model.rename_project_pending
    }
    None => false
  }
}

///|
fn append_local_user_message(
  model : Model,
  project_id : String,
  content : String,
) -> Array[@sdk.ChatMessage] {
  let messages = model.messages.copy()
  messages.push({
    id: "local-" + content.length().to_string(),
    project_id,
    run_id: None,
    role: User,
    content,
    created_at: "now",
  })
  messages
}

///|
fn project_summary_from_detail(
  project : @sdk.ProjectDetail,
) -> @sdk.ProjectSummary {
  {
    id: project.id,
    display_name: project.display_name,
    agent_cli: project.agent_cli,
    model: project.model,
    status: project.status,
    preview: project.preview,
    current_run_id: project.current_run_id,
    updated_at: project.updated_at,
  }
}

///|
fn replace_project_summary(
  projects : Array[@sdk.ProjectSummary],
  replacement : @sdk.ProjectSummary,
) -> Array[@sdk.ProjectSummary] {
  let items : Array[@sdk.ProjectSummary] = []
  let mut found = false
  for item in projects {
    if item.id == replacement.id {
      items.push(replacement)
      found = true
    } else {
      items.push(item)
    }
  }
  if !found {
    items.push(replacement)
  }
  items
}

///|
fn error_notice(prefix : String, error : @sdk.ApiError) -> String {
  prefix + " " + error.message
}

///|
fn run_failure_summary(run : @sdk.RunStatusResponse) -> String? {
  if !(run.state is Failed) {
    None
  } else {
    match run.summary {
      Some(summary) => Some(summary)
      None => run.error_message
    }
  }
}

///|
fn is_unauthorized_error(error : @sdk.ApiError) -> Bool {
  error.code == Unauthorized
}

///|
fn clear_workspace(model : Model) -> Model {
  {
    ..model,
    projects: [],
    selected_project_id: None,
    project_detail: None,
    messages: [],
    run_status: None,
    run_events: [],
    last_run_event_seq: 0,
    run_spinner_tick: 0,
    draft: "",
    new_project_modal_open: false,
    new_project_name: "",
    new_project_agent_cli: "codex",
    new_project_more_open: false,
    new_project_model: "",
    ai_models: [],
    ai_models_default_model: "",
    ai_models_loading: false,
    ai_models_error: None,
    create_project_pending: false,
    rename_project_editing: false,
    rename_project_name: "",
    rename_project_pending: false,
    delete_project_confirming: None,
    delete_project_pending: None,
    sending_message: false,
    notice: None,
  }
}

///|
fn apply_session(model : Model, session : @sdk.SessionResponse) -> Model {
  let next = if session.authenticated { model } else { clear_workspace(model) }
  {
    ..next,
    session_ready: true,
    current_user: if session.authenticated {
      session.user
    } else {
      None
    },
    github_enabled: session.github_enabled,
    app_mode: session.app_mode,
    logout_pending: false,
    auth_notice: None,
  }
}

///|
fn auth_recovery(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  message : String,
) -> (@rabbita.Cmd, Model) {
  (
    load_session_cmd(dispatch),
    {
      ..clear_workspace(model),
      current_user: None,
      logout_pending: false,
      account_notice: None,
      account_panel_open: false,
      auth_notice: Some(message),
    },
  )
}
