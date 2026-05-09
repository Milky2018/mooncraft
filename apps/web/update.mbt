///|
fn update(
  dispatch : @rabbita.Dispatch[Msg],
  msg : Msg,
  model : Model,
) -> (@rabbita.Cmd, Model) {
  match msg {
    Bootstrap =>
      (
        @rabbita.batch([load_theme_cmd(dispatch), load_session_cmd(dispatch)]),
        { ..model, boot_requested: true, notice: None },
      )
    ThemeModeLoaded(theme_mode, resolved_theme_mode) =>
      (@rabbita.none, { ..model, theme_mode, resolved_theme_mode })
    ToggleTheme => {
      let theme_mode = model.theme_mode.next()
      (
        persist_theme_cmd(dispatch, theme_mode),
        {
          ..model,
          theme_mode,
          resolved_theme_mode: resolved_theme_fallback(
            theme_mode,
            model.resolved_theme_mode,
          ),
        },
      )
    }
    SessionLoaded(Ok(session)) => {
      let next_model = apply_session(model, session)
      let cmd = if session.authenticated {
        load_projects_cmd(dispatch)
      } else {
        @rabbita.none
      }
      (cmd, next_model)
    }
    SessionLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..clear_workspace(model),
          session_ready: true,
          current_user: None,
          auth_notice: Some(
            error_notice("Session state could not be loaded.", error),
          ),
        },
      )
    Logout =>
      if model.logout_pending {
        (@rabbita.none, model)
      } else {
        (
          logout_cmd(dispatch),
          { ..model, logout_pending: true, auth_notice: None, notice: None },
        )
      }
    LoggedOut(Ok(_)) =>
      (
        load_session_cmd(dispatch),
        {
          ..clear_workspace(model),
          current_user: None,
          logout_pending: false,
          account_notice: None,
          account_panel_open: false,
          auth_notice: None,
        },
      )
    LoggedOut(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          logout_pending: false,
          auth_notice: Some(error_notice("Sign-out failed.", error)),
          notice: Some(error_notice("Sign-out failed.", error)),
        },
      )
    ToggleAccountPanel =>
      (
        @rabbita.none,
        { ..model, account_panel_open: !model.account_panel_open },
      )
    ProjectsLoaded(Ok(response)) => {
      let projects = response.items
      let selected_project_id = pick_selected_project_id(model, projects)
      let selection_changed = selected_project_id != model.selected_project_id
      let cmd = match selected_project_id {
        Some(project_id) => load_project_cmd(dispatch, project_id)
        None => @rabbita.none
      }
      let next_model = if selection_changed {
        {
          ..model,
          projects,
          selected_project_id,
          project_detail: None,
          messages: [],
          run_status: None,
          run_events: [],
          last_run_event_seq: 0,
          run_spinner_tick: 0,
          rename_project_editing: false,
          rename_project_name: "",
          rename_project_pending: false,
        }
      } else {
        { ..model, projects, selected_project_id }
      }
      (cmd, next_model)
    }
    ProjectsLoaded(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            notice: Some(error_notice("Projects could not be loaded.", error)),
          },
        )
      }
    SelectProject(project_id) =>
      (
        load_project_cmd(dispatch, project_id),
        {
          ..model,
          selected_project_id: Some(project_id),
          project_detail: None,
          messages: [],
          run_events: [],
          last_run_event_seq: 0,
          run_spinner_tick: 0,
          delete_project_confirming: None,
          rename_project_editing: false,
          rename_project_name: "",
          rename_project_pending: false,
          notice: None,
        },
      )
    ProjectLoaded(Ok(project)) => {
      let cmd = match project.current_run_id {
        Some(run_id) if project.status is Running =>
          @rabbita.batch([
            @rabbita.delay(dispatch(PollRun(project.id, run_id)), 1000),
            dispatch(PollRunEvents(project.id, run_id)),
          ])
        _ => @rabbita.none
      }
      (
        cmd,
        {
          ..model,
          project_detail: Some(project),
          rename_project_editing: false,
          rename_project_name: project.display_name,
          rename_project_pending: false,
          notice: None,
        },
      )
    }
    ProjectLoaded(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            notice: Some(
              error_notice("Project details could not be loaded.", error),
            ),
          },
        )
      }
    MessagesLoaded(Ok(response)) =>
      (@rabbita.none, { ..model, messages: response.items })
    MessagesLoaded(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            notice: Some(
              error_notice("Chat history could not be loaded.", error),
            ),
          },
        )
      }
    DraftChanged(value) => (@rabbita.none, { ..model, draft: value })
    OpenNewProjectDialog =>
      (
        load_ai_models_cmd(dispatch),
        {
          ..model,
          new_project_modal_open: true,
          new_project_name: "",
          new_project_agent_cli: "codex",
          new_project_more_open: false,
          new_project_model: model.ai_models_default_model,
          ai_models_loading: true,
          delete_project_confirming: None,
          notice: None,
        },
      )
    CloseNewProjectDialog =>
      if model.create_project_pending {
        (@rabbita.none, model)
      } else {
        (
          @rabbita.none,
          {
            ..model,
            new_project_modal_open: false,
            new_project_name: "",
            new_project_agent_cli: "codex",
            new_project_more_open: false,
          },
        )
      }
    NewProjectNameChanged(value) =>
      (@rabbita.none, { ..model, new_project_name: value })
    ToggleNewProjectMore =>
      (
        @rabbita.none,
        { ..model, new_project_more_open: !model.new_project_more_open },
      )
    NewProjectAgentChanged(value) =>
      (
        @rabbita.none,
        {
          ..model,
          new_project_agent_cli: value,
          new_project_model: compatible_default_model(value, model),
        },
      )
    NewProjectModelChanged(value) =>
      (@rabbita.none, { ..model, new_project_model: value })
    AiModelsLoaded(Ok(response)) => {
      let next_model = {
        ..model,
        ai_models: response.items,
        ai_models_default_model: response.default_model,
      }
      let selected_model = compatible_default_model(
        model.new_project_agent_cli,
        next_model,
      )
      (
        @rabbita.none,
        {
          ..model,
          ai_models: next_model.ai_models,
          ai_models_default_model: response.default_model,
          new_project_model: selected_model,
          ai_models_loading: false,
        },
      )
    }
    AiModelsLoaded(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (@rabbita.none, { ..model, ai_models_loading: false })
      }
    CreateProject =>
      if !can_create_project(model) {
        (@rabbita.none, model)
      } else {
        let display_name = model.new_project_name.trim().to_owned()
        (
          create_project_cmd(
            dispatch,
            display_name,
            ui_empty_to_none(model.new_project_agent_cli),
            ui_empty_to_none(model.new_project_model),
          ),
          {
            ..model,
            create_project_pending: true,
            new_project_modal_open: true,
            delete_project_confirming: None,
            notice: None,
          },
        )
      }
    StartProjectRename(display_name) =>
      match model.selected_project_id {
        Some(_) =>
          (
            @rabbita.none,
            {
              ..model,
              rename_project_editing: true,
              rename_project_name: display_name,
              notice: None,
            },
          )
        None => (@rabbita.none, model)
      }
    CancelProjectRename =>
      if model.rename_project_pending {
        (@rabbita.none, model)
      } else {
        match model.project_detail {
          Some(project) =>
            (
              @rabbita.none,
              {
                ..model,
                rename_project_editing: false,
                rename_project_name: project.display_name,
              },
            )
          None =>
            (
              @rabbita.none,
              {
                ..model,
                rename_project_editing: false,
                rename_project_name: "",
              },
            )
        }
      }
    RenameProjectNameChanged(value) =>
      (@rabbita.none, { ..model, rename_project_name: value })
    SaveProjectRename =>
      match model.project_detail {
        Some(project) if can_rename_project(model) => {
          let display_name = model.rename_project_name.trim().to_owned()
          (
            rename_project_cmd(dispatch, project.id, display_name),
            { ..model, rename_project_pending: true, notice: None },
          )
        }
        _ => (@rabbita.none, model)
      }
    RequestDeleteProject(project_id) =>
      if model.delete_project_pending is Some(_) {
        (@rabbita.none, model)
      } else if model.delete_project_confirming == Some(project_id) {
        (@rabbita.none, model)
      } else {
        (
          @rabbita.none,
          { ..model, delete_project_confirming: Some(project_id), notice: None },
        )
      }
    ConfirmDeleteProject(project_id) =>
      if model.delete_project_pending is Some(_) ||
        model.delete_project_confirming != Some(project_id) {
        (@rabbita.none, model)
      } else {
        (
          delete_project_cmd(dispatch, project_id),
          {
            ..model,
            delete_project_confirming: None,
            delete_project_pending: Some(project_id),
            notice: None,
          },
        )
      }
    ProjectCreated(Ok(response)) => {
      let project = response.project
      (
        @rabbita.batch([
          load_projects_cmd(dispatch),
          load_messages_cmd(dispatch, project.id),
        ]),
        {
          ..model,
          create_project_pending: false,
          new_project_modal_open: false,
          new_project_name: "",
          new_project_agent_cli: "codex",
          new_project_more_open: false,
          selected_project_id: Some(project.id),
          project_detail: Some(project),
          rename_project_editing: false,
          rename_project_name: project.display_name,
          rename_project_pending: false,
          messages: [],
          run_status: None,
          run_events: [],
          last_run_event_seq: 0,
          run_spinner_tick: 0,
          delete_project_confirming: None,
        },
      )
    }
    ProjectCreated(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            create_project_pending: false,
            new_project_modal_open: true,
            rename_project_pending: false,
            delete_project_confirming: None,
            notice: Some(
              error_notice("A new project could not be created.", error),
            ),
          },
        )
      }
    ProjectDeleted(project_id, Ok(_)) => {
      let next_model = if model.selected_project_id == Some(project_id) {
        {
          ..model,
          selected_project_id: None,
          project_detail: None,
          messages: [],
          run_status: None,
          run_events: [],
          last_run_event_seq: 0,
          run_spinner_tick: 0,
          draft: "",
          rename_project_editing: false,
          rename_project_name: "",
          rename_project_pending: false,
          delete_project_confirming: None,
          delete_project_pending: None,
        }
      } else {
        {
          ..model,
          delete_project_confirming: None,
          delete_project_pending: None,
        }
      }
      (load_projects_cmd(dispatch), next_model)
    }
    ProjectRenamed(Ok(response)) => {
      let project = response.project
      let project_summary = project_summary_from_detail(project)
      (
        @rabbita.none,
        {
          ..model,
          projects: replace_project_summary(model.projects, project_summary),
          project_detail: if model.selected_project_id == Some(project.id) {
            Some(project)
          } else {
            model.project_detail
          },
          rename_project_editing: false,
          rename_project_name: project.display_name,
          rename_project_pending: false,
          notice: None,
        },
      )
    }
    ProjectRenamed(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            rename_project_pending: false,
            notice: Some(
              error_notice("The project could not be renamed.", error),
            ),
          },
        )
      }
    ProjectDeleted(_, Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            delete_project_confirming: None,
            delete_project_pending: None,
            notice: Some(
              error_notice("The project could not be deleted.", error),
            ),
          },
        )
      }
    SendDraft =>
      match model.selected_project_id {
        Some(project_id) if can_send(model) => {
          let content = model.draft.trim().to_owned()
          (
            create_run_cmd(dispatch, project_id, content),
            {
              ..model,
              draft: "",
              sending_message: true,
              notice: None,
              messages: append_local_user_message(model, project_id, content),
              run_events: [],
              last_run_event_seq: 0,
              run_spinner_tick: 0,
              stopping_run_id: None,
            },
          )
        }
        _ => (@rabbita.none, model)
      }
    StopRun(project_id, run_id) =>
      if model.stopping_run_id is Some(_) {
        (@rabbita.none, model)
      } else {
        (
          cancel_run_cmd(dispatch, project_id, run_id),
          { ..model, stopping_run_id: Some(run_id), notice: None },
        )
      }
    RunCreated(Ok(response)) =>
      match response.poll_after_ms {
        Some(delay_ms) if response.run.state is Running =>
          (
            @rabbita.batch([
              @rabbita.delay(
                dispatch(PollRun(response.run.project_id, response.run.run_id)),
                delay_ms,
              ),
              dispatch(
                PollRunEvents(response.run.project_id, response.run.run_id),
              ),
            ]),
            {
              ..model,
              run_status: Some(response.run),
              sending_message: false,
              run_events: [],
              last_run_event_seq: 0,
              run_spinner_tick: 0,
              stopping_run_id: None,
            },
          )
        _ =>
          (
            @rabbita.batch([
              load_projects_cmd(dispatch),
              load_project_cmd(dispatch, response.run.project_id),
            ]),
            {
              ..model,
              run_status: Some(response.run),
              sending_message: false,
              stopping_run_id: None,
              notice: None,
            },
          )
      }
    RunCreated(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            sending_message: false,
            stopping_run_id: None,
            notice: Some(error_notice("The request could not be sent.", error)),
          },
        )
      }
    RunCancelled(Ok(response)) =>
      (
        @rabbita.batch([
          load_run_events_cmd(
            dispatch,
            response.run.project_id,
            response.run.run_id,
            model.last_run_event_seq,
          ),
          load_projects_cmd(dispatch),
          load_project_cmd(dispatch, response.run.project_id),
        ]),
        {
          ..model,
          run_status: Some(response.run),
          stopping_run_id: None,
          notice: None,
        },
      )
    RunCancelled(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            stopping_run_id: None,
            notice: Some(error_notice("The run could not be stopped.", error)),
          },
        )
      }
    PollRun(project_id, run_id) =>
      (load_run_cmd(dispatch, project_id, run_id), model)
    RunLoaded(project_id, run_id, Ok(run)) =>
      if run.state is Running {
        (
          @rabbita.batch([
            @rabbita.delay(dispatch(PollRun(project_id, run_id)), 1000),
            @rabbita.delay(dispatch(PollRunEvents(project_id, run_id)), 1000),
          ]),
          { ..model, run_status: Some(run) },
        )
      } else {
        (
          @rabbita.batch([
            load_run_events_cmd(
              dispatch,
              project_id,
              run_id,
              model.last_run_event_seq,
            ),
            load_projects_cmd(dispatch),
            load_project_cmd(dispatch, project_id),
          ]),
          {
            ..model,
            run_status: Some(run),
            stopping_run_id: None,
            notice: None,
          },
        )
      }
    PollRunEvents(project_id, run_id) =>
      (
        load_run_events_cmd(
          dispatch,
          project_id,
          run_id,
          model.last_run_event_seq,
        ),
        model,
      )
    RunEventsLoaded(Ok(response)) => {
      let events = model.run_events.copy()
      let mut last_seq = model.last_run_event_seq
      for event in response.items {
        events.push(event)
        if event.seq > last_seq {
          last_seq = event.seq
        }
      }
      (
        @rabbita.none,
        {
          ..model,
          run_events: events,
          last_run_event_seq: last_seq,
          run_spinner_tick: model.run_spinner_tick + 1,
        },
      )
    }
    RunEventsLoaded(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (@rabbita.none, model)
      }
    RunLoaded(_, _, Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            notice: Some(
              error_notice("Run status could not be refreshed.", error),
            ),
          },
        )
      }
  }
}
