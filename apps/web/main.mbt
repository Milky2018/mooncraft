///|
enum AuthMode {
  Login
  Signup
} derive(Eq)

///|
enum ThemeMode {
  Dark
  Light
} derive(Eq)

///|
struct Model {
  boot_requested : Bool
  session_ready : Bool
  theme_mode : ThemeMode
  current_user : @sdk.UserSummary?
  github_enabled : Bool
  auth_mode : AuthMode
  auth_email : String
  auth_password : String
  auth_display_name : String
  auth_pending : Bool
  auth_notice : String?
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
  ThemeModeLoaded(ThemeMode)
  ToggleTheme
  SessionLoaded(Result[@sdk.SessionResponse, @sdk.ApiError])
  AuthModeSelected(AuthMode)
  AuthEmailChanged(String)
  AuthPasswordChanged(String)
  AuthDisplayNameChanged(String)
  SubmitAuth
  AuthCompleted(Result[@sdk.AuthResponse, @sdk.ApiError])
  Logout
  LoggedOut(Result[Unit, @sdk.ApiError])
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
    Dark => "dark"
    Light => "light"
  }
}

///|
fn ThemeMode::toggle(self : ThemeMode) -> ThemeMode {
  match self {
    Dark => Light
    Light => Dark
  }
}

///|
fn theme_mode_from_string(value : String) -> ThemeMode {
  if value == "light" {
    Light
  } else {
    Dark
  }
}

///|
fn initial_model() -> Model {
  {
    boot_requested: false,
    session_ready: false,
    theme_mode: Dark,
    current_user: None,
    github_enabled: false,
    auth_mode: Signup,
    auth_email: "",
    auth_password: "",
    auth_display_name: "",
    auth_pending: false,
    auth_notice: None,
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
    js_load_theme_mode(succeed=mode => {
      scheduler.add(dispatch(ThemeModeLoaded(theme_mode_from_string(mode))))
    })
  })
}

