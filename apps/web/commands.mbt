///|
fn load_theme_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  @cmd.custom_cmd(fn(scheduler) {
    js_load_theme_mode(succeed=(mode, resolved_mode) => {
      scheduler.add(
        dispatch(
          ThemeModeLoaded(
            theme_mode_from_string(mode),
            resolved_theme_mode_from_string(resolved_mode),
          ),
        ),
      )
    })
  })
}

///|
fn persist_theme_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  theme_mode : ThemeMode,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(fn(scheduler) {
    js_persist_theme_mode(theme_mode.storage_value(), succeed=resolved_mode => {
      scheduler.add(
        dispatch(
          ThemeModeLoaded(
            theme_mode,
            resolved_theme_mode_from_string(resolved_mode),
          ),
        ),
      )
    })
  })
}

///|
fn load_session_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  get_json(@sdk.session_path(), fn(result) { dispatch(SessionLoaded(result)) })
}

///|
fn load_projects_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  get_json(@sdk.projects_path(), fn(result) { dispatch(ProjectsLoaded(result)) })
}

///|
fn load_messages_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  get_json(@sdk.messages_path(project_id), fn(result) {
    dispatch(MessagesLoaded(result))
  })
}

///|
fn load_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  @rabbita.batch([
    get_json(@sdk.project_path(project_id), fn(result) {
      dispatch(ProjectLoaded(result))
    }),
    load_messages_cmd(dispatch, project_id),
  ])
}

///|
fn create_project_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  let payload : @sdk.CreateProjectRequest = @sdk.CreateProjectRequest::{
    display_name: None,
    template_id: None,
  }
  post_json(@sdk.projects_path(), payload, fn(result) {
    dispatch(ProjectCreated(result))
  })
}

///|
fn create_run_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  content : String,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateRunRequest = @sdk.CreateRunRequest::{ content, }
  post_json(@sdk.create_run_path(project_id), payload, fn(result) {
    dispatch(RunCreated(result))
  })
}

///|
fn delete_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  delete_empty(@sdk.project_path(project_id), fn(result) {
    dispatch(ProjectDeleted(project_id, result))
  })
}

///|
fn load_run_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  run_id : String,
) -> @rabbita.Cmd {
  get_json(@sdk.run_path(project_id, run_id), fn(result) {
    dispatch(RunLoaded(project_id, run_id, result))
  })
}

///|
fn submit_auth_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Cmd {
  match model.auth_mode {
    Login => {
      let payload : @sdk.LoginRequest = @sdk.LoginRequest::{
        email: model.auth_email,
        password: model.auth_password,
      }
      post_json(@sdk.login_path(), payload, fn(result) {
        dispatch(AuthCompleted(result))
      })
    }
    Signup => {
      let payload : @sdk.SignupRequest = @sdk.SignupRequest::{
        email: model.auth_email,
        password: model.auth_password,
        display_name: if model.auth_display_name == "" {
          None
        } else {
          Some(model.auth_display_name)
        },
      }
      post_json(@sdk.signup_path(), payload, fn(result) {
        dispatch(AuthCompleted(result))
      })
    }
    ForgotPassword => {
      let payload : @sdk.RequestPasswordResetRequest = @sdk.RequestPasswordResetRequest::{
        email: model.auth_email,
      }
      post_json(@sdk.request_password_reset_path(), payload, fn(result) {
        dispatch(RequestPasswordResetCompleted(result))
      })
    }
  }
}

///|
fn logout_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  post_empty(@sdk.logout_path(), fn(result) { dispatch(LoggedOut(result)) })
}

///|
fn change_password_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Cmd {
  let payload : @sdk.ChangePasswordRequest = @sdk.ChangePasswordRequest::{
    current_password: model.account_current_password,
    new_password: model.account_new_password,
  }
  post_json(@sdk.change_password_path(), payload, fn(result) {
    dispatch(PasswordChanged(result))
  })
}

///|
fn resend_email_verification_cmd(
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Cmd {
  post_empty_json(@sdk.resend_email_verification_path(), fn(result) {
    dispatch(EmailVerificationResent(result))
  })
}
