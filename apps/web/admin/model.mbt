///|
enum AdminView {
  Users
  Secrets
  Runtimes
  Models
} derive(Eq)

///|
enum ModelCatalogMode {
  Recommended
  All
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
  ai_config : @sdk.AdminAiConfigResponse
  catalog : Array[@sdk.AdminAiModelSummary]
  models_error : String?
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
  editing_runtime_spec_json : String
  editing_runtime_enabled : String
  editing_runtime_default : String
  creating_model : Bool
  model_search : String
  model_catalog_mode : ModelCatalogMode
  confirming_model_remove_id : String?
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
  ConfigLoaded(Result[@sdk.AdminAiConfigResponse, @sdk.ApiError])
  CatalogLoaded(Result[@sdk.AdminListAiModelsResponse, @sdk.ApiError])
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
  RuntimeSpecChanged(String)
  RuntimeEnabledChanged(String)
  RuntimeDefaultChanged(String)
  SaveCreateRuntime
  SaveRuntime(String)
  RuntimeSaved(Result[@sdk.RuntimeDetail, @sdk.ApiError])
  OpenCreateModel
  CancelCreateModel
  ModelSearchChanged(String)
  SetModelCatalogMode(ModelCatalogMode)
  AddModel(String)
  SetDefaultModel(String)
  RequestRemoveModel(String)
  ModelsUpdated(Result[@sdk.AdminAiConfigResponse, @sdk.ApiError])
}

///|
fn empty_ai_config() -> @sdk.AdminAiConfigResponse {
  { default_model: "", allowed_models: [], updated_at: "" }
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
    ai_config: empty_ai_config(),
    catalog: [],
    models_error: None,
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
    editing_runtime_spec_json: "",
    editing_runtime_enabled: "true",
    editing_runtime_default: "false",
    creating_model: false,
    model_search: "",
    model_catalog_mode: Recommended,
    confirming_model_remove_id: None,
  }
}