///|
fn persist_theme_cmd(theme_mode : ThemeMode) -> @rabbita.Cmd {
  @cmd.custom_cmd(fn(_scheduler) {
    js_persist_theme_mode(theme_mode.storage_value())
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
  }
}

///|
fn logout_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  post_empty(@sdk.logout_path(), fn(result) { dispatch(LoggedOut(result)) })
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
  model.auth_email.trim() != "" &&
  model.auth_password != "" &&
  !model.auth_pending
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
    ThemeModeLoaded(theme_mode) => (@rabbita.none, { ..model, theme_mode, })
    ToggleTheme => {
      let theme_mode = model.theme_mode.toggle()
      (persist_theme_cmd(theme_mode), { ..model, theme_mode, })
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
        { ..model, auth_pending: false, auth_password: "", auth_notice: None },
      )
    AuthCompleted(Err(error)) =>
      (
        @rabbita.none,
        { ..model, auth_pending: false, auth_notice: Some(error.message) },
      )
    Logout =>
      (logout_cmd(dispatch), { ..model, auth_notice: None, notice: None })
    LoggedOut(Ok(_)) =>
      (
        load_session_cmd(dispatch),
        {
          ..clear_workspace(model),
          current_user: None,
          auth_password: "",
          auth_notice: None,
        },
      )
    LoggedOut(Err(error)) =>
      (
        @rabbita.none,
        { ..model, auth_notice: Some(error_notice("Sign-out failed.", error)) },
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
    Dark =>
      [
        "--page-bg: #05080c", "--page-bg-alt: #091119", "--page-grid: rgba(123, 145, 170, 0.08)",
        "--page-glow-a: rgba(24, 255, 176, 0.14)", "--page-glow-b: rgba(45, 125, 255, 0.16)",
        "--surface-1: rgba(8, 13, 19, 0.92)", "--surface-2: rgba(11, 18, 26, 0.96)",
        "--surface-3: rgba(16, 24, 34, 0.98)", "--surface-raised: rgba(17, 29, 42, 1)",
        "--border-soft: rgba(120, 140, 166, 0.16)", "--border-strong: rgba(92, 255, 196, 0.34)",
        "--text-1: #eff7ff", "--text-2: #a7bad0", "--text-3: #72849a", "--accent: #38efb7",
        "--accent-strong: #12d89c", "--accent-soft: rgba(18, 216, 156, 0.12)", "--action: #5fa8ff",
        "--action-strong: #2d7dff", "--action-soft: rgba(45, 125, 255, 0.18)", "--danger: #ff7a7a",
        "--danger-soft: rgba(255, 122, 122, 0.12)", "--warning: #ffcf66", "--warning-soft: rgba(255, 207, 102, 0.12)",
        "--shadow: 0 24px 90px rgba(0, 0, 0, 0.42)", "--badge-idle-bg: rgba(115, 137, 160, 0.14)",
        "--badge-idle-fg: #a7bad0", "--badge-running-bg: rgba(45, 125, 255, 0.16)",
        "--badge-running-fg: #91c0ff", "--badge-success-bg: rgba(18, 216, 156, 0.14)",
        "--badge-success-fg: #7af0c6", "--badge-failed-bg: rgba(255, 122, 122, 0.14)",
        "--badge-failed-fg: #ffb0b0", "color-scheme: dark",
      ]
    Light =>
      [
        "--page-bg: #edf3f8", "--page-bg-alt: #f8fbfd", "--page-grid: rgba(74, 91, 115, 0.06)",
        "--page-glow-a: rgba(18, 216, 156, 0.10)", "--page-glow-b: rgba(45, 125, 255, 0.10)",
        "--surface-1: rgba(255, 255, 255, 0.92)", "--surface-2: rgba(247, 250, 252, 0.97)",
        "--surface-3: rgba(240, 245, 249, 0.98)", "--surface-raised: #ffffff", "--border-soft: rgba(57, 74, 96, 0.12)",
        "--border-strong: rgba(9, 143, 109, 0.20)", "--text-1: #18283c", "--text-2: #4b6078",
        "--text-3: #708196", "--accent: #0ea277", "--accent-strong: #0a8a65", "--accent-soft: rgba(10, 138, 101, 0.10)",
        "--action: #2f84ff", "--action-strong: #1a63ea", "--action-soft: rgba(26, 99, 234, 0.12)",
        "--danger: #cc4f4f", "--danger-soft: rgba(204, 79, 79, 0.10)", "--warning: #b88614",
        "--warning-soft: rgba(184, 134, 20, 0.12)", "--shadow: 0 20px 60px rgba(19, 40, 66, 0.10)",
        "--badge-idle-bg: rgba(115, 137, 160, 0.12)", "--badge-idle-fg: #4f6277",
        "--badge-running-bg: rgba(45, 125, 255, 0.12)", "--badge-running-fg: #1d5cc9",
        "--badge-success-bg: rgba(10, 138, 101, 0.12)", "--badge-success-fg: #0a7f5d",
        "--badge-failed-bg: rgba(204, 79, 79, 0.12)", "--badge-failed-fg: #a84343",
        "color-scheme: light",
      ]
  }
}

///|
fn app_root_style(theme_mode : ThemeMode) -> Array[String] {
  theme_variables(theme_mode) +
  [
    "min-height: 100vh", "padding: 18px", "background-color: var(--page-bg)", "background-image: radial-gradient(circle at top left, var(--page-glow-a), transparent 26%), radial-gradient(circle at top right, var(--page-glow-b), transparent 24%), linear-gradient(180deg, var(--page-bg-alt), var(--page-bg)), repeating-linear-gradient(0deg, transparent, transparent 39px, var(--page-grid) 40px), repeating-linear-gradient(90deg, transparent, transparent 39px, var(--page-grid) 40px)",
    "background-size: auto, auto, auto, 40px 40px, 40px 40px", "color: var(--text-1)",
    "font-family: \"IBM Plex Sans\", \"Avenir Next\", \"Segoe UI\", sans-serif",
  ]
}

