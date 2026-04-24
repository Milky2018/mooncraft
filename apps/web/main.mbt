///|
enum AuthMode {
  Login
  Signup
  ForgotPassword
} derive(Eq)

///|
enum ThemeMode {
  Light
  System
  Dark
} derive(Eq)

///|
struct Model {
  boot_requested : Bool
  session_ready : Bool
  theme_mode : ThemeMode
  resolved_theme_mode : ThemeMode
  current_user : @sdk.UserSummary?
  github_enabled : Bool
  auth_mode : AuthMode
  auth_email : String
  auth_password : String
  auth_display_name : String
  auth_pending : Bool
  logout_pending : Bool
  auth_notice : String?
  account_current_password : String
  account_new_password : String
  account_pending : Bool
  account_notice : String?
  account_panel_open : Bool
  password_panel_open : Bool
  projects : Array[@sdk.ProjectSummary]
  selected_project_id : String?
  project_detail : @sdk.ProjectDetail?
  messages : Array[@sdk.ChatMessage]
  run_status : @sdk.RunStatusResponse?
  draft : String
  create_project_pending : Bool
  delete_project_pending : String?
  sending_message : Bool
  notice : String?
}

///|
enum Msg {
  Bootstrap
  ThemeModeLoaded(ThemeMode, ThemeMode)
  ToggleTheme
  SessionLoaded(Result[@sdk.SessionResponse, @sdk.ApiError])
  AuthModeSelected(AuthMode)
  AuthEmailChanged(String)
  AuthPasswordChanged(String)
  AuthDisplayNameChanged(String)
  SubmitAuth
  AuthCompleted(Result[@sdk.AuthResponse, @sdk.ApiError])
  RequestPasswordResetCompleted(Result[@sdk.AuthActionResponse, @sdk.ApiError])
  Logout
  LoggedOut(Result[Unit, @sdk.ApiError])
  ToggleAccountPanel
  TogglePasswordPanel
  AccountCurrentPasswordChanged(String)
  AccountNewPasswordChanged(String)
  ChangePassword
  PasswordChanged(Result[@sdk.AuthActionResponse, @sdk.ApiError])
  ResendEmailVerification
  EmailVerificationResent(Result[@sdk.AuthActionResponse, @sdk.ApiError])
  ProjectsLoaded(Result[@sdk.ListProjectsResponse, @sdk.ApiError])
  SelectProject(String)
  ProjectLoaded(Result[@sdk.ProjectDetail, @sdk.ApiError])
  MessagesLoaded(Result[@sdk.ListMessagesResponse, @sdk.ApiError])
  DraftChanged(String)
  CreateProject
  DeleteProject(String)
  ProjectCreated(Result[@sdk.CreateProjectResponse, @sdk.ApiError])
  ProjectDeleted(String, Result[Unit, @sdk.ApiError])
  SendDraft
  RunCreated(Result[@sdk.CreateRunResponse, @sdk.ApiError])
  PollRun(String, String)
  RunLoaded(String, String, Result[@sdk.RunStatusResponse, @sdk.ApiError])
}

///|
priv suberror BootstrapSubscription {
  ScheduleBootstrap(@rabbita.Cmd)
}

///|
fn ThemeMode::storage_value(self : ThemeMode) -> String {
  match self {
    Light => "light"
    System => "system"
    Dark => "dark"
  }
}

///|
fn ThemeMode::next(self : ThemeMode) -> ThemeMode {
  match self {
    Light => System
    System => Dark
    Dark => Light
  }
}

///|
fn ThemeMode::label(self : ThemeMode) -> String {
  match self {
    Light => "Light"
    System => "System"
    Dark => "Dark"
  }
}

///|
fn theme_mode_from_string(value : String) -> ThemeMode {
  if value == "light" {
    Light
  } else if value == "system" {
    System
  } else {
    Dark
  }
}

///|
fn resolved_theme_mode_from_string(value : String) -> ThemeMode {
  if value == "light" {
    Light
  } else {
    Dark
  }
}

///|
fn resolved_theme_fallback(
  theme_mode : ThemeMode,
  fallback : ThemeMode,
) -> ThemeMode {
  match theme_mode {
    Light => Light
    Dark => Dark
    System => fallback
  }
}

///|
fn initial_model() -> Model {
  {
    boot_requested: false,
    session_ready: false,
    theme_mode: System,
    resolved_theme_mode: Dark,
    current_user: None,
    github_enabled: false,
    auth_mode: Signup,
    auth_email: "",
    auth_password: "",
    auth_display_name: "",
    auth_pending: false,
    logout_pending: false,
    auth_notice: None,
    account_current_password: "",
    account_new_password: "",
    account_pending: false,
    account_notice: None,
    account_panel_open: false,
    password_panel_open: false,
    projects: [],
    selected_project_id: None,
    project_detail: None,
    messages: [],
    run_status: None,
    draft: "",
    create_project_pending: false,
    delete_project_pending: None,
    sending_message: false,
    notice: None,
  }
}

