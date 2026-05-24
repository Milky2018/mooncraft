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
          auth_notice: Some(error_notice("Failed to load session.", error)),
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
          auth_notice: Some(error_notice("Failed to log out.", error)),
          notice: Some(error_notice("Failed to log out.", error)),
        },
      )
    ToggleAccountPanel =>
      (
        @rabbita.none,
        { ..model, account_panel_open: !model.account_panel_open },
      )
    SetPreviewPanelMode(mode) =>
      (@rabbita.none, { ..model, preview_panel_mode: mode })
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
          rename_project_editing: false,
          rename_project_name: "",
          rename_project_pending: false,
          project_action_menu_open: None,
          project_info_open: false,
          project_info_pending: false,
          delete_project_confirming: None,
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
            notice: Some(error_notice("Failed to load projects.", error)),
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
          run_status: None,
          run_events: [],
          last_run_event_seq: 0,
          stopping_run_id: None,
          delete_project_confirming: None,
          project_action_menu_open: None,
          project_info_open: false,
          project_info_pending: false,
          rename_project_editing: false,
          rename_project_name: "",
          rename_project_pending: false,
          notice: None,
        },
      )
    ProjectLoaded(requested_project_id, Ok(project)) =>
      if model.selected_project_id != Some(requested_project_id) ||
        project.id != requested_project_id {
        (@rabbita.none, model)
      } else {
        let cmd = match project.activity {
          Some(activity) if project.is_processing =>
            @rabbita.batch([
              @rabbita.delay(
                dispatch(PollRun(project.id, activity.run_id)),
                1000,
              ),
              dispatch(PollRunEvents(project.id, activity.run_id)),
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
            project_action_menu_open: None,
            project_info_open: false,
            project_info_pending: false,
            delete_project_confirming: None,
            notice: None,
          },
        )
      }
    ProjectLoaded(requested_project_id, Err(error)) =>
      if model.selected_project_id != Some(requested_project_id) {
        (@rabbita.none, model)
      } else if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            notice: Some(error_notice("Failed to load project.", error)),
          },
        )
      }
    MessagesLoaded(project_id, Ok(response)) =>
      if model.selected_project_id == Some(project_id) {
        (@rabbita.none, { ..model, messages: response.items })
      } else {
        (@rabbita.none, model)
      }
    MessagesLoaded(project_id, Err(error)) =>
      if model.selected_project_id != Some(project_id) {
        (@rabbita.none, model)
      } else if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            notice: Some(error_notice("Failed to load messages.", error)),
          },
        )
      }
    DraftChanged(value) => (@rabbita.none, { ..model, draft: value })
    OpenNewProjectDialog =>
      (
        load_runtimes_cmd(dispatch),
        {
          ..model,
          new_project_modal_open: true,
          new_project_name: "",
          new_project_runtime_id: if model.default_runtime_id != "" {
            model.default_runtime_id
          } else {
            model.new_project_runtime_id
          },
          runtimes_loading: true,
          delete_project_confirming: None,
          project_action_menu_open: None,
          project_info_open: false,
          project_info_pending: false,
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
            new_project_runtime_id: model.default_runtime_id,
          },
        )
      }
    NewProjectNameChanged(value) =>
      (@rabbita.none, { ..model, new_project_name: value })
    NewProjectRuntimeChanged(value) =>
      (@rabbita.none, { ..model, new_project_runtime_id: value })
    RuntimesLoaded(Ok(response)) =>
      (
        @rabbita.none,
        {
          ..model,
          runtimes: response.items,
          default_runtime_id: response.default_runtime_id,
          new_project_runtime_id: if model.new_project_runtime_id == "" {
            response.default_runtime_id
          } else {
            model.new_project_runtime_id
          },
          runtimes_loading: false,
        },
      )
    RuntimesLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          runtimes_loading: false,
          notice: Some(error_notice("Failed to load Runtimes.", error)),
        },
      )
    CreateProject =>
      if !can_create_project(model) {
        (@rabbita.none, model)
      } else {
        let display_name = model.new_project_name.trim().to_owned()
        (
          create_project_cmd(
            dispatch,
            display_name,
            ui_empty_to_none(model.new_project_runtime_id),
          ),
          {
            ..model,
            create_project_pending: true,
            new_project_modal_open: true,
            delete_project_confirming: None,
            project_action_menu_open: None,
            notice: None,
          },
        )
      }
    ToggleProjectActionMenu(project_id) =>
      (
        @rabbita.none,
        {
          ..model,
          project_action_menu_open: if model.project_action_menu_open ==
            Some(project_id) {
            None
          } else {
            Some(project_id)
          },
          delete_project_confirming: if model.project_action_menu_open ==
            Some(project_id) {
            model.delete_project_confirming
          } else {
            None
          },
        },
      )
    OpenProjectInfo =>
      (
        @rabbita.none,
        {
          ..model,
          project_action_menu_open: None,
          project_info_open: true,
          project_info_pending: false,
          delete_project_confirming: None,
          notice: None,
        },
      )
    CloseProjectInfo =>
      if model.project_info_pending {
        (@rabbita.none, model)
      } else {
        (
          @rabbita.none,
          { ..model, project_info_open: false, project_info_pending: false },
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
              project_action_menu_open: None,
              project_info_open: false,
              project_info_pending: false,
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
                project_action_menu_open: None,
              },
            )
          None =>
            (
              @rabbita.none,
              {
                ..model,
                rename_project_editing: false,
                rename_project_name: "",
                project_action_menu_open: None,
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
          {
            ..model,
            delete_project_confirming: Some(project_id),
            project_action_menu_open: Some(project_id),
            notice: None,
          },
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
            project_action_menu_open: None,
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
          selected_project_id: Some(project.id),
          project_detail: Some(project),
          rename_project_editing: false,
          rename_project_name: project.display_name,
          rename_project_pending: false,
          messages: [],
          run_status: None,
          run_events: [],
          last_run_event_seq: 0,
          delete_project_confirming: None,
          project_action_menu_open: None,
          project_info_open: false,
          project_info_pending: false,
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
            project_action_menu_open: None,
            project_info_open: false,
            project_info_pending: false,
            notice: Some(error_notice("Failed to create project.", error)),
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
          draft: "",
          rename_project_editing: false,
          rename_project_name: "",
          rename_project_pending: false,
          delete_project_confirming: None,
          project_action_menu_open: None,
          project_info_open: false,
          project_info_pending: false,
          delete_project_pending: None,
        }
      } else {
        {
          ..model,
          delete_project_confirming: None,
          project_action_menu_open: None,
          project_info_open: false,
          project_info_pending: false,
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
          project_action_menu_open: None,
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
            notice: Some(error_notice("Failed to rename project.", error)),
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
            project_action_menu_open: None,
            delete_project_pending: None,
            notice: Some(error_notice("Failed to delete project.", error)),
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
          if model.selected_project_id == Some(response.run.project_id) {
            (
              @rabbita.batch([
                @rabbita.delay(
                  dispatch(
                    PollRun(response.run.project_id, response.run.run_id),
                  ),
                  delay_ms,
                ),
                dispatch(
                  PollRunEvents(response.run.project_id, response.run.run_id),
                ),
              ]),
              {
                ..model,
                projects: replace_project_summary_run_status(
                  model.projects,
                  response.run,
                ),
                project_detail: update_project_detail_run_status(
                  model.project_detail,
                  response.run,
                ),
                run_status: Some(response.run),
                sending_message: false,
                run_events: [],
                last_run_event_seq: 0,
                stopping_run_id: None,
              },
            )
          } else {
            (
              @rabbita.none,
              {
                ..model,
                projects: replace_project_summary_run_status(
                  model.projects,
                  response.run,
                ),
                sending_message: false,
                stopping_run_id: None,
              },
            )
          }
        _ =>
          if model.selected_project_id == Some(response.run.project_id) {
            (
              @rabbita.batch([
                load_projects_cmd(dispatch),
                load_project_cmd(dispatch, response.run.project_id),
              ]),
              {
                ..model,
                projects: replace_project_summary_run_status(
                  model.projects,
                  response.run,
                ),
                project_detail: update_project_detail_run_status(
                  model.project_detail,
                  response.run,
                ),
                run_status: Some(response.run),
                sending_message: false,
                stopping_run_id: None,
                notice: None,
              },
            )
          } else {
            (
              load_projects_cmd(dispatch),
              {
                ..model,
                projects: replace_project_summary_run_status(
                  model.projects,
                  response.run,
                ),
                sending_message: false,
                stopping_run_id: None,
              },
            )
          }
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
            notice: Some(error_notice("Failed to send message.", error)),
          },
        )
      }
    RunCancelled(Ok(response)) =>
      if model.selected_project_id == Some(response.run.project_id) {
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
            project_detail: update_project_detail_run_status(
              model.project_detail,
              response.run,
            ),
            stopping_run_id: None,
            notice: None,
          },
        )
      } else {
        (
          load_projects_cmd(dispatch),
          { ..model, stopping_run_id: None, notice: None },
        )
      }
    RunCancelled(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            stopping_run_id: None,
            notice: Some(error_notice("Failed to stop run.", error)),
          },
        )
      }
    PollRun(project_id, run_id) =>
      if model.selected_project_id == Some(project_id) {
        (load_run_cmd(dispatch, project_id, run_id), model)
      } else {
        (@rabbita.none, model)
      }
    RunLoaded(project_id, run_id, Ok(run)) =>
      if model.selected_project_id != Some(project_id) ||
        run.project_id != project_id ||
        run.run_id != run_id {
        (
          @rabbita.none,
          {
            ..model,
            projects: replace_project_summary_run_status(model.projects, run),
          },
        )
      } else if run.state is Running {
        (
          @rabbita.batch([
            @rabbita.delay(dispatch(PollRun(project_id, run_id)), 1000),
            @rabbita.delay(dispatch(PollRunEvents(project_id, run_id)), 1000),
          ]),
          {
            ..model,
            projects: replace_project_summary_run_status(model.projects, run),
            project_detail: update_project_detail_run_status(
              model.project_detail,
              run,
            ),
            run_status: Some(run),
          },
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
            project_detail: update_project_detail_run_status(
              model.project_detail,
              run,
            ),
            stopping_run_id: None,
            notice: None,
          },
        )
      }
    PollRunEvents(project_id, run_id) =>
      if model.selected_project_id == Some(project_id) {
        (
          load_run_events_cmd(
            dispatch,
            project_id,
            run_id,
            model.last_run_event_seq,
          ),
          model,
        )
      } else {
        (@rabbita.none, model)
      }
    RunEventsLoaded(project_id, Ok(response)) => {
      if model.selected_project_id != Some(project_id) {
        return (@rabbita.none, model)
      }
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
          projects: update_project_summary_activity_message(
            model.projects,
            project_id,
            latest_event_code(events),
            latest_event_content(events),
          ),
          project_detail: update_project_activity_message(
            model.project_detail,
            project_id,
            latest_event_code(events),
            latest_event_content(events),
          ),
          run_events: events,
          last_run_event_seq: last_seq,
        },
      )
    }
    RunEventsLoaded(project_id, Err(error)) =>
      if model.selected_project_id != Some(project_id) {
        (@rabbita.none, model)
      } else if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (@rabbita.none, model)
      }
    RunLoaded(project_id, _, Err(error)) =>
      if model.selected_project_id != Some(project_id) {
        (@rabbita.none, model)
      } else if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            notice: Some(error_notice("Failed to refresh run.", error)),
          },
        )
      }
  }
}
