///|
enum AdminView {
  Users
  Keys
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
  keys : Array[@sdk.AdminAiKeySummary]
  secrets : Array[@sdk.AdminSecretSummary]
  runtimes : Array[@sdk.RuntimeDetail]
  ai_config : @sdk.AdminAiConfigResponse
  catalog : Array[@sdk.AdminAiModelSummary]
  models_error : String?
  creating_key : Bool
  key_label : String
  key_secret : String
  key_priority : String
  editing_key_id : String?
  editing_key_label : String
  editing_key_secret : String
  editing_key_status : String
  editing_key_priority : String
  confirming_key_delete_id : String?
  creating_secret : Bool
  secret_name : String
  secret_kind : String
  secret_value : String
  editing_secret_id : String?
  editing_secret_name : String
  editing_secret_kind : String
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
  KeysLoaded(Result[@sdk.AdminListAiKeysResponse, @sdk.ApiError])
  SecretsLoaded(Result[@sdk.AdminListSecretsResponse, @sdk.ApiError])
  RuntimesLoaded(Result[@sdk.AdminListRuntimesResponse, @sdk.ApiError])
  ConfigLoaded(Result[@sdk.AdminAiConfigResponse, @sdk.ApiError])
  CatalogLoaded(Result[@sdk.AdminListAiModelsResponse, @sdk.ApiError])
  ShowView(AdminView)
  Logout
  LoggedOut(Result[Unit, @sdk.ApiError])
  OpenCreateKey
  CancelCreateKey
  KeyLabelChanged(String)
  KeySecretChanged(String)
  KeyPriorityChanged(String)
  SaveCreateKey
  KeyCreated(Result[@sdk.AdminAiKeySummary, @sdk.ApiError])
  StartEditKey(String)
  CancelEditKey
  EditKeyLabelChanged(String)
  EditKeySecretChanged(String)
  EditKeyStatusChanged(String)
  EditKeyPriorityChanged(String)
  SaveEditKey(String)
  KeyUpdated(Result[@sdk.AdminAiKeySummary, @sdk.ApiError])
  RequestDeleteKey(String)
  KeyDeleted(String, Result[Unit, @sdk.ApiError])
  OpenCreateSecret
  CancelCreateSecret
  SecretNameChanged(String)
  SecretKindChanged(String)
  SecretValueChanged(String)
  SaveCreateSecret
  SecretCreated(Result[@sdk.AdminSecretSummary, @sdk.ApiError])
  StartEditSecret(String)
  CancelEditSecret
  EditSecretNameChanged(String)
  EditSecretKindChanged(String)
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
    keys: [],
    secrets: [],
    runtimes: [],
    ai_config: empty_ai_config(),
    catalog: [],
    models_error: None,
    creating_key: false,
    key_label: "",
    key_secret: "",
    key_priority: "100",
    editing_key_id: None,
    editing_key_label: "",
    editing_key_secret: "",
    editing_key_status: "active",
    editing_key_priority: "100",
    confirming_key_delete_id: None,
    creating_secret: false,
    secret_name: "",
    secret_kind: "file",
    secret_value: "",
    editing_secret_id: None,
    editing_secret_name: "",
    editing_secret_kind: "file",
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
