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
          auth_pending: false,
          auth_notice: Some(
            error_notice("Session state could not be loaded.", error),
          ),
        },
      )
    AuthModeSelected(mode) =>
      (
        @rabbita.none,
        { ..model, auth_mode: mode, auth_notice: None, auth_password: "" },
      )
    AuthEmailChanged(value) => (@rabbita.none, { ..model, auth_email: value })
    AuthPasswordChanged(value) =>
      (@rabbita.none, { ..model, auth_password: value })
    AuthDisplayNameChanged(value) =>
      (@rabbita.none, { ..model, auth_display_name: value })
    SubmitAuth =>
      if !can_submit_auth(model) {
        (@rabbita.none, model)
      } else {
        (
          submit_auth_cmd(dispatch, model),
          { ..model, auth_pending: true, auth_notice: None },
        )
      }
    AuthCompleted(Ok(_)) =>
      (
        load_session_cmd(dispatch),
        {
          ..model,
          auth_pending: false,
          auth_password: "",
          auth_notice: None,
          account_notice: if model.auth_mode is Signup {
            Some("Verification link queued in the local account email outbox.")
          } else {
            model.account_notice
          },
          account_panel_open: false,
          password_panel_open: false,
        },
      )
    AuthCompleted(Err(error)) =>
      (
        @rabbita.none,
        { ..model, auth_pending: false, auth_notice: Some(error.message) },
      )
    RequestPasswordResetCompleted(Ok(response)) =>
      (
        @rabbita.none,
        {
          ..model,
          auth_pending: false,
          auth_password: "",
          auth_notice: Some(response.message),
        },
      )
    RequestPasswordResetCompleted(Err(error)) =>
      (
        @rabbita.none,
        { ..model, auth_pending: false, auth_notice: Some(error.message) },
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
          auth_mode: Login,
          auth_email: "",
          auth_password: "",
          auth_display_name: "",
          logout_pending: false,
          account_current_password: "",
          account_new_password: "",
          account_ai_provider: "openai",
          account_ai_model: "gpt-5.5",
          account_ai_api_key: "",
          account_model_options: [],
          account_model_options_pending: false,
          account_pending: false,
          account_notice: None,
          account_panel_open: false,
          password_panel_open: false,
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
        {
          ..model,
          account_panel_open: !model.account_panel_open,
          password_panel_open: if model.account_panel_open {
            false
          } else {
            model.password_panel_open
          },
        },
      )
    TogglePasswordPanel =>
      (
        @rabbita.none,
        { ..model, password_panel_open: !model.password_panel_open },
      )
    OpenLlmConfig =>
      (
        load_model_options_cmd(dispatch, model.account_ai_provider),
        {
          ..model,
          active_page: LlmConfig,
          account_panel_open: false,
          password_panel_open: false,
          account_model_options: [],
          account_model_options_pending: true,
          account_notice: None,
          notice: None,
        },
      )
    AccountCurrentPasswordChanged(value) =>
      (@rabbita.none, { ..model, account_current_password: value })
    AccountNewPasswordChanged(value) =>
      (@rabbita.none, { ..model, account_new_password: value })
    AccountAiProviderChanged(value) =>
      (
        load_model_options_cmd(dispatch, value),
        {
          ..model,
          account_ai_provider: value,
          account_model_options: [],
          account_model_options_pending: true,
          account_notice: None,
        },
      )
    AccountAiModelChanged(value) =>
      (@rabbita.none, { ..model, account_ai_model: value })
    AccountAiApiKeyChanged(value) =>
      (@rabbita.none, { ..model, account_ai_api_key: value })
    RefreshModelOptions =>
      (
        load_model_options_cmd(dispatch, model.account_ai_provider),
        {
          ..model,
          account_model_options: [],
          account_model_options_pending: true,
          account_notice: None,
        },
      )
    ModelOptionsLoaded(provider, Ok(response)) =>
      if provider != model.account_ai_provider {
        (@rabbita.none, model)
      } else {
        let has_current_model = model_options_include(
          response.items,
          model.account_ai_model,
        )
        let selected_model = if model.account_ai_model != "" &&
          (has_current_model || response.items.length() == 0) {
          model.account_ai_model
        } else {
          match response.items.get(0) {
            Some(item) => item.id
            None => model.account_ai_model
          }
        }
        (
          @rabbita.none,
          {
            ..model,
            account_ai_model: selected_model,
            account_model_options: response.items,
            account_model_options_pending: false,
            account_notice: response.warning,
          },
        )
      }
    ModelOptionsLoaded(provider, Err(error)) =>
      if provider != model.account_ai_provider {
        (@rabbita.none, model)
      } else if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            account_model_options: [],
            account_model_options_pending: false,
            account_notice: Some(
              "Model list could not be loaded. Your saved model is still available.",
            ),
          },
        )
      }
    SaveAiSettings =>
      if !can_save_ai_settings(model) {
        (@rabbita.none, model)
      } else {
        (
          save_ai_settings_cmd(dispatch, model),
          { ..model, account_pending: true, account_notice: None },
        )
      }
    AiSettingsSaved(Ok(settings)) => {
      let current_user = model.current_user.map(fn(user) {
        @sdk.UserSummary::{
          id: user.id,
          email: user.email,
          email_verified: user.email_verified,
          display_name: user.display_name,
          github_login: user.github_login,
          ai_provider: settings.provider,
          ai_model: settings.model,
          ai_api_key_configured: settings.api_key_configured,
          created_at: user.created_at,
        }
      })
      (
        @rabbita.none,
        {
          ..model,
          current_user,
          account_ai_provider: settings.provider,
          account_ai_model: settings.model,
          account_ai_api_key: "",
          account_pending: false,
          account_notice: Some("LLM config saved."),
        },
      )
    }
    AiSettingsSaved(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            account_pending: false,
            account_notice: Some(error.message),
          },
        )
      }
    ChangePassword =>
      if !can_change_password(model) {
        (@rabbita.none, model)
      } else {
        (
          change_password_cmd(dispatch, model),
          { ..model, account_pending: true, account_notice: None },
        )
      }
    PasswordChanged(Ok(response)) =>
      (
        @rabbita.none,
        {
          ..model,
          account_current_password: "",
          account_new_password: "",
          account_ai_api_key: "",
          account_pending: false,
          account_notice: Some(response.message),
          password_panel_open: false,
        },
      )
    PasswordChanged(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            account_pending: false,
            account_notice: Some(error.message),
          },
        )
      }
    ResendEmailVerification =>
      if model.account_pending {
        (@rabbita.none, model)
      } else {
        (
          resend_email_verification_cmd(dispatch),
          { ..model, account_pending: true, account_notice: None },
        )
      }
    EmailVerificationResent(Ok(response)) =>
      (
        @rabbita.none,
        {
          ..model,
          account_pending: false,
          account_notice: Some(response.message),
        },
      )
    EmailVerificationResent(Err(error)) =>
      if is_unauthorized_error(error) {
        auth_recovery(dispatch, model, "Your session expired. Sign in again.")
      } else {
        (
          @rabbita.none,
          {
            ..model,
            account_pending: false,
            account_notice: Some(error.message),
          },
        )
      }
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
          active_page: AppWorkspace,
          selected_project_id: Some(project_id),
          project_detail: None,
          messages: [],
          run_events: [],
          last_run_event_seq: 0,
          run_spinner_tick: 0,
          delete_project_confirming: None,
          notice: None,
        },
      )
    ProjectLoaded(Ok(project)) => {
      let cmd = match project.current_run_id {
        Some(run_id) if project.status is @sdk.Running =>
          @rabbita.batch([
            @rabbita.delay(dispatch(PollRun(project.id, run_id)), 1000),
            dispatch(PollRunEvents(project.id, run_id)),
          ])
        _ => @rabbita.none
      }
      (cmd, { ..model, project_detail: Some(project), notice: None })
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
    CreateProject =>
      if model.create_project_pending || model.current_user is None {
        (@rabbita.none, model)
      } else {
        (
          create_project_cmd(dispatch),
          {
            ..model,
            active_page: AppWorkspace,
            create_project_pending: true,
            delete_project_confirming: None,
            notice: None,
          },
        )
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
          active_page: AppWorkspace,
          create_project_pending: false,
          selected_project_id: Some(project.id),
          project_detail: Some(project),
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
            },
          )
        }
        _ => (@rabbita.none, model)
      }
    RunCreated(Ok(response)) =>
      match response.poll_after_ms {
        Some(delay_ms) if response.run.state is @sdk.Running =>
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
            notice: Some(error_notice("The request could not be sent.", error)),
          },
        )
      }
    PollRun(project_id, run_id) =>
      (load_run_cmd(dispatch, project_id, run_id), model)
    RunLoaded(project_id, run_id, Ok(run)) =>
      if run.state is @sdk.Running {
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
          { ..model, run_status: Some(run), notice: None },
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