///|
fn subscriptions(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @sub.Sub {
  if model.boot_requested {
    return @sub.none
  }
  @sub.custom_sub(
    "bootstrap",
    @sub.Local,
    ScheduleBootstrap(dispatch(Bootstrap)),
    @sub.SubLoader((payload, scheduler) => {
      match payload {
        ScheduleBootstrap(cmd) => {
          scheduler.add(cmd)
          None
        }
        _ => None
      }
    }),
  )
}

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
    Some(run) if run.state is @sdk.Running => Some(run)
    _ =>
      match model.project_detail {
        Some(project) if project.status is @sdk.Running =>
          match project.current_run_id {
            Some(run_id) =>
              Some(@sdk.RunStatusResponse::{
                run_id,
                project_id: project.id,
                state: @sdk.Running,
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
fn can_submit_auth(model : Model) -> Bool {
  let has_required_fields = if model.auth_mode is ForgotPassword {
    true
  } else {
    model.auth_password != ""
  }
  model.auth_email.trim() != "" && !model.auth_pending && has_required_fields
}

///|
fn can_change_password(model : Model) -> Bool {
  model.account_current_password != "" &&
  model.account_new_password != "" &&
  !model.account_pending
}

///|
fn append_local_user_message(
  model : Model,
  project_id : String,
  content : String,
) -> Array[@sdk.ChatMessage] {
  let messages = model.messages.copy()
  messages.push(@sdk.ChatMessage::{
    id: "local-" + content.length().to_string(),
    project_id,
    run_id: None,
    role: @sdk.User,
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
  if !(run.state is @sdk.Failed) {
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
  error.code == @sdk.Unauthorized
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
    draft: "",
    create_project_pending: false,
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
    auth_pending: false,
    logout_pending: false,
    account_pending: false,
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
      auth_pending: false,
      logout_pending: false,
      account_current_password: "",
      account_new_password: "",
      account_pending: false,
      account_notice: None,
      account_panel_open: false,
      password_panel_open: false,
      auth_notice: Some(message),
    },
  )
}

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
          account_panel_open: if model.auth_mode is Signup {
            true
          } else {
            model.account_panel_open
          },
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
    AccountCurrentPasswordChanged(value) =>
      (@rabbita.none, { ..model, account_current_password: value })
    AccountNewPasswordChanged(value) =>
      (@rabbita.none, { ..model, account_new_password: value })
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
          notice: None,
        },
      )
    ProjectLoaded(Ok(project)) => {
      let cmd = match project.current_run_id {
        Some(run_id) if project.status is @sdk.Running =>
          @rabbita.delay(dispatch(PollRun(project.id, run_id)), 1000)
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
          { ..model, create_project_pending: true, notice: None },
        )
      }
    DeleteProject(project_id) =>
      if model.delete_project_pending is Some(_) {
        (@rabbita.none, model)
      } else {
        (
          delete_project_cmd(dispatch, project_id),
          { ..model, delete_project_pending: Some(project_id), notice: None },
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
          selected_project_id: Some(project.id),
          project_detail: Some(project),
          messages: [],
          run_status: None,
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
          draft: "",
          delete_project_pending: None,
        }
      } else {
        { ..model, delete_project_pending: None }
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
          let content = model.draft.trim().to_string()
          (
            create_run_cmd(dispatch, project_id, content),
            {
              ..model,
              draft: "",
              sending_message: true,
              notice: None,
              messages: append_local_user_message(model, project_id, content),
            },
          )
        }
        _ => (@rabbita.none, model)
      }
    RunCreated(Ok(response)) =>
      match response.poll_after_ms {
        Some(delay_ms) if response.run.state is @sdk.Running =>
          (
            @rabbita.delay(
              dispatch(PollRun(response.run.project_id, response.run.run_id)),
              delay_ms,
            ),
            { ..model, run_status: Some(response.run), sending_message: false },
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
          @rabbita.delay(dispatch(PollRun(project_id, run_id)), 1000),
          { ..model, run_status: Some(run) },
        )
      } else {
        (
          @rabbita.batch([
            load_projects_cmd(dispatch),
            load_project_cmd(dispatch, project_id),
          ]),
          { ..model, run_status: Some(run), notice: None },
        )
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

///|
fn mono_style() -> Array[String] {
  ["font-family: \"IBM Plex Mono\", \"SFMono-Regular\", Menlo, monospace"]
}

///|
fn theme_variables(theme_mode : ThemeMode) -> Array[String] {
  match theme_mode {
    System => theme_variables(Dark)
    Dark =>
      [
        "--page-bg: #101113", "--page-bg-alt: #111214", "--sidebar-bg: #17181a",
        "--surface-1: #17181b", "--surface-2: #1c1d20", "--surface-3: #222328", "--surface-raised: #25262b",
        "--preview-bg: #111214", "--border-soft: rgba(255, 255, 255, 0.09)", "--border-strong: rgba(47, 132, 255, 0.72)",
        "--text-1: #f4f4f5", "--text-2: #c7c7cb", "--text-3: #8c8e95", "--accent: #0b8f7f",
        "--accent-strong: #007f72", "--accent-soft: rgba(0, 127, 114, 0.18)", "--action: #2f84ff",
        "--action-strong: #136dff", "--action-soft: rgba(47, 132, 255, 0.20)", "--on-action: #ffffff",
        "--danger: #ff7a7a", "--danger-soft: rgba(255, 122, 122, 0.12)", "--warning: #ffcf66",
        "--warning-soft: rgba(255, 207, 102, 0.12)", "--shadow: 0 10px 24px rgba(0, 0, 0, 0.22), 0 0 0 1px rgba(255, 255, 255, 0.02)",
        "--badge-idle-bg: rgba(115, 137, 160, 0.14)", "--badge-idle-fg: #a7bad0",
        "--badge-running-bg: rgba(45, 125, 255, 0.16)", "--badge-running-fg: #91c0ff",
        "--badge-success-bg: rgba(18, 216, 156, 0.14)", "--badge-success-fg: #7af0c6",
        "--badge-failed-bg: rgba(255, 122, 122, 0.14)", "--badge-failed-fg: #ffb0b0",
        "color-scheme: dark",
      ]
    Light =>
      [
        "--page-bg: #f4f6f8", "--page-bg-alt: #ffffff", "--sidebar-bg: #eef1f5",
        "--surface-1: #ffffff", "--surface-2: #f6f8fb", "--surface-3: #edf1f5", "--surface-raised: #ffffff",
        "--preview-bg: #f7f9fc", "--border-soft: rgba(25, 35, 48, 0.14)", "--border-strong: rgba(47, 132, 255, 0.54)",
        "--text-1: #121821", "--text-2: #3f4b5a", "--text-3: #707b8a", "--accent: #087b6d",
        "--accent-strong: #006e63", "--accent-soft: rgba(0, 110, 99, 0.12)", "--action: #1f73e8",
        "--action-strong: #155fd0", "--action-soft: rgba(31, 115, 232, 0.14)", "--on-action: #ffffff",
        "--danger: #b94747", "--danger-soft: rgba(185, 71, 71, 0.10)", "--warning: #9b6b10",
        "--warning-soft: rgba(155, 107, 16, 0.12)", "--shadow: 0 10px 24px rgba(24, 36, 52, 0.10), 0 0 0 1px rgba(25, 35, 48, 0.03)",
        "--badge-idle-bg: rgba(92, 110, 130, 0.12)", "--badge-idle-fg: #526173",
        "--badge-running-bg: rgba(31, 115, 232, 0.12)", "--badge-running-fg: #175ab9",
        "--badge-success-bg: rgba(0, 110, 99, 0.12)", "--badge-success-fg: #075f56",
        "--badge-failed-bg: rgba(185, 71, 71, 0.12)", "--badge-failed-fg: #9d3838",
        "color-scheme: light",
      ]
  }
}

///|
fn app_root_style(theme_mode : ThemeMode) -> Array[String] {
  theme_variables(theme_mode) +
  [
    "min-height: 100vh", "padding: 0", "background-color: var(--page-bg)", "background-image: linear-gradient(180deg, var(--page-bg-alt), var(--page-bg))",
    "background-size: auto", "color: var(--text-1)", "font-family: \"IBM Plex Sans\", \"Avenir Next\", \"Segoe UI\", sans-serif",
  ]
}

///|
fn app_stack_style() -> Array[String] {
  [
    "min-height: calc(100vh - 24px)", "display: flex", "flex-direction: column",
    "gap: 10px", "padding: 12px",
  ]
}

///|
fn panel_style() -> Array[String] {
  [
    "background: var(--surface-1)", "border: 1px solid var(--border-soft)", "border-radius: 8px",
    "box-shadow: var(--shadow)", "overflow: hidden", "backdrop-filter: blur(14px)",
  ]
}

///|
fn inset_panel_style() -> Array[String] {
  [
    "background: var(--surface-2)", "border: 1px solid var(--border-soft)", "border-radius: 6px",
  ]
}

///|
fn section_label_style() -> Array[String] {
  mono_style() +
  [
    "font-size: 12px", "letter-spacing: 0.08em", "text-transform: uppercase", "color: var(--text-3)",
    "font-weight: 700",
  ]
}

///|
fn button_style(
  background : String,
  foreground : String,
  enabled : Bool,
) -> Array[String] {
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  [
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "gap: 10px",
    "padding: 10px 14px",
    "border: 1px solid var(--border-soft)",
    "border-radius: 6px",
    "background: " + background,
    "color: " + foreground,
    "font-size: 14px",
    "font-weight: 700",
    "cursor: " + cursor,
    "opacity: " + opacity,
    "transition: opacity 120ms ease, transform 120ms ease",
  ]
}

///|
fn primary_button_style(enabled : Bool) -> Array[String] {
  button_style(
    "linear-gradient(135deg, var(--action-strong), var(--action))", "var(--on-action)",
    enabled,
  ) +
  ["box-shadow: 0 8px 18px var(--action-soft)"]
}

///|
fn secondary_button_style(enabled : Bool) -> Array[String] {
  button_style("var(--surface-3)", "var(--text-1)", enabled)
}

///|
fn subtle_danger_button_style(enabled : Bool) -> Array[String] {
  let foreground = if enabled { "var(--danger)" } else { "var(--text-3)" }
  let border_color = if enabled {
    "rgba(255, 122, 122, 0.18)"
  } else {
    "var(--border-soft)"
  }
  let background = if enabled {
    "rgba(255, 122, 122, 0.06)"
  } else {
    "transparent"
  }
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  mono_style() +
  [
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "padding: 8px 10px",
    "border: 1px solid " + border_color,
    "border-radius: 5px",
    "background: " + background,
    "color: " + foreground,
    "font-size: 11px",
    "font-weight: 700",
    "letter-spacing: 0.06em",
    "text-transform: uppercase",
    "cursor: " + cursor,
    "opacity: " + opacity,
  ]
}

///|
fn input_style(disabled : Bool) -> Array[String] {
  let border_color = if disabled {
    "var(--border-soft)"
  } else {
    "var(--border-strong)"
  }
  let background = if disabled {
    "var(--surface-3)"
  } else {
    "var(--surface-2)"
  }
  [
    "width: 100%",
    "padding: 12px 14px",
    "border: 1px solid " + border_color,
    "border-radius: 6px",
    "background: " + background,
    "font-size: 15px",
    "line-height: 1.5",
    "color: var(--text-1)",
    "outline: none",
    "box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.02)",
  ]
}

///|
fn status_badge(state : @sdk.RunState) -> @rabbita.Html {
  let (background, foreground) = match state {
    @sdk.Idle => ("var(--badge-idle-bg)", "var(--badge-idle-fg)")
    @sdk.Running => ("var(--badge-running-bg)", "var(--badge-running-fg)")
    @sdk.Succeeded => ("var(--badge-success-bg)", "var(--badge-success-fg)")
    @sdk.Failed => ("var(--badge-failed-bg)", "var(--badge-failed-fg)")
  }
  @html.div(
    style=mono_style() +
      [
        "padding: 6px 10px",
        "border-radius: 6px",
        "background: " + background,
        "color: " + foreground,
        "font-size: 11px",
        "font-weight: 700",
        "letter-spacing: 0.06em",
        "text-transform: uppercase",
        "border: 1px solid var(--border-soft)",
      ],
    state.label(),
  )
}

///|
fn logo_asset_url() -> String {
  "/assets/logo.svg"
}

///|
fn brand_logo(size : Int) -> @rabbita.Html {
  let px = size.to_string() + "px"
  @html.div(
    style=[
      "width: " + px,
      "height: " + px,
      "display: grid",
      "place-items: center",
      "border-radius: 6px",
      "background: #05080c",
      "border: 1px solid var(--border-soft)",
      "overflow: hidden",
      "flex-shrink: 0",
    ],
    @html.img(
      src=logo_asset_url(),
      alt="MoonBit Cloud logo",
      loading="eager",
      decoding="async",
      style=["width: 100%", "height: 100%", "object-fit: contain"],
      "",
    ),
  )
}

///|
fn user_name(model : Model) -> String {
  match model.current_user {
    Some(user) => user.display_name
    None => "Operator"
  }
}

///|
fn project_headline(model : Model) -> String {
  match model.project_detail {
    Some(project) => project.display_name
    None =>
      if model.projects.length() == 0 {
        "No project selected"
      } else {
        "Workspace"
      }
  }
}

///|
fn active_project_status(model : Model) -> @sdk.RunState {
  match model.project_detail {
    Some(project) => project.status
    None => if active_run(model) is Some(_) { @sdk.Running } else { @sdk.Idle }
  }
}

///|
fn theme_toggle_button(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    on_click=dispatch(ToggleTheme),
    style=secondary_button_style(true),
    "Theme: " + model.theme_mode.label(),
  )
}

///|
fn render_app_header(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=panel_style() +
      [
        "padding: 12px 14px", "display: flex", "align-items: center", "justify-content: space-between",
        "gap: 12px",
      ],
    [
      @html.div(style=["display: flex", "align-items: center", "gap: 10px"], [
        brand_logo(38),
        @html.div(
          style=[
            "font-size: 22px", "font-weight: 780", "letter-spacing: -0.02em",
          ],
          "MoonBit Cloud",
        ),
      ]),
      theme_toggle_button(dispatch, model),
    ],
  )
}

///|
fn auth_mode_button(
  dispatch : @rabbita.Dispatch[Msg],
  current : AuthMode,
  value : AuthMode,
  label : String,
) -> @rabbita.Html {
  let active = current == value
  @html.button(
    type_="button",
    on_click=dispatch(AuthModeSelected(value)),
    style=button_style(
        if active {
          "linear-gradient(135deg, var(--action-strong), var(--action))"
        } else {
          "transparent"
        },
        if active {
          "var(--on-action)"
        } else {
          "var(--text-2)"
        },
        true,
      ) +
      ["flex: 1"],
    label,
  )
}

///|
fn auth_field(
  label : String,
  field_id : String,
  input_type : @html.InputType,
  value : String,
  placeholder : String,
  on_input : (String) -> Msg,
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Html {
  @html.div(style=["display: flex", "flex-direction: column", "gap: 8px"], [
    @html.label(for_=field_id, style=section_label_style(), label),
    @html.input(
      input_type~,
      id=field_id,
      value~,
      placeholder~,
      on_input=fn(next) { dispatch(on_input(next)) },
      style=input_style(false),
      "",
    ),
  ])
}

///|
fn render_notice_card(notice : String?, tone : String) -> @rabbita.Html {
  match notice {
    Some(message) =>
      @html.div(
        style=[
          "padding: 12px 14px",
          "border-radius: 6px",
          "background: " + tone,
          "border: 1px solid var(--border-soft)",
          "font-size: 14px",
          "line-height: 1.6",
          "color: var(--text-1)",
        ],
        message,
      )
    None => @html.nothing
  }
}

///|
fn render_auth_screen(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let title = match model.auth_mode {
    Login => "Return to the workspace"
    Signup => "Build apps without opening the code"
    ForgotPassword => "Reset your password"
  }
  let subtitle = match model.auth_mode {
    Login => "Sign in to resume your projects and previews."
    Signup =>
      "Describe what you want, let the agent update the workspace, and watch the preview."
    ForgotPassword => "Enter your email and use the local outbox reset link."
  }
  let submit_label = if model.auth_pending {
    "Working..."
  } else {
    match model.auth_mode {
      Login => "Log In"
      Signup => "Create Account"
      ForgotPassword => "Send Reset Link"
    }
  }
  @html.div(
    style=[
      "display: flex", "flex-wrap: wrap", "gap: 10px", "align-items: stretch", "flex: 1",
    ],
    [
      @html.div(
        style=panel_style() +
          [
            "flex: 1 1 360px", "min-width: 320px", "padding: 22px", "display: flex",
            "flex-direction: column", "gap: 12px", "justify-content: center",
          ],
        [
          @html.div(
            style=[
              "font-size: 42px", "line-height: 1.02", "font-weight: 780", "max-width: 620px",
            ],
            title,
          ),
          @html.div(
            style=[
              "font-size: 17px", "line-height: 1.7", "color: var(--text-2)", "max-width: 620px",
            ],
            subtitle,
          ),
        ],
      ),
      @html.div(
        style=panel_style() +
          [
            "flex: 1 1 420px", "min-width: 320px", "max-width: 560px", "padding: 22px",
            "display: flex", "flex-direction: column", "gap: 14px",
          ],
        [
          @html.div(
            style=[
              "display: flex", "gap: 6px", "padding: 4px", "border-radius: 8px",
              "background: var(--surface-3)", "border: 1px solid var(--border-soft)",
            ],
            [
              auth_mode_button(dispatch, model.auth_mode, Signup, "Sign Up"),
              auth_mode_button(dispatch, model.auth_mode, Login, "Log In"),
            ],
          ),
          render_notice_card(model.auth_notice, "var(--danger-soft)"),
          auth_field(
            "Email",
            "auth-email",
            @html.Email,
            model.auth_email,
            "name@example.com",
            fn(value) { AuthEmailChanged(value) },
            dispatch,
          ),
          if model.auth_mode is ForgotPassword {
            @html.nothing
          } else {
            auth_field(
              "Password",
              "auth-password",
              @html.Password,
              model.auth_password,
              "At least 8 characters",
              fn(value) { AuthPasswordChanged(value) },
              dispatch,
            )
          },
          if model.auth_mode is Signup {
            auth_field(
              "Display Name",
              "auth-display-name",
              @html.Text,
              model.auth_display_name,
              "Optional operator name",
              fn(value) { AuthDisplayNameChanged(value) },
              dispatch,
            )
          } else {
            @html.nothing
          },
          if model.auth_mode is Login {
            @html.button(
              type_="button",
              on_click=dispatch(AuthModeSelected(ForgotPassword)),
              style=[
                "align-self: flex-start", "border: none", "background: transparent",
                "color: var(--text-2)", "padding: 0", "font-size: 13px", "font-weight: 700",
                "cursor: pointer",
              ],
              "Forgot password?",
            )
          } else if model.auth_mode is ForgotPassword {
            @html.button(
              type_="button",
              on_click=dispatch(AuthModeSelected(Login)),
              style=[
                "align-self: flex-start", "border: none", "background: transparent",
                "color: var(--text-2)", "padding: 0", "font-size: 13px", "font-weight: 700",
                "cursor: pointer",
              ],
              "Back to log in",
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            disabled=!can_submit_auth(model),
            on_click=dispatch(SubmitAuth),
            style=primary_button_style(can_submit_auth(model)),
            submit_label,
          ),
          if model.github_enabled && !(model.auth_mode is ForgotPassword) {
            @html.fragment([
              @html.div(
                style=[
                  "display: flex", "align-items: center", "gap: 12px", "color: var(--text-3)",
                ],
                [
                  @html.div(
                    style=[
                      "flex: 1", "height: 1px", "background: var(--border-soft)",
                    ],
                    "",
                  ),
                  @html.div(style=section_label_style(), "or"),
                  @html.div(
                    style=[
                      "flex: 1", "height: 1px", "background: var(--border-soft)",
                    ],
                    "",
                  ),
                ],
              ),
              @html.a(
                href="/auth/github/start",
                style=secondary_button_style(true) +
                  [
                    "text-decoration: none", "justify-content: center", "padding: 12px 14px",
                  ],
                "Continue with GitHub",
              ),
            ])
          } else {
            @html.nothing
          },
        ],
      ),
    ],
  )
}

///|
fn render_message(message : @sdk.ChatMessage) -> @rabbita.Html {
  let is_user = message.role is @sdk.User
  let bubble_background = if is_user {
    "linear-gradient(135deg, var(--action-strong), var(--action))"
  } else {
    "var(--surface-2)"
  }
  let bubble_foreground = if is_user {
    "var(--on-action)"
  } else {
    "var(--text-1)"
  }
  let justify = if is_user { "flex-end" } else { "flex-start" }
  let bubble_border = if is_user {
    "rgba(255,255,255,0.08)"
  } else {
    "var(--border-soft)"
  }
  @html.div(
    style=["display: flex", "justify-content: " + justify],
    @html.div(
      style=[
        "max-width: min(720px, 88%)",
        "padding: 14px 16px",
        "border-radius: 6px",
        "background: " + bubble_background,
        "color: " + bubble_foreground,
        "border: 1px solid " + bubble_border,
        "box-shadow: 0 8px 18px rgba(0, 0, 0, 0.14)",
      ],
      [
        @html.div(
          style=mono_style() +
            [
              "font-size: 11px", "letter-spacing: 0.08em", "text-transform: uppercase",
              "opacity: 0.86", "margin-bottom: 8px", "font-weight: 700",
            ],
          message.role.label(),
        ),
        @html.div(
          style=["font-size: 15px", "line-height: 1.7", "white-space: pre-wrap"],
          message.content,
        ),
      ],
    ),
  )
}

///|
fn render_run_banner(model : Model) -> @rabbita.Html {
  match active_run(model) {
    Some(run) =>
      @html.div(
        style=[
          "padding: 10px 12px", "border-radius: 6px", "background: var(--action-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "justify-content: space-between",
          "align-items: center", "gap: 12px",
        ],
        [
          @html.div(
            style=[
              "font-size: 14px", "font-weight: 700", "color: var(--text-1)",
            ],
            "Updating preview...",
          ),
          status_badge(run.state),
        ],
      )
    None => @html.nothing
  }
}

///|
fn ui_empty_to_none(value : String) -> String? {
  if value == "" {
    None
  } else {
    Some(value)
  }
}

///|
fn debug_value_row(label : String, value : String?) -> @rabbita.Html {
  match value {
    Some(text) if text != "" =>
      @html.div(
        style=[
          "display: grid", "grid-template-columns: 120px minmax(0, 1fr)", "gap: 10px",
          "font-size: 12px", "line-height: 1.5",
        ],
        [
          @html.div(
            style=mono_style() + ["color: var(--text-3)", "font-weight: 700"],
            label,
          ),
          @html.div(
            style=mono_style() +
              [
                "color: var(--text-2)", "overflow-wrap: anywhere", "white-space: pre-wrap",
              ],
            text,
          ),
        ],
      )
    _ => @html.nothing
  }
}

///|
fn optional_int_text(value : Int?) -> String? {
  match value {
    Some(number) => Some(number.to_string())
    None => None
  }
}

///|
fn render_run_failure_debug(run : @sdk.RunStatusResponse) -> @rabbita.Html {
  match run.failure_debug {
    Some(debug) =>
      @html.div(
        style=[
          "padding: 12px", "border-radius: 10px", "background: var(--surface-3)",
          "border: 1px solid var(--border-soft)", "display: flex", "flex-direction: column",
          "gap: 8px",
        ],
        [
          debug_value_row("Stage", ui_empty_to_none(debug.stage)),
          debug_value_row("Exit Code", optional_int_text(debug.exit_code)),
          debug_value_row("Command", debug.command),
          debug_value_row("Codex Log", debug.codex_log_path),
          debug_value_row("Validation Log", debug.validation_log_path),
          debug_value_row("Final Summary", debug.final_summary_path),
        ],
      )
    None => @html.nothing
  }
}

///|
fn render_run_failure_detail(
  summary : String,
  details : String?,
) -> @rabbita.Html {
  match details {
    Some(text) if text != "" && text != summary =>
      @html.div(style=["display: flex", "flex-direction: column", "gap: 8px"], [
        @html.div(
          style=["font-size: 12px", "font-weight: 760", "color: var(--text-2)"],
          "Failure detail",
        ),
        @html.div(
          style=mono_style() +
            [
              "padding: 12px", "border-radius: 10px", "background: var(--surface-2)",
              "border: 1px solid var(--border-soft)", "font-size: 12px", "line-height: 1.5",
              "color: var(--text-2)", "white-space: pre-wrap", "overflow-wrap: anywhere",
            ],
          text,
        ),
      ])
    _ => @html.nothing
  }
}

///|
fn render_run_failure_card(model : Model) -> @rabbita.Html {
  match model.run_status {
    Some(run) if run.state is @sdk.Failed => {
      let summary = run_failure_summary(run).unwrap_or(
        "The run failed before the preview could be refreshed.",
      )
      @html.div(
        style=[
          "padding: 14px 16px", "border-radius: 12px", "background: var(--danger-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "flex-direction: column",
          "gap: 12px",
        ],
        [
          @html.div(
            style=[
              "font-size: 14px", "font-weight: 760", "color: var(--text-1)",
            ],
            "Run failed",
          ),
          @html.div(
            style=[
              "font-size: 14px", "line-height: 1.6", "color: var(--text-1)", "white-space: pre-wrap",
            ],
            summary,
          ),
          render_run_failure_debug(run),
          render_run_failure_detail(summary, run.error_message),
        ],
      )
    }
    _ => @html.nothing
  }
}

///|
fn render_workspace_empty(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.selected_project_id {
    None =>
      @html.div(
        style=inset_panel_style() +
          [
            "padding: 18px", "display: flex", "flex-direction: column", "gap: 10px",
          ],
        [
          @html.div(
            style=["font-size: 24px", "line-height: 1.12", "font-weight: 760"],
            "Create a project to start.",
          ),
          @html.div(
            style=[
              "font-size: 15px", "line-height: 1.6", "color: var(--text-2)",
            ],
            "Then describe the first change you want.",
          ),
          @html.button(
            type_="button",
            disabled=model.create_project_pending,
            on_click=dispatch(CreateProject),
            style=primary_button_style(!model.create_project_pending),
            if model.create_project_pending {
              "Creating..."
            } else {
              "Create Project"
            },
          ),
        ],
      )
    Some(_) =>
      @html.div(
        style=inset_panel_style() +
          [
            "padding: 14px", "display: flex", "flex-direction: column", "gap: 8px",
          ],
        [
          @html.div(
            style=["font-size: 18px", "font-weight: 720"],
            "No messages yet.",
          ),
          @html.div(
            style=[
              "font-size: 15px", "line-height: 1.6", "color: var(--text-2)",
            ],
            "Describe the first change you want.",
          ),
        ],
      )
  }
}

///|
fn render_workspace_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let send_enabled = can_send(model)
  let composer_placeholder = if model.selected_project_id is Some(_) {
    "Describe the change you want."
  } else {
    "Create a project first."
  }
  let messages = if model.messages.length() == 0 {
    [render_workspace_empty(dispatch, model)]
  } else {
    model.messages.map(render_message)
  }
  @html.div(
    style=panel_style() +
      [
        "flex: 1 1 620px", "min-width: 360px", "display: flex", "flex-direction: column",
        "min-height: 720px",
      ],
    [
      @html.div(
        style=[
          "padding: 16px 18px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
          "justify-content: space-between", "align-items: flex-start", "gap: 12px",
          "flex-wrap: wrap",
        ],
        [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
            [
              @html.div(
                style=[
                  "font-size: 38px", "line-height: 1.02", "font-weight: 780",
                ],
                project_headline(model),
              ),
            ],
          ),
          status_badge(active_project_status(model)),
        ],
      ),
      @html.div(
        style=[
          "padding: 12px 18px 0", "display: flex", "flex-direction: column", "gap: 8px",
        ],
        [
          render_notice_card(model.notice, "var(--warning-soft)"),
          render_run_banner(model),
          render_run_failure_card(model),
        ],
      ),
      @html.div(
        style=[
          "flex: 1", "min-height: 0", "padding: 12px 18px", "display: flex", "flex-direction: column",
          "gap: 10px", "overflow-y: auto",
        ],
        messages,
      ),
      @html.div(
        style=[
          "padding: 14px 18px 18px", "border-top: 1px solid var(--border-soft)",
          "display: flex", "flex-direction: column", "gap: 10px",
        ],
        [
          @html.textarea(
            rows=6,
            value=model.draft,
            disabled=model.selected_project_id is None ||
              active_run(model) is Some(_),
            placeholder=composer_placeholder,
            on_input=fn(value) { dispatch(DraftChanged(value)) },
            style=input_style(
                model.selected_project_id is None ||
                active_run(model) is Some(_),
              ) +
              ["min-height: 164px", "resize: vertical"],
            "",
          ),
          @html.div(
            style=[
              "display: flex", "justify-content: flex-end", "align-items: center",
              "gap: 12px", "flex-wrap: wrap",
            ],
            [
              @html.button(
                type_="button",
                disabled=!send_enabled,
                on_click=dispatch(SendDraft),
                style=primary_button_style(send_enabled),
                if active_run(model) is Some(_) {
                  "Working..."
                } else {
                  "Send Request"
                },
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
fn render_preview_empty(model : Model) -> @rabbita.Html {
  let project_error = model.project_detail.bind(fn(project) {
    project.last_error
  })
  let helper_copy = match model.project_detail {
    None => "Select a project to see its preview."
    Some(_) =>
      if active_run(model) is Some(_) {
        "The preview will appear when the run finishes."
      } else {
        "No preview yet. Send a request to build the app."
      }
  }
  @html.div(
    style=[
      "height: 100%", "padding: 14px", "display: flex", "flex-direction: column",
      "gap: 10px",
    ],
    [
      @html.div(
        style=inset_panel_style() +
          [
            "padding: 14px", "display: flex", "flex-direction: column", "gap: 8px",
            "min-height: 220px", "justify-content: center",
          ],
        [
          @html.div(
            style=["font-size: 24px", "line-height: 1.12", "font-weight: 760"],
            "Preview",
          ),
          @html.div(
            style=[
              "font-size: 15px", "line-height: 1.6", "color: var(--text-2)",
            ],
            helper_copy,
          ),
        ],
      ),
      render_notice_card(project_error, "var(--danger-soft)"),
    ],
  )
}

///|
fn preview_url_with_theme(url : String, theme_mode : ThemeMode) -> String {
  let separator = if url.contains("?") { "&" } else { "?" }
  url + separator + "theme=" + theme_mode.storage_value()
}

///|
fn render_preview_panel(model : Model) -> @rabbita.Html {
  let preview = model.project_detail.bind(fn(project) { project.preview })
  let status = match preview {
    Some(target) => if target.healthy { @sdk.Succeeded } else { @sdk.Failed }
    None => if active_run(model) is Some(_) { @sdk.Running } else { @sdk.Idle }
  }
  @html.div(
    style=panel_style() +
      [
        "flex: 1 1 420px", "min-width: 320px", "display: flex", "flex-direction: column",
        "min-height: 720px",
      ],
    [
      @html.div(
        style=[
          "padding: 16px 18px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
          "justify-content: space-between", "align-items: flex-start", "gap: 12px",
          "flex-wrap: wrap",
        ],
        [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
            [
              @html.div(
                style=[
                  "font-size: 38px", "line-height: 1.02", "font-weight: 780",
                ],
                "Preview",
              ),
            ],
          ),
          status_badge(status),
        ],
      ),
      @html.div(
        style=[
          "flex: 1", "min-height: 0", "background: linear-gradient(180deg, var(--surface-2), var(--surface-3))",
        ],
        match preview {
          Some(target) =>
            @html.div(
              style=["height: 100%"],
              @html.iframe(
                title="Live Preview",
                src=preview_url_with_theme(
                  target.url,
                  model.resolved_theme_mode,
                ),
                loading="eager",
                style=[
                  "height: 100%", "width: 100%", "border: none", "background: var(--preview-bg)",
                ],
              ),
            )
          None => render_preview_empty(model)
        },
      ),
    ],
  )
}

///|
fn render_loading_screen() -> @rabbita.Html {
  @html.div(
    style=["display: grid", "place-items: center", "flex: 1"],
    @html.div(
      style=panel_style() +
        [
          "padding: 18px 20px", "display: flex", "flex-direction: column", "gap: 8px",
          "min-width: 320px",
        ],
      [
        @html.div(
          style=["font-size: 28px", "line-height: 1.05", "font-weight: 760"],
          "Loading...",
        ),
      ],
    ),
  )
}

///|
fn workspace_name(model : Model) -> String {
  user_name(model) + "'s Workspace"
}

///|
fn avatar_chip(label : String) -> @rabbita.Html {
  @html.div(
    style=[
      "width: 28px", "height: 28px", "border-radius: 999px", "display: grid", "place-items: center",
      "background: var(--accent-strong)", "color: var(--on-action)", "font-size: 13px",
      "font-weight: 760",
    ],
    label,
  )
}

///|
fn sidebar_project_item(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  project : @sdk.ProjectSummary,
) -> @rabbita.Html {
  let selected = model.selected_project_id == Some(project.id)
  let background = if selected { "var(--surface-2)" } else { "transparent" }
  let border_color = if selected {
    "var(--border-strong)"
  } else {
    "transparent"
  }
  let deleting = model.delete_project_pending == Some(project.id)
  let delete_enabled = !(project.status is @sdk.Running || deleting)
  @html.div(
    style=[
      "border: 1px solid " + border_color,
      "border-radius: 6px",
      "background: " + background,
      "padding: 8px",
      "display: flex",
      "flex-direction: column",
      "gap: 8px",
    ],
    [
      @html.button(
        type_="button",
        on_click=dispatch(SelectProject(project.id)),
        style=[
          "width: 100%", "padding: 0", "border: none", "background: transparent",
          "color: var(--text-1)", "cursor: pointer", "display: flex", "align-items: center",
          "gap: 10px", "text-align: left",
        ],
        [
          @html.div(
            style=[
              "width: 30px", "height: 30px", "border-radius: 6px", "background: var(--surface-raised)",
              "border: 1px solid var(--border-soft)",
            ],
            "",
          ),
          @html.div(
            style=[
              "min-width: 0", "display: flex", "flex-direction: column", "gap: 3px",
            ],
            [
              @html.div(
                style=[
                  "font-size: 14px", "font-weight: 720", "white-space: nowrap", "overflow: hidden",
                  "text-overflow: ellipsis",
                ],
                project.display_name,
              ),
              @html.div(
                style=mono_style() + ["font-size: 11px", "color: var(--text-3)"],
                project.status.label(),
              ),
            ],
          ),
        ],
      ),
      if selected || deleting {
        @html.button(
          type_="button",
          disabled=!delete_enabled,
          on_click=dispatch(DeleteProject(project.id)),
          style=subtle_danger_button_style(delete_enabled) +
            ["align-self: flex-start"],
          if deleting {
            "Deleting..."
          } else {
            "Delete"
          },
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn account_password_input(
  value : String,
  placeholder : String,
  on_input : (String) -> Msg,
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Html {
  @html.input(
    input_type=@html.Password,
    value~,
    placeholder~,
    on_input=fn(next) { dispatch(on_input(next)) },
    style=input_style(false) +
      [
        "padding: 9px 10px", "font-size: 13px", "border-color: var(--border-soft)",
      ],
    "",
  )
}

///|
fn render_account_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.current_user {
    Some(user) => {
      let verification_text = if user.email_verified {
        "Verified"
      } else {
        "Verification pending"
      }
      let resend_enabled = !user.email_verified && !model.account_pending
      @html.div(
        style=panel_style() +
          [
            "position: absolute", "right: 0", "top: calc(100% + 8px)", "width: min(360px, calc(100vw - 24px))",
            "padding: 12px", "display: flex", "flex-direction: column", "gap: 10px",
            "z-index: 10",
          ],
        [
          @html.div(
            style=[
              "display: flex", "align-items: center", "justify-content: space-between",
              "gap: 10px",
            ],
            [
              @html.div(
                style=[
                  "display: flex", "flex-direction: column", "gap: 3px", "min-width: 0",
                ],
                [
                  @html.div(style=section_label_style(), "Account"),
                  @html.div(
                    style=[
                      "font-size: 14px", "font-weight: 760", "color: var(--text-1)",
                      "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                    ],
                    user.display_name,
                  ),
                  @html.div(
                    style=mono_style() +
                      [
                        "font-size: 11px", "color: var(--text-3)", "white-space: nowrap",
                        "overflow: hidden", "text-overflow: ellipsis",
                      ],
                    user.email,
                  ),
                ],
              ),
              @html.div(
                style=mono_style() +
                  [
                    "font-size: 11px", "color: var(--text-2)", "padding: 5px 8px",
                    "border: 1px solid var(--border-soft)", "border-radius: 999px",
                    "background: var(--surface-2)", "white-space: nowrap",
                  ],
                verification_text,
              ),
            ],
          ),
          render_notice_card(model.account_notice, "var(--warning-soft)"),
          if user.email_verified {
            @html.nothing
          } else {
            @html.button(
              type_="button",
              disabled=!resend_enabled,
              on_click=dispatch(ResendEmailVerification),
              style=secondary_button_style(resend_enabled) +
                ["padding: 9px 10px", "font-size: 12px"],
              if model.account_pending {
                "Queueing..."
              } else {
                "Resend Verification"
              },
            )
          },
          @html.div(
            style=[
              "display: flex", "align-items: center", "justify-content: space-between",
              "gap: 10px", "padding-top: 8px", "border-top: 1px solid var(--border-soft)",
            ],
            [
              @html.div(
                style=["display: flex", "flex-direction: column", "gap: 3px"],
                [@html.div(style=section_label_style(), "Appearance")],
              ),
              theme_toggle_button(dispatch, model),
            ],
          ),
          @html.button(
            type_="button",
            on_click=dispatch(TogglePasswordPanel),
            style=secondary_button_style(true) +
              ["justify-content: space-between"],
            if model.password_panel_open {
              "Hide Password Form"
            } else {
              "Change Password"
            },
          ),
          if model.password_panel_open {
            @html.div(
              style=[
                "display: flex", "flex-direction: column", "gap: 8px", "padding: 10px",
                "border: 1px solid var(--border-soft)", "border-radius: 6px", "background: var(--surface-2)",
              ],
              [
                account_password_input(
                  model.account_current_password,
                  "Current password",
                  fn(value) { AccountCurrentPasswordChanged(value) },
                  dispatch,
                ),
                account_password_input(
                  model.account_new_password,
                  "New password",
                  fn(value) { AccountNewPasswordChanged(value) },
                  dispatch,
                ),
                @html.button(
                  type_="button",
                  disabled=!can_change_password(model),
                  on_click=dispatch(ChangePassword),
                  style=primary_button_style(can_change_password(model)) +
                    ["padding: 9px 10px", "font-size: 12px"],
                  if model.account_pending {
                    "Updating..."
                  } else {
                    "Save Password"
                  },
                ),
              ],
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            disabled=model.logout_pending,
            on_click=dispatch(Logout),
            style=button_style(
                "var(--surface-2)",
                "var(--text-2)",
                !model.logout_pending,
              ) +
              ["width: 100%", "justify-content: flex-start"],
            if model.logout_pending {
              "Logging out..."
            } else {
              "Log Out"
            },
          ),
        ],
      )
    }
    None => @html.nothing
  }
}

///|
fn render_account_toolbar(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.current_user {
    Some(user) =>
      @html.div(
        style=panel_style() +
          [
            "position: relative", "padding: 10px 12px", "display: flex", "align-items: center",
            "justify-content: space-between", "gap: 10px", "flex-wrap: wrap",
          ],
        [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 2px"],
            [
              @html.div(style=section_label_style(), "Workspace"),
              @html.div(
                style=[
                  "font-size: 15px", "font-weight: 760", "color: var(--text-1)",
                ],
                workspace_name(model),
              ),
            ],
          ),
          @html.div(
            style=[
              "display: flex", "align-items: center", "justify-content: flex-end",
              "gap: 8px", "flex-wrap: wrap", "position: relative",
            ],
            [
              @html.button(
                type_="button",
                on_click=dispatch(ToggleAccountPanel),
                style=secondary_button_style(true) +
                  [
                    "padding: 7px 9px", "justify-content: flex-start", "min-width: 184px",
                  ],
                [
                  avatar_chip("U"),
                  @html.div(
                    style=[
                      "display: flex", "flex-direction: column", "gap: 1px", "min-width: 0",
                      "align-items: flex-start",
                    ],
                    [
                      @html.div(
                        style=[
                          "font-size: 13px", "font-weight: 760", "color: var(--text-1)",
                          "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                          "max-width: 110px",
                        ],
                        user.display_name,
                      ),
                      @html.div(
                        style=mono_style() +
                          ["font-size: 10px", "color: var(--text-3)"],
                        "Account",
                      ),
                    ],
                  ),
                  @html.div(
                    style=[
                      "margin-left: auto", "font-size: 12px", "color: var(--text-3)",
                    ],
                    if model.account_panel_open {
                      "x"
                    } else {
                      "v"
                    },
                  ),
                ],
              ),
              if model.account_panel_open {
                render_account_panel(dispatch, model)
              } else {
                @html.nothing
              },
            ],
          ),
        ],
      )
    None => @html.nothing
  }
}

///|
fn render_project_sidebar(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let project_items = model.projects.map(fn(project) {
    sidebar_project_item(dispatch, model, project)
  })
  @html.div(
    style=[
      "width: 300px", "min-height: 100vh", "padding: 14px 12px", "display: flex",
      "flex-direction: column", "gap: 14px", "background: var(--sidebar-bg)", "border-right: 1px solid var(--border-soft)",
      "box-sizing: border-box", "flex-shrink: 0",
    ],
    [
      @html.div(style=["display: flex", "align-items: center", "gap: 10px"], [
        brand_logo(38),
        @html.div(
          style=[
            "min-width: 0", "display: flex", "flex-direction: column", "gap: 2px",
          ],
          [
            @html.div(
              style=["font-size: 16px", "font-weight: 800"],
              "MoonBit Cloud",
            ),
            @html.div(
              style=[
                "font-size: 12px", "color: var(--text-3)", "white-space: nowrap",
                "overflow: hidden", "text-overflow: ellipsis",
              ],
              workspace_name(model),
            ),
          ],
        ),
      ]),
      @html.button(
        type_="button",
        disabled=model.create_project_pending,
        on_click=dispatch(CreateProject),
        style=primary_button_style(!model.create_project_pending) +
          ["width: 100%"],
        if model.create_project_pending {
          "Creating..."
        } else {
          "+ New Project"
        },
      ),
      @html.div(
        style=[
          "display: flex", "justify-content: space-between", "align-items: center",
          "color: var(--text-2)", "font-size: 13px", "font-weight: 760",
        ],
        [
          @html.div("Projects"),
          @html.div(style=mono_style(), model.projects.length().to_string()),
        ],
      ),
      @html.div(
        style=[
          "display: flex", "flex-direction: column", "gap: 8px", "min-height: 0",
          "overflow-y: auto", "flex: 1",
        ],
        if project_items.length() == 0 {
          [
            @html.div(
              style=[
                "padding: 12px", "border: 1px solid var(--border-soft)", "border-radius: 6px",
                "color: var(--text-3)", "font-size: 13px", "line-height: 1.5",
              ],
              "Create a project to begin.",
            ),
          ]
        } else {
          project_items
        },
      ),
    ],
  )
}

///|
fn render_workspace_shell(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=[
      "min-height: 100vh", "display: flex", "align-items: stretch", "background: var(--page-bg)",
    ],
    [
      render_project_sidebar(dispatch, model),
      @html.div(
        style=[
          "flex: 1", "min-width: 0", "padding: 10px", "display: flex", "flex-direction: column",
          "gap: 10px", "box-sizing: border-box",
        ],
        [
          render_account_toolbar(dispatch, model),
          @html.div(
            style=[
              "flex: 1", "min-width: 0", "display: flex", "gap: 10px", "align-items: stretch",
            ],
            [
              render_workspace_panel(dispatch, model),
              render_preview_panel(model),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
fn view(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
  if model.session_ready && model.current_user is Some(_) {
    @html.div(
      style=app_root_style(model.resolved_theme_mode),
      render_workspace_shell(dispatch, model),
    )
  } else {
    let body = if !model.session_ready {
      render_loading_screen()
    } else {
      render_auth_screen(dispatch, model)
    }
    @html.div(
      style=app_root_style(model.resolved_theme_mode),
      @html.div(style=app_stack_style(), [
        render_app_header(dispatch, model),
        body,
      ]),
    )
  }
}

///|
extern "js" fn js_load_theme_mode(succeed~ : (String, String) -> Unit) =
  #| (succeed) => {
  #|   const resolveTheme = (mode) => {
  #|     if (mode === "light" || mode === "dark") return mode;
  #|     if (
  #|       window.matchMedia &&
  #|       window.matchMedia("(prefers-color-scheme: light)").matches
  #|     ) {
  #|       return "light";
  #|     }
  #|     return "dark";
  #|   };
  #|   let mode = "system";
  #|   try {
  #|     const stored = window.localStorage.getItem("moonbitcloud-theme");
  #|     if (stored === "dark" || stored === "light" || stored === "system") {
  #|       mode = stored;
  #|     }
  #|   } catch (_) {}
  #|   const resolved = resolveTheme(mode);
  #|   try {
  #|     document.documentElement.dataset.theme = mode;
  #|     document.documentElement.dataset.resolvedTheme = resolved;
  #|     document.documentElement.style.colorScheme = resolved;
  #|   } catch (_) {}
  #|   succeed(mode, resolved);
  #| }

///|
extern "js" fn js_persist_theme_mode(
  value : String,
  succeed~ : (String) -> Unit,
) =
  #| (value, succeed) => {
  #|   const resolveTheme = (mode) => {
  #|     if (mode === "light" || mode === "dark") return mode;
  #|     if (
  #|       window.matchMedia &&
  #|       window.matchMedia("(prefers-color-scheme: light)").matches
  #|     ) {
  #|       return "light";
  #|     }
  #|     return "dark";
  #|   };
  #|   const mode = value === "light" || value === "dark" || value === "system" ? value : "system";
  #|   const resolved = resolveTheme(mode);
  #|   try {
  #|     window.localStorage.setItem("moonbitcloud-theme", mode);
  #|   } catch (_) {}
  #|   try {
  #|     document.documentElement.dataset.theme = mode;
  #|     document.documentElement.dataset.resolvedTheme = resolved;
  #|     document.documentElement.style.colorScheme = resolved;
  #|   } catch (_) {}
  #|   succeed(resolved);
  #| }

///|
fn main {
  let (dispatch, root) = @rabbita.cell_with_dispatch(
    model=initial_model(),
    update~,
    view~,
    subscriptions~,
  )
  ignore(dispatch)
  @rabbita.new(root).mount("app")
}
