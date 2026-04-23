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
  StarterPromptSelected(String)
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
fn ThemeMode::label(self : ThemeMode) -> String {
  match self {
    Dark => "DARK"
    Light => "LIGHT"
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
    StarterPromptSelected(prompt) => (@rabbita.none, { ..model, draft: prompt })
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
              notice: response.run.error_message,
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
          { ..model, run_status: Some(run), notice: run.error_message },
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
fn danger_button_style(enabled : Bool) -> Array[String] {
  button_style("var(--danger-soft)", "var(--danger)", enabled)
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
fn user_email(model : Model) -> String {
  match model.current_user {
    Some(user) => user.email
    None => "local-only"
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
fn starter_prompts() -> Array[String] {
  [
    "Build a dashboard for tracking bugs, ownership, and release status.", "Turn this into a sharp landing page with pricing, waitlist signup, and FAQ.",
    "Create a task manager with keyboard-first interactions and saved views.",
  ]
}

///|
fn preview_url_text(model : Model) -> String {
  match model.project_detail.bind(fn(project) { project.preview }) {
    Some(target) => target.url
    None => "not-ready"
  }
}

///|
fn theme_toggle_button(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let next_label = if model.theme_mode is Dark {
    "Switch to Light"
  } else {
    "Switch to Dark"
  }
  @html.button(
    type_="button",
    on_click=dispatch(ToggleTheme),
    style=secondary_button_style(true) + ["min-width: 154px"],
    [
      @html.div(style=section_label_style(), "Theme"),
      @html.div(
        style=["font-size: 14px", "font-weight: 700"],
        model.theme_mode.label(),
      ),
      @html.div(style=["font-size: 13px", "color: var(--text-3)"], next_label),
    ],
  )
}

///|
fn render_app_header(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let runtime_label = if active_run(model) is Some(_) {
    "Agent Run Active"
  } else if model.current_user is Some(_) {
    "Local Prototype"
  } else {
    "Preview-First Builder"
  }
  @html.div(
    style=panel_style() +
      [
        "padding: 16px 18px", "display: flex", "justify-content: space-between",
        "align-items: center", "gap: 14px", "flex-wrap: wrap",
      ],
    [
      @html.div(style=["display: flex", "flex-direction: column", "gap: 6px"], [
        @html.div(style=section_label_style(), "MoonBit Cloud // Local"),
        @html.div(
          style=[
            "font-size: 28px", "font-weight: 780", "letter-spacing: -0.03em",
          ],
          runtime_label,
        ),
        @html.div(
          style=["font-size: 14px", "line-height: 1.6", "color: var(--text-2)"],
          "Hidden-code workflow, sharp state visibility, and live preview as the source of truth.",
        ),
      ]),
      @html.div(
        style=[
          "display: flex", "align-items: center", "gap: 10px", "flex-wrap: wrap",
          "justify-content: flex-end",
        ],
        [
          if model.current_user is Some(_) {
            @html.div(
              style=inset_panel_style() +
                [
                  "padding: 10px 12px", "display: flex", "flex-direction: column",
                  "gap: 4px", "min-width: 220px",
                ],
              [
                @html.div(style=section_label_style(), "Active Operator"),
                @html.div(
                  style=["font-size: 15px", "font-weight: 700"],
                  user_name(model),
                ),
                @html.div(
                  style=["font-size: 13px", "color: var(--text-3)"],
                  user_email(model),
                ),
              ],
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
fn render_terminal_card() -> @rabbita.Html {
  let rows = [
    "[01] scaffold local MoonBit workspace", "[02] run one Codex thread per project",
    "[03] validate moon fmt / check / test", "[04] restart preview on stable port",
  ]
  @html.div(
    style=inset_panel_style() +
      [
        "padding: 18px", "display: flex", "flex-direction: column", "gap: 10px",
        "background: linear-gradient(180deg, var(--surface-3), var(--surface-2))",
      ],
    [
      @html.div(style=section_label_style(), "Runbook"),
      @html.div(
        style=mono_style() +
          [
            "display: flex", "flex-direction: column", "gap: 8px", "font-size: 13px",
            "color: var(--text-2)",
          ],
        rows.map(fn(row) {
          @html.div(
            style=[
              "padding: 10px 12px", "border-radius: 10px", "background: rgba(255, 255, 255, 0.02)",
              "border: 1px solid var(--border-soft)",
            ],
            row,
          )
        }),
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
    Signup => "Build sharper apps without opening the code"
  }
  let subtitle = match model.auth_mode {
    Login =>
      "Sign in to resume your projects, inspect the latest preview, and keep iterating in one thread."
    Signup =>
      "Create an account to start from a blank chat, let the agent shape the workspace, and track progress through the preview."
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
            "flex-direction: column", "gap: 18px",
          ],
        [
          @html.div(style=section_label_style(), "Operator Console"),
          @html.div(
            style=["font-size: 42px", "line-height: 1.02", "font-weight: 780"],
            title,
          ),
          @html.div(
            style=[
              "font-size: 16px", "line-height: 1.7", "color: var(--text-2)",
            ],
            subtitle,
          ),
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 10px"],
            [
              @html.div(
                style=inset_panel_style() +
                  [
                    "padding: 16px", "display: flex", "flex-direction: column", "gap: 8px",
                  ],
                [
                  @html.div(style=section_label_style(), "Interface Rules"),
                  @html.div(
                    style=[
                      "font-size: 15px", "line-height: 1.7", "color: var(--text-2)",
                    ],
                    "One project rail, one workspace, one live preview. Less chrome, clearer state, faster feedback.",
                  ),
                ],
              ),
              render_terminal_card(),
            ],
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
    "linear-gradient(135deg, var(--action-strong), var(--action))"
  } else {
    "var(--surface-2)"
  }
  let tile_border_color = if is_selected {
    "rgba(255, 255, 255, 0.12)"
  } else {
    "var(--border-soft)"
  }
  let tile_foreground = if is_selected { "#ffffff" } else { "var(--text-1)" }
  let meta_color = if is_selected {
    "rgba(255,255,255,0.78)"
  } else {
    "var(--text-3)"
  }
  let delete_label = if is_deleting { "Deleting..." } else { "Delete" }
  @html.div(style=["display: flex", "gap: 10px", "align-items: stretch"], [
    @html.button(
      type_="button",
      on_click=dispatch(SelectProject(project.id)),
      style=inset_panel_style() +
        [
          "flex: 1",
          "padding: 14px 16px",
          "display: flex",
          "justify-content: space-between",
          "align-items: center",
          "gap: 14px",
          "cursor: pointer",
          "background: " + tile_background,
          "border-color: " + tile_border_color,
          "color: " + tile_foreground,
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
    @html.button(
      type_="button",
      disabled=!delete_enabled,
      on_click=dispatch(DeleteProject(project.id)),
      style=danger_button_style(delete_enabled) + ["min-width: 94px"],
      delete_label,
    ),
  ])
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
          "display: flex", "justify-content: space-between", "align-items: flex-start",
          "gap: 12px",
        ],
        [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
            [
              @html.div(style=section_label_style(), "Project Rail"),
              @html.div(
                style=["font-size: 28px", "font-weight: 780"],
                "Projects",
              ),
              @html.div(
                style=["font-size: 14px", "color: var(--text-2)"],
                "\{model.projects.length()} total",
              ),
            ],
          ),
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
        style=inset_panel_style() +
          [
            "padding: 14px 16px", "display: flex", "flex-direction: column", "gap: 6px",
          ],
        [
          @html.div(style=section_label_style(), "Operator"),
          @html.div(
            style=["font-size: 16px", "font-weight: 700"],
            user_name(model),
          ),
          @html.div(
            style=["font-size: 13px", "color: var(--text-3)"],
            user_email(model),
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
              "Create the first project, then drive the whole app through chat. The preview will stay same-origin and update in place.",
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
          "padding: 14px 16px", "border-radius: 12px", "background: var(--action-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "justify-content: space-between",
          "align-items: center", "gap: 12px", "flex-wrap: wrap",
        ],
        [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
            [
              @html.div(style=section_label_style(), "Run In Progress"),
              @html.div(
                style=[
                  "font-size: 14px", "line-height: 1.6", "color: var(--text-1)",
                ],
                "The agent is editing the workspace, validating the project, and refreshing the preview.",
              ),
            ],
          ),
          status_badge(run.state),
        ],
      )
    None => @html.nothing
  }
}

///|
fn render_starter_prompt(
  dispatch : @rabbita.Dispatch[Msg],
  prompt : String,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    on_click=dispatch(StarterPromptSelected(prompt)),
    style=inset_panel_style() +
      [
        "padding: 14px 16px", "display: flex", "flex-direction: column", "gap: 8px",
        "align-items: flex-start", "text-align: left", "cursor: pointer",
      ],
    [
      @html.div(style=section_label_style(), "Starter Prompt"),
      @html.div(
        style=["font-size: 14px", "line-height: 1.6", "color: var(--text-1)"],
        prompt,
      ),
    ],
  )
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
            "padding: 24px", "display: flex", "flex-direction: column", "gap: 16px",
          ],
        [
          @html.div(style=section_label_style(), "First Move"),
          @html.div(
            style=["font-size: 28px", "line-height: 1.1", "font-weight: 760"],
            "Create a project, then start with a concrete product request.",
          ),
          @html.div(
            style=[
              "font-size: 15px", "line-height: 1.7", "color: var(--text-2)",
            ],
            "The workspace stays code-hidden. You only manage intent, run state, and the preview outcome.",
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
        style=["display: flex", "flex-direction: column", "gap: 12px"],
        [
          @html.div(
            style=inset_panel_style() +
              [
                "padding: 18px", "display: flex", "flex-direction: column", "gap: 10px",
              ],
            [
              @html.div(style=section_label_style(), "No Messages Yet"),
              @html.div(
                style=["font-size: 18px", "font-weight: 720"],
                "Start with a concrete change request.",
              ),
              @html.div(
                style=[
                  "font-size: 15px", "line-height: 1.7", "color: var(--text-2)",
                ],
                "Good prompts describe product behavior, layout, or data flow. The agent keeps one persistent Codex thread for this project.",
              ),
            ],
          ),
          @html.div(
            style=[
              "display: grid", "grid-template-columns: repeat(auto-fit, minmax(220px, 1fr))",
              "gap: 12px",
            ],
            starter_prompts().map(fn(prompt) {
              render_starter_prompt(dispatch, prompt)
            }),
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
    "Describe a product change, bug fix, or redesign. The preview should be the proof."
  } else {
    "Create a project to unlock the workspace."
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
              @html.div(style=section_label_style(), "Chat Workspace"),
              @html.div(
                style=[
                  "font-size: 38px", "line-height: 1.02", "font-weight: 780",
                ],
                project_headline(model),
              ),
              @html.div(
                style=[
                  "font-size: 14px", "line-height: 1.6", "color: var(--text-2)",
                ],
                "Sharper controls, clearer empty states, and one persistent thread per project.",
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
          "display: flex", "flex-direction: column", "gap: 12px",
        ],
        [
          @html.div(style=section_label_style(), "Request Composer"),
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
              "display: flex", "justify-content: space-between", "align-items: center",
              "gap: 12px", "flex-wrap: wrap",
            ],
            [
              @html.div(
                style=[
                  "font-size: 13px", "line-height: 1.6", "color: var(--text-3)",
                ],
                "Keep prompts concrete: target screen, behavior, and success criteria.",
              ),
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
    None =>
      "Choose a project to inspect the execution surface. The preview becomes the main artifact once the first run succeeds."
    Some(_) =>
      if active_run(model) is Some(_) {
        "Waiting for the agent to finish the first successful run. The control plane will reverse-proxy the generated app here."
      } else {
        "No preview yet. Send a request and the platform will build, validate, and boot the generated app into this panel."
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
          @html.div(style=section_label_style(), "Execution Surface"),
          @html.div(
            style=["font-size: 28px", "line-height: 1.08", "font-weight: 760"],
            "Preview boots here after validation passes.",
          ),
          @html.div(
            style=[
              "font-size: 15px", "line-height: 1.7", "color: var(--text-2)",
            ],
            helper_copy,
          ),
        ],
      ),
      @html.div(
        style=[
          "display: grid", "grid-template-columns: repeat(auto-fit, minmax(160px, 1fr))",
          "gap: 12px",
        ],
        [
          @html.div(
            style=inset_panel_style() +
              [
                "padding: 14px", "display: flex", "flex-direction: column", "gap: 8px",
              ],
            [
              @html.div(style=section_label_style(), "Step 1"),
              @html.div(
                style=["font-size: 14px", "line-height: 1.6"],
                "Chat drives the change.",
              ),
            ],
          ),
          @html.div(
            style=inset_panel_style() +
              [
                "padding: 14px", "display: flex", "flex-direction: column", "gap: 8px",
              ],
            [
              @html.div(style=section_label_style(), "Step 2"),
              @html.div(
                style=["font-size: 14px", "line-height: 1.6"],
                "Agent edits and validates.",
              ),
            ],
          ),
          @html.div(
            style=inset_panel_style() +
              [
                "padding: 14px", "display: flex", "flex-direction: column", "gap: 8px",
              ],
            [
              @html.div(style=section_label_style(), "Step 3"),
              @html.div(
                style=["font-size: 14px", "line-height: 1.6"],
                "Control plane restarts preview.",
              ),
            ],
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
              @html.div(style=section_label_style(), "Live Preview"),
              @html.div(
                style=[
                  "font-size: 38px", "line-height: 1.02", "font-weight: 780",
                ],
                "Running App",
              ),
              @html.div(
                style=[
                  "font-size: 14px", "line-height: 1.6", "color: var(--text-2)",
                ],
                "Same-origin proxy target: \{preview_url_text(model)}",
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
              style=["height: 100%", "display: flex", "flex-direction: column"],
              [
                @html.iframe(
                  title="Live Preview",
                  src=target.url,
                  loading="eager",
                  style=[
                    "flex: 1", "min-height: 0", "width: 100%", "border: none", "background: #ffffff",
                  ],
                ),
                @html.div(
                  style=[
                    "padding: 14px 16px", "border-top: 1px solid var(--border-soft)",
                    "display: flex", "justify-content: space-between", "gap: 12px",
                    "flex-wrap: wrap", "align-items: center",
                  ],
                  [
                    @html.div(
                      style=[
                        "display: flex", "flex-direction: column", "gap: 4px",
                      ],
                      [
                        @html.div(style=section_label_style(), "Preview Target"),
                        @html.div(
                          style=mono_style() +
                            ["font-size: 13px", "color: var(--text-2)"],
                          "\{target.url}  :: port \{target.port}",
                        ),
                      ],
                    ),
                    if target.healthy {
                      @html.div(
                        style=["font-size: 14px", "color: var(--text-2)"],
                        "Healthy",
                      )
                    } else {
                      @html.div(
                        style=["font-size: 14px", "color: var(--danger)"],
                        "Needs attention",
                      )
                    },
                  ],
                ),
              ],
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
        @html.div(style=section_label_style(), "Boot"),
        @html.div(
          style=["font-size: 28px", "line-height: 1.05", "font-weight: 760"],
          "Loading MoonBit Cloud",
        ),
        @html.div(
          style=["font-size: 14px", "line-height: 1.6", "color: var(--text-2)"],
          "Restoring session state, theme preference, and project context.",
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
