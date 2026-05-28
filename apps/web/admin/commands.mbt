///|
fn load_users_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  @shared.get_json(@sdk.admin_users_path(100), fn(result) {
    dispatch(UsersLoaded(result))
  })
}

///|
fn load_secrets_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  @shared.get_json(@sdk.admin_secrets_path(), fn(result) {
    dispatch(SecretsLoaded(result))
  })
}

///|
fn load_user_projects_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  user_id : String,
) -> @rabbita.Cmd {
  @shared.get_json(@sdk.admin_user_projects_path(user_id), fn(result) {
    dispatch(UserProjectsLoaded(user_id, result))
  })
}

///|
fn load_runtimes_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  @shared.get_json(@sdk.admin_runtimes_path(), fn(result) {
    dispatch(RuntimesLoaded(result))
  })
}

///|
fn refresh_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  @rabbita.batch([
    load_users_cmd(dispatch),
    load_secrets_cmd(dispatch),
    load_runtimes_cmd(dispatch),
  ])
}

///|
fn create_secret_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  name : String,
  value : String,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateAdminSecretRequest = { name, value }
  @shared.post_json(@sdk.admin_secrets_path(), payload, fn(result) {
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
  @shared.patch_json(@sdk.admin_secret_path(id), payload, fn(result) {
    dispatch(SecretUpdated(result))
  })
}

///|
fn delete_secret_cmd(
  dispatch : @rabbita.Dispatch[AdminMsg],
  id : String,
) -> @rabbita.Cmd {
  @shared.delete_empty(@sdk.admin_secret_path(id), fn(result) {
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
  @shared.put_json(@sdk.admin_runtime_path(id), payload, fn(result) {
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
  @shared.post_json(@sdk.admin_runtimes_path(), payload, fn(result) {
    dispatch(RuntimeSaved(result))
  })
}

///|
fn logout_cmd(dispatch : @rabbita.Dispatch[AdminMsg]) -> @rabbita.Cmd {
  @shared.post_empty("/api/admin/logout", fn(result) {
    dispatch(LoggedOut(result))
  })
}

///|
fn redirect_admin_login_cmd() -> @rabbita.Cmd {
  @cmd.custom_cmd(fn(_) { js_redirect("/admin/login") })
}

///|
extern "js" fn js_redirect(path : String) -> Unit =
  #| (path) => { window.location.assign(path); }
