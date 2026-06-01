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
  active_action_menu : String?
  users : AdminUsersState
  secrets : AdminSecretsState
  runtimes : AdminRuntimesState
}

///|
struct AdminUsersState {
  items : Array[@sdk.AdminUserSummary]
  expanded_user_id : String?
  expanded_projects : Array[@sdk.AdminProjectSummary]
  projects_loading : Bool
}

///|
struct AdminSecretCreateState {
  name : String
  value : String
}

///|
struct AdminSecretEditState {
  id : String
  name : String
  value : String
}

///|
struct AdminSecretsState {
  items : Array[@sdk.AdminSecretSummary]
  create : AdminSecretCreateState?
  edit : AdminSecretEditState?
  confirming_delete_id : String?
}

///|
struct AdminRuntimeEditor {
  id : String?
  name : String
  config_json : String
  enabled : String
  is_default : String
}

///|
struct AdminRuntimesState {
  items : Array[@sdk.RuntimeDetail]
  editor : AdminRuntimeEditor?
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
    active_action_menu: None,
    users: {
      items: [],
      expanded_user_id: None,
      expanded_projects: [],
      projects_loading: false,
    },
    secrets: { items: [], create: None, edit: None, confirming_delete_id: None },
    runtimes: { items: [], editor: None },
  }
}
