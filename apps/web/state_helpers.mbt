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
    Some(run) =>
      if run.state is Running &&
        model.selected_project_id == Some(run.project_id) {
        return Some(run)
      }
    _ => ignore(())
  }
  match model.project_detail {
    Some(project) =>
      if project.is_processing && model.selected_project_id == Some(project.id) {
        match project.activity {
          Some(activity) =>
            Some({
              run_id: activity.run_id,
              project_id: project.id,
              state: Running,
              phase: activity.phase,
              summary: None,
              error_message: None,
              failure_debug: None,
              preview: project.preview,
              started_at: project.updated_at,
              finished_at: None,
            })
          None => None
        }
      } else {
        None
      }
    _ => None
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
  model.new_project_runtime_id.trim() != "" &&
  !model.create_project_pending
}

///|
fn selected_project_detail(model : Model) -> @sdk.ProjectDetail? {
  match model.project_detail {
    Some(project) if model.selected_project_id == Some(project.id) =>
      Some(project)
    _ => None
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
    id: "local-\{content.length()}",
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
    runtime_id: project.runtime_id,
    runtime_name: project.runtime_name,
    agent_session_id: project.agent_session_id,
    agent_cli: project.agent_cli,
    model: project.model,
    status: project.status,
    is_processing: project.is_processing,
    activity: project.activity,
    current_run_phase: project.current_run_phase,
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
fn replace_project_summary_run_status(
  projects : Array[@sdk.ProjectSummary],
  run : @sdk.RunStatusResponse,
) -> Array[@sdk.ProjectSummary] {
  let items : Array[@sdk.ProjectSummary] = []
  for item in projects {
    if item.id == run.project_id {
      items.push({
        ..item,
        status: if run.state is Running {
          item.status
        } else {
          run.state
        },
        is_processing: run.state is Running,
        activity: project_activity_from_run(run),
        current_run_phase: run.phase,
        current_run_id: if run.state is Running {
          Some(run.run_id)
        } else {
          None
        },
      })
    } else {
      items.push(item)
    }
  }
  items
}

///|
fn project_activity_from_run(
  run : @sdk.RunStatusResponse,
) -> @sdk.ProjectActivity? {
  if run.state is Running {
    Some({
      run_id: run.run_id,
      phase: run.phase,
      message_code: None,
      message: None,
    })
  } else {
    None
  }
}

///|
fn update_project_detail_run_status(
  project : @sdk.ProjectDetail?,
  run : @sdk.RunStatusResponse,
) -> @sdk.ProjectDetail? {
  match project {
    Some(item) if item.id == run.project_id =>
      Some({
        ..item,
        status: if run.state is Running {
          item.status
        } else {
          run.state
        },
        is_processing: run.state is Running,
        activity: project_activity_from_run(run),
        current_run_phase: run.phase,
        current_run_id: if run.state is Running {
          Some(run.run_id)
        } else {
          None
        },
        preview: match run.preview {
          Some(preview) => Some(preview)
          None => item.preview
        },
      })
    _ => project
  }
}

///|
fn latest_event_content(events : Array[@sdk.RunEvent]) -> String? {
  let mut text : String? = None
  for event in events {
    if event.content != "" {
      text = Some(event.content)
    }
  }
  text
}

///|
fn latest_event_code(events : Array[@sdk.RunEvent]) -> String? {
  let mut code : String? = None
  for event in events {
    if event.content != "" && event.code != "" {
      code = Some(event.code)
    }
  }
  code
}

///|
fn update_project_activity_message(
  project : @sdk.ProjectDetail?,
  project_id : String,
  message_code : String?,
  message : String?,
) -> @sdk.ProjectDetail? {
  match project {
    Some(item) if item.id == project_id =>
      Some({
        ..item,
        activity: match item.activity {
          Some(activity) => Some({ ..activity, message_code, message })
          None => None
        },
      })
    _ => project
  }
}

///|
fn update_project_summary_activity_message(
  projects : Array[@sdk.ProjectSummary],
  project_id : String,
  message_code : String?,
  message : String?,
) -> Array[@sdk.ProjectSummary] {
  let items : Array[@sdk.ProjectSummary] = []
  for item in projects {
    if item.id == project_id {
      items.push({
        ..item,
        activity: match item.activity {
          Some(activity) => Some({ ..activity, message_code, message })
          None => None
        },
      })
    } else {
      items.push(item)
    }
  }
  items
}

///|
fn error_notice(prefix : String, error : @sdk.ApiError) -> String {
  "\{prefix} \{error.message}"
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
    draft: "",
    new_project_modal_open: false,
    new_project_name: "",
    new_project_runtime_id: "",
    runtimes: [],
    default_runtime_id: "",
    runtimes_loading: false,
    create_project_pending: false,
    project_action_menu_open: None,
    project_info_open: false,
    project_info_pending: false,
    rename_project_editing: false,
    rename_project_name: "",
    rename_project_pending: false,
    delete_project_confirming: None,
    delete_project_pending: None,
    sending_message: false,
    stopping_run_id: None,
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
