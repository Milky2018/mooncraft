///|
fn load_users_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  get_json(@sdk.admin_users_path(100), fn(result) {
    dispatch(UsersLoaded(result))
  })
}

///|
fn load_keys_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  get_json(@sdk.admin_ai_keys_path(), fn(result) {
    dispatch(KeysLoaded(result))
  })
}

///|
fn load_secrets_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  get_json(@sdk.admin_secrets_path(), fn(result) {
    dispatch(SecretsLoaded(result))
  })
}

///|
fn load_user_projects_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  user_id : String,
) -> @rabbita.Cmd {
  get_json(@sdk.admin_user_projects_path(user_id), fn(result) {
    dispatch(UserProjectsLoaded(user_id, result))
  })
}

///|
fn load_config_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  get_json(@sdk.admin_ai_config_path(), fn(result) {
    dispatch(ConfigLoaded(result))
  })
}

///|
fn load_runtimes_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  get_json(@sdk.admin_runtimes_path(), fn(result) {
    dispatch(RuntimesLoaded(result))
  })
}

///|
fn load_catalog_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  get_json(@sdk.admin_ai_models_path(), fn(result) {
    dispatch(CatalogLoaded(result))
  })
}

///|
fn refresh_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  @rabbita.batch([
    load_users_cmd(dispatch),
    load_keys_cmd(dispatch),
    load_secrets_cmd(dispatch),
    load_runtimes_cmd(dispatch),
    load_config_cmd(dispatch),
    load_catalog_cmd(dispatch),
  ])
}

///|
fn create_key_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  label : String,
  api_key : String,
  priority : Int,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateAdminAiKeyRequest = { label, api_key, priority }
  post_json(@sdk.admin_ai_keys_path(), payload, fn(result) {
    dispatch(KeyCreated(result))
  })
}

///|
fn update_key_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  id : String,
  label : String,
  api_key : String,
  status : String,
  priority : Int,
) -> @rabbita.Cmd {
  let payload : @sdk.UpdateAdminAiKeyRequest = {
    label,
    api_key,
    status,
    priority,
  }
  patch_json(@sdk.admin_ai_key_path(id), payload, fn(result) {
    dispatch(KeyUpdated(result))
  })
}

///|
fn delete_key_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  id : String,
) -> @rabbita.Cmd {
  delete_empty(@sdk.admin_ai_key_path(id), fn(result) {
    dispatch(KeyDeleted(id, result))
  })
}

///|
fn create_secret_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  name : String,
  value : String,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateAdminSecretRequest = { name, value }
  post_json(@sdk.admin_secrets_path(), payload, fn(result) {
    dispatch(SecretCreated(result))
  })
}

///|
fn update_secret_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  id : String,
  name : String,
  value : String,
) -> @rabbita.Cmd {
  let payload : @sdk.UpdateAdminSecretRequest = { name, value }
  patch_json(@sdk.admin_secret_path(id), payload, fn(result) {
    dispatch(SecretUpdated(result))
  })
}

///|
fn delete_secret_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  id : String,
) -> @rabbita.Cmd {
  delete_empty(@sdk.admin_secret_path(id), fn(result) {
    dispatch(SecretDeleted(id, result))
  })
}

///|
fn save_runtime_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  id : String,
  name : String,
  spec_json : String,
  enabled : Bool,
  is_default : Bool,
) -> @rabbita.Cmd {
  let payload : @sdk.UpdateAdminRuntimeRequest = {
    name,
    spec_json,
    enabled,
    is_default,
  }
  put_json(@sdk.admin_runtime_path(id), payload, fn(result) {
    dispatch(RuntimeSaved(result))
  })
}

///|
fn create_runtime_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  name : String,
  spec_json : String,
  enabled : Bool,
  is_default : Bool,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateAdminRuntimeRequest = {
    name,
    spec_json,
    enabled,
    is_default,
  }
  post_json(@sdk.admin_runtimes_path(), payload, fn(result) {
    dispatch(RuntimeSaved(result))
  })
}

///|
fn save_models_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  default_model : String,
  allowed_models : Array[String],
) -> @rabbita.Cmd {
  let payload : @sdk.UpdateAdminAiConfigRequest = {
    default_model,
    allowed_models,
  }
  put_json(@sdk.admin_ai_config_path(), payload, fn(result) {
    dispatch(ModelsUpdated(result))
  })
}

///|
fn logout_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  post_empty("/api/admin/logout", fn(result) { dispatch(LoggedOut(result)) })
}

///|
fn redirect_admin_login_cmd() -> @rabbita.Cmd {
  @cmd.custom_cmd(fn(_) { js_redirect("/admin/login") })
}

///|
extern "js" fn js_redirect(path : String) -> Unit =
  #| (path) => { window.location.assign(path); }