///|
fn app_stack_style() -> Array[String] {
  [
    "min-height: calc(100vh - 36px)", "display: flex", "flex-direction: column",
    "gap: 18px",
  ]
}

///|
fn panel_style() -> Array[String] {
  [
    "background: var(--surface-1)", "border: 1px solid var(--border-soft)", "border-radius: 14px",
    "box-shadow: var(--shadow)", "overflow: hidden", "backdrop-filter: blur(14px)",
  ]
}

///|
fn inset_panel_style() -> Array[String] {
  [
    "background: var(--surface-2)", "border: 1px solid var(--border-soft)", "border-radius: 12px",
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
    "padding: 12px 16px",
    "border: 1px solid var(--border-soft)",
    "border-radius: 12px",
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
    "linear-gradient(135deg, var(--action-strong), var(--action))", "#ffffff", enabled,
  ) +
  ["box-shadow: 0 12px 30px var(--action-soft)"]
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
    "border-radius: 10px",
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
fn ghost_button_style(enabled : Bool) -> Array[String] {
  button_style("transparent", "var(--text-2)", enabled)
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
    "padding: 14px 16px",
    "border: 1px solid " + border_color,
    "border-radius: 12px",
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
        "border-radius: 999px",
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
  let label = if model.theme_mode is Dark { "Light Mode" } else { "Dark Mode" }
  @html.button(
    type_="button",
    on_click=dispatch(ToggleTheme),
    style=secondary_button_style(true),
    label,
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
        "padding: 14px 18px", "display: flex", "justify-content: space-between",
        "align-items: center", "gap: 14px", "flex-wrap: wrap",
      ],
    [
      @html.div(
        style=["font-size: 22px", "font-weight: 780", "letter-spacing: -0.02em"],
        "MoonBit Cloud",
      ),
      @html.div(
        style=[
          "display: flex", "align-items: center", "gap: 10px", "flex-wrap: wrap",
          "justify-content: flex-end",
        ],
        [
          if model.current_user is Some(_) {
            @html.div(
              style=["font-size: 14px", "color: var(--text-2)"],
              user_name(model),
            )
          } else {
            @html.nothing
          },
          theme_toggle_button(dispatch, model),
          if model.current_user is Some(_) {
            @html.button(
              type_="button",
              on_click=dispatch(Logout),
              style=ghost_button_style(true),
              "Log Out",
            )
          } else {
            @html.nothing
          },
        ],
      ),
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
          "#ffffff"
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
  input_type : @html.InputType,
  value : String,
  placeholder : String,
  on_input : (String) -> Msg,
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Html {
  @html.div(style=["display: flex", "flex-direction: column", "gap: 8px"], [
    @html.div(style=section_label_style(), label),
    @html.input(
      input_type~,
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
          "padding: 14px 16px",
          "border-radius: 12px",
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
  }
  let subtitle = match model.auth_mode {
    Login => "Sign in to resume your projects and previews."
    Signup =>
      "Describe what you want, let the agent update the workspace, and watch the preview."
  }
  let submit_label = if model.auth_pending {
    "Working..."
  } else {
    match model.auth_mode {
      Login => "Log In"
      Signup => "Create Account"
    }
  }
  @html.div(
    style=[
      "display: flex", "flex-wrap: wrap", "gap: 18px", "align-items: stretch", "flex: 1",
    ],
    [
      @html.div(
        style=panel_style() +
          [
            "flex: 1 1 360px", "min-width: 320px", "padding: 26px", "display: flex",
            "flex-direction: column", "gap: 16px", "justify-content: center",
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
            "flex: 1 1 420px", "min-width: 320px", "max-width: 560px", "padding: 26px",
            "display: flex", "flex-direction: column", "gap: 18px",
          ],
        [
          @html.div(
            style=[
              "display: flex", "gap: 10px", "padding: 6px", "border-radius: 14px",
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
            @html.Email,
            model.auth_email,
            "name@example.com",
            fn(value) { AuthEmailChanged(value) },
            dispatch,
          ),
          auth_field(
            "Password",
            @html.Password,
            model.auth_password,
            "At least 8 characters",
            fn(value) { AuthPasswordChanged(value) },
            dispatch,
          ),
          if model.auth_mode is Signup {
            auth_field(
              "Display Name",
              @html.Text,
              model.auth_display_name,
              "Optional operator name",
              fn(value) { AuthDisplayNameChanged(value) },
              dispatch,
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
          if model.github_enabled {
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
                    "text-decoration: none", "justify-content: center", "padding: 14px 16px",
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
fn render_project_tile(
  dispatch : @rabbita.Dispatch[Msg],
  selected_project_id : String?,
  delete_project_pending : String?,
  project : @sdk.ProjectSummary,
) -> @rabbita.Html {
  let is_selected = selected_project_id == Some(project.id)
  let is_deleting = delete_project_pending == Some(project.id)
  let delete_enabled = !(project.status is @sdk.Running || is_deleting)
  let tile_background = if is_selected {
    "var(--surface-3)"
  } else {
    "var(--surface-2)"
  }
  let tile_border_color = if is_selected {
    "var(--border-strong)"
  } else {
    "var(--border-soft)"
  }
  let tile_foreground = "var(--text-1)"
  let meta_color = "var(--text-3)"
  let delete_label = if is_deleting { "Deleting..." } else { "Delete" }
  @html.div(
    style=inset_panel_style() +
      [
        "padding: 14px 16px",
        "display: flex",
        "flex-direction: column",
        "gap: 12px",
        "background: " + tile_background,
        "border-color: " + tile_border_color,
        "color: " + tile_foreground,
      ],
    [
      @html.button(
        type_="button",
        on_click=dispatch(SelectProject(project.id)),
        style=[
          "width: 100%", "padding: 0", "display: flex", "justify-content: space-between",
          "align-items: center", "gap: 14px", "border: none", "background: transparent",
          "color: inherit", "cursor: pointer", "text-align: left",
        ],
        [
          @html.div(
            style=[
              "display: flex", "flex-direction: column", "gap: 6px", "min-width: 0",
              "text-align: left",
            ],
            [
              @html.div(
                style=["font-size: 15px", "font-weight: 700"],
                project.display_name,
              ),
              @html.div(
                style=mono_style() +
                  [
                    "font-size: 12px",
                    "color: " + meta_color,
                    "white-space: nowrap",
                    "overflow: hidden",
                    "text-overflow: ellipsis",
                  ],
                project.updated_at,
              ),
            ],
          ),
          status_badge(project.status),
        ],
      ),
      if is_selected || is_deleting {
        @html.div(
          style=["display: flex", "justify-content: flex-end"],
          @html.button(
            type_="button",
            disabled=!delete_enabled,
            on_click=dispatch(DeleteProject(project.id)),
            style=subtle_danger_button_style(delete_enabled),
            delete_label,
          ),
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn render_projects_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let tiles = model.projects.map(fn(project) {
    render_project_tile(
      dispatch,
      model.selected_project_id,
      model.delete_project_pending,
      project,
    )
  })
  @html.div(
    style=panel_style() +
      [
        "flex: 0 1 300px", "min-width: 280px", "display: flex", "flex-direction: column",
        "padding: 18px", "gap: 16px",
      ],
    [
      @html.div(
        style=[
          "display: flex", "justify-content: space-between", "align-items: center",
          "gap: 12px",
        ],
        [
          @html.div(style=["font-size: 28px", "font-weight: 780"], "Projects"),
          @html.button(
            type_="button",
            disabled=model.create_project_pending,
            on_click=dispatch(CreateProject),
            style=button_style(
              "linear-gradient(135deg, var(--accent-strong), var(--accent))",
              "#04110d",
              !model.create_project_pending,
            ),
            if model.create_project_pending {
              "Creating..."
            } else {
              "+ New"
            },
          ),
        ],
      ),
      @html.div(
        style=["display: flex", "flex-direction: column", "gap: 10px"],
        if tiles.length() == 0 {
          [
            @html.div(
              style=inset_panel_style() +
                [
                  "padding: 16px", "font-size: 14px", "line-height: 1.7", "color: var(--text-2)",
                ],
              "Create your first project to start.",
            ),
          ]
        } else {
          tiles
        },
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
  let bubble_foreground = if is_user { "#ffffff" } else { "var(--text-1)" }
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
        "padding: 16px 18px",
        "border-radius: 14px",
        "background: " + bubble_background,
        "color: " + bubble_foreground,
        "border: 1px solid " + bubble_border,
        "box-shadow: 0 16px 36px rgba(0, 0, 0, 0.12)",
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
          "padding: 12px 14px", "border-radius: 12px", "background: var(--action-soft)",
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
            "padding: 22px", "display: flex", "flex-direction: column", "gap: 14px",
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
            "padding: 18px", "display: flex", "flex-direction: column", "gap: 8px",
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
        "min-height: 760px",
      ],
    [
      @html.div(
        style=[
          "padding: 20px 22px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
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
          "padding: 18px 22px 0", "display: flex", "flex-direction: column", "gap: 12px",
        ],
        [
          render_notice_card(model.notice, "var(--warning-soft)"),
          render_run_banner(model),
          render_run_failure_card(model),
        ],
      ),
      @html.div(
        style=[
          "flex: 1", "min-height: 0", "padding: 18px 22px", "display: flex", "flex-direction: column",
          "gap: 14px", "overflow-y: auto",
        ],
        messages,
      ),
      @html.div(
        style=[
          "padding: 18px 22px 22px", "border-top: 1px solid var(--border-soft)",
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
      "height: 100%", "padding: 20px", "display: flex", "flex-direction: column",
      "gap: 14px",
    ],
    [
      @html.div(
        style=inset_panel_style() +
          [
            "padding: 18px", "display: flex", "flex-direction: column", "gap: 10px",
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
        "min-height: 760px",
      ],
    [
      @html.div(
        style=[
          "padding: 20px 22px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
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
                src=target.url,
                loading="eager",
                style=[
                  "height: 100%", "width: 100%", "border: none", "background: #ffffff",
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
          "padding: 22px 26px", "display: flex", "flex-direction: column", "gap: 8px",
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
fn render_workspace_shell(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=[
      "display: flex", "flex-wrap: wrap", "align-items: stretch", "gap: 18px", "flex: 1",
    ],
    [
      render_projects_panel(dispatch, model),
      render_workspace_panel(dispatch, model),
      render_preview_panel(model),
    ],
  )
}

///|
fn view(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
  let body = if !model.session_ready {
    render_loading_screen()
  } else if model.current_user is None {
    render_auth_screen(dispatch, model)
  } else {
    render_workspace_shell(dispatch, model)
  }
  @html.div(
    style=app_root_style(model.theme_mode),
    @html.div(style=app_stack_style(), [
      render_app_header(dispatch, model),
      body,
    ]),
  )
}

///|
extern "js" fn js_load_theme_mode(succeed~ : (String) -> Unit) =
  #| (succeed) => {
  #|   try {
  #|     const stored = window.localStorage.getItem("moonbitcloud-theme");
  #|     if (stored === "dark" || stored === "light") {
  #|       document.documentElement.style.colorScheme = stored;
  #|       succeed(stored);
  #|       return;
  #|     }
  #|   } catch (_) {}
  #|   const mode =
  #|     window.matchMedia &&
  #|     window.matchMedia("(prefers-color-scheme: dark)").matches
  #|       ? "dark"
  #|       : "light";
  #|   try {
  #|     document.documentElement.style.colorScheme = mode;
  #|   } catch (_) {}
  #|   succeed(mode);
  #| }

///|
extern "js" fn js_persist_theme_mode(value : String) =
  #| (value) => {
  #|   try {
  #|     window.localStorage.setItem("moonbitcloud-theme", value);
  #|   } catch (_) {}
  #|   try {
  #|     document.documentElement.style.colorScheme = value;
  #|   } catch (_) {}
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
