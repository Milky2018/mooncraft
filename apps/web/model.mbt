///|
enum ThemeMode {
  Light
  System
  Dark
} derive(Eq)

///|
enum ShellPage {
  AppWorkspace
  LlmConfig
} derive(Eq)

///|
struct Model {
  boot_requested : Bool
  session_ready : Bool
  theme_mode : ThemeMode
  resolved_theme_mode : ThemeMode
  app_mode : String
  current_user : @sdk.UserSummary?
  github_enabled : Bool
  logout_pending : Bool
  auth_notice : String?
  account_ai_provider : String
  account_ai_model : String
  account_ai_api_key : String
  account_model_options : Array[@sdk.ModelOption]
  account_model_options_pending : Bool
  account_pending : Bool
  account_notice : String?
  account_panel_open : Bool
  active_page : ShellPage
  projects : Array[@sdk.ProjectSummary]
  selected_project_id : String?
  project_detail : @sdk.ProjectDetail?
  messages : Array[@sdk.ChatMessage]
  run_status : @sdk.RunStatusResponse?
  run_events : Array[@sdk.RunEvent]
  last_run_event_seq : Int
  run_spinner_tick : Int
  draft : String
  new_project_name : String
  create_project_pending : Bool
  rename_project_name : String
  rename_project_pending : Bool
  delete_project_confirming : String?
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
  Logout
  LoggedOut(Result[Unit, @sdk.ApiError])
  ToggleAccountPanel
  OpenLlmConfig
  AccountAiProviderChanged(String)
  AccountAiModelChanged(String)
  AccountAiApiKeyChanged(String)
  RefreshModelOptions
  ModelOptionsLoaded(
    String,
    Result[@sdk.ListModelOptionsResponse, @sdk.ApiError]
  )
  SaveAiSettings
  AiSettingsSaved(Result[@sdk.AiSettingsResponse, @sdk.ApiError])
  ProjectsLoaded(Result[@sdk.ListProjectsResponse, @sdk.ApiError])
  SelectProject(String)
  ProjectLoaded(Result[@sdk.ProjectDetail, @sdk.ApiError])
  MessagesLoaded(Result[@sdk.ListMessagesResponse, @sdk.ApiError])
  DraftChanged(String)
  NewProjectNameChanged(String)
  CreateProject
  RenameProjectNameChanged(String)
  SaveProjectRename
  ProjectRenamed(Result[@sdk.UpdateProjectResponse, @sdk.ApiError])
  RequestDeleteProject(String)
  ConfirmDeleteProject(String)
  ProjectCreated(Result[@sdk.CreateProjectResponse, @sdk.ApiError])
  ProjectDeleted(String, Result[Unit, @sdk.ApiError])
  SendDraft
  RunCreated(Result[@sdk.CreateRunResponse, @sdk.ApiError])
  PollRun(String, String)
  RunLoaded(String, String, Result[@sdk.RunStatusResponse, @sdk.ApiError])
  PollRunEvents(String, String)
  RunEventsLoaded(Result[@sdk.ListRunEventsResponse, @sdk.ApiError])
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
    theme_mode: Light,
    resolved_theme_mode: Light,
    app_mode: "production",
    current_user: None,
    github_enabled: false,
    logout_pending: false,
    auth_notice: None,
    account_ai_provider: "openai",
    account_ai_model: "gpt-5.5",
    account_ai_api_key: "",
    account_model_options: [],
    account_model_options_pending: false,
    account_pending: false,
    account_notice: None,
    account_panel_open: false,
    active_page: AppWorkspace,
    projects: [],
    selected_project_id: None,
    project_detail: None,
    messages: [],
    run_status: None,
    run_events: [],
    last_run_event_seq: 0,
    run_spinner_tick: 0,
    draft: "",
    new_project_name: "",
    create_project_pending: false,
    rename_project_name: "",
    rename_project_pending: false,
    delete_project_confirming: None,
    delete_project_pending: None,
    sending_message: false,
    notice: None,
  }
}
