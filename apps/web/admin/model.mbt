///|
enum AdminView {
  Users
  Secrets
  Runtimes
} derive(Eq)

///|
struct AdminModel {
  boot_requested : Bool
  view : AdminView
  loading : Bool
  notice : String?
  users : Array[@sdk.AdminUserSummary]
  expanded_user_id : String?
  expanded_user_projects : Array[@sdk.AdminProjectSummary]
  user_projects_loading : Bool
  secrets : Array[@sdk.AdminSecretSummary]
  runtimes : Array[@sdk.RuntimeDetail]
  active_action_menu : String?
  creating_secret : Bool
  secret_name : String
  secret_value : String
  editing_secret_id : String?
  editing_secret_name : String
  editing_secret_value : String
  confirming_secret_delete_id : String?
  creating_runtime : Bool
  editing_runtime_id : String?
  editing_runtime_name : String
  editing_runtime_config_json : String
  editing_runtime_enabled : String
  editing_runtime_default : String
}

///|
enum AdminMsg {
  Bootstrap
  Refresh
  UsersLoaded(Result[@sdk.AdminListUsersResponse, @sdk.ApiError])
  ToggleUser(String)
  UserProjectsLoaded(
    String,
    Result[@sdk.AdminUserProjectsResponse, @sdk.ApiError]
  )
  SecretsLoaded(Result[@sdk.AdminListSecretsResponse, @sdk.ApiError])
  RuntimesLoaded(Result[@sdk.AdminListRuntimesResponse, @sdk.ApiError])
  ShowView(AdminView)
  ToggleActionMenu(String)
  Logout
  LoggedOut(Result[Unit, @sdk.ApiError])
  OpenCreateSecret
  CancelCreateSecret
  SecretNameChanged(String)
  SecretValueChanged(String)
  SaveCreateSecret
  SecretCreated(Result[@sdk.AdminSecretSummary, @sdk.ApiError])
  StartEditSecret(String)
  CancelEditSecret
  EditSecretNameChanged(String)
  EditSecretValueChanged(String)
  SaveEditSecret(String)
  SecretUpdated(Result[@sdk.AdminSecretSummary, @sdk.ApiError])
  RequestDeleteSecret(String)
  SecretDeleted(String, Result[Unit, @sdk.ApiError])
  OpenCreateRuntime
  StartEditRuntime(String)
  CancelEditRuntime
  RuntimeNameChanged(String)
  RuntimeConfigChanged(String)
  RuntimeEnabledChanged(String)
  RuntimeDefaultChanged(String)
  SaveCreateRuntime
  SaveRuntime(String)
  RuntimeSaved(Result[@sdk.RuntimeDetail, @sdk.ApiError])
}

///|
fn initial_admin_model() -> AdminModel {
  {
    boot_requested: false,
    view: Users,
    loading: true,
    notice: None,
    users: [],
    expanded_user_id: None,
    expanded_user_projects: [],
    user_projects_loading: false,
    secrets: [],
    runtimes: [],
    active_action_menu: None,
    creating_secret: false,
    secret_name: "",
    secret_value: "",
    editing_secret_id: None,
    editing_secret_name: "",
    editing_secret_value: "",
    confirming_secret_delete_id: None,
    creating_runtime: false,
    editing_runtime_id: None,
    editing_runtime_name: "",
    editing_runtime_config_json: "",
    editing_runtime_enabled: "true",
    editing_runtime_default: "false",
  }
}
