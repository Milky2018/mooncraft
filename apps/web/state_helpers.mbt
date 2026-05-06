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
fn can_save_ai_settings(model : Model) -> Bool {
  let has_key = match model.current_user {
    Some(user) => user.ai_api_key_configured || model.account_ai_api_key != ""
    None => false
  }
  model.account_ai_provider != "" &&
  model.account_ai_model.trim() != "" &&
  has_key &&
  !model.account_pending
}

///|
fn model_options_include(
  items : Array[@sdk.ModelOption],
  model_id : String,
) -> Bool {
  for item in items {
    if item.id == model_id {
      return true
    }
  }
  false
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
    active_page: AppWorkspace,
    draft: "",
    create_project_pending: false,
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
    account_pending: false,
    account_ai_provider: match session.user {
      Some(user) => user.ai_provider
      None => "openai"
    },
    account_ai_model: match session.user {
      Some(user) => user.ai_model
      None => "gpt-5.5"
    },
    account_ai_api_key: "",
    account_model_options: [],
    account_model_options_pending: false,
    auth_notice: None,
    active_page: if session.authenticated {
      model.active_page
    } else {
      AppWorkspace
    },
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
      account_ai_provider: "openai",
      account_ai_model: "gpt-5.5",
      account_ai_api_key: "",
      account_pending: false,
      account_notice: None,
      account_panel_open: false,
      active_page: AppWorkspace,
      auth_notice: Some(message),
    },
  )
}
