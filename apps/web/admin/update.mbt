///|
fn api_notice(prefix : String, error : @sdk.ApiError) -> String {
  prefix + " " + error.message
}

///|
fn model_contains(items : Array[String], id : String) -> Bool {
  for item in items {
    if item == id {
      return true
    }
  }
  false
}

///|
fn append_model(items : Array[String], id : String) -> Array[String] {
  let next = []
  for item in items {
    next.push(item)
  }
  if !model_contains(next, id) {
    next.push(id)
  }
  next
}

///|
fn remove_model(items : Array[String], id : String) -> Array[String] {
  let next = []
  for item in items {
    if item != id {
      next.push(item)
    }
  }
  next
}

///|
fn replace_secret(
  secrets : Array[@sdk.AdminSecretSummary],
  replacement : @sdk.AdminSecretSummary,
) -> Array[@sdk.AdminSecretSummary] {
  let next = []
  let mut found = false
  for secret in secrets {
    if secret.id == replacement.id {
      next.push(replacement)
      found = true
    } else {
      next.push(secret)
    }
  }
  if !found {
    next.push(replacement)
  }
  next
}

///|
fn remove_secret(
  secrets : Array[@sdk.AdminSecretSummary],
  id : String,
) -> Array[@sdk.AdminSecretSummary] {
  let next = []
  for secret in secrets {
    if secret.id != id {
      next.push(secret)
    }
  }
  next
}

///|
fn replace_runtime(
  runtimes : Array[@sdk.RuntimeDetail],
  replacement : @sdk.RuntimeDetail,
) -> Array[@sdk.RuntimeDetail] {
  let next = []
  let mut found = false
  for runtime in runtimes {
    if runtime.id == replacement.id {
      next.push(replacement)
      found = true
    } else if replacement.is_default {
      next.push({ ..runtime, is_default: false })
    } else {
      next.push(runtime)
    }
  }
  if !found {
    next.push(replacement)
  }
  next
}

///|
fn admin_bool_value(value : String) -> Bool {
  value == "true"
}

///|
fn default_runtime_spec_json() -> String {
  @sdk.default_runtime_manifest_json()
}

///|
fn runtime_by_id(
  runtimes : Array[@sdk.RuntimeDetail],
  id : String,
) -> @sdk.RuntimeDetail? {
  for runtime in runtimes {
    if runtime.id == id {
      return Some(runtime)
    }
  }
  None
}

///|
fn secret_by_id(
  secrets : Array[@sdk.AdminSecretSummary],
  id : String,
) -> @sdk.AdminSecretSummary? {
  for secret in secrets {
    if secret.id == id {
      return Some(secret)
    }
  }
  None
}

///|
fn update(
  dispatch : @rabbita.Dispatch[AdminMsg],
  msg : AdminMsg,
  model : AdminModel,
) -> (@rabbita.Cmd, AdminModel) {
  match msg {
    Bootstrap | Refresh =>
      (
        refresh_cmd(dispatch),
        {
          ..model,
          boot_requested: true,
          loading: true,
          notice: None,
          models_error: None,
          active_action_menu: None,
        },
      )
    UsersLoaded(Ok(response)) =>
      (@rabbita.none, { ..model, users: response.items, loading: false })
    UsersLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          notice: Some(api_notice("Failed to load users.", error)),
        },
      )
    ToggleUser(user_id) =>
      if model.expanded_user_id == Some(user_id) {
        (
          @rabbita.none,
          { ..model, expanded_user_id: None, expanded_user_projects: [] },
        )
      } else {
        (
          load_user_projects_cmd(dispatch, user_id),
          {
            ..model,
            expanded_user_id: Some(user_id),
            expanded_user_projects: [],
            user_projects_loading: true,
            notice: None,
          },
        )
      }
    UserProjectsLoaded(user_id, Ok(response)) =>
      if model.expanded_user_id == Some(user_id) {
        (
          @rabbita.none,
          {
            ..model,
            expanded_user_projects: response.projects,
            user_projects_loading: false,
          },
        )
      } else {
        (@rabbita.none, model)
      }
    UserProjectsLoaded(user_id, Err(error)) =>
      if model.expanded_user_id == Some(user_id) {
        (
          @rabbita.none,
          {
            ..model,
            user_projects_loading: false,
            notice: Some(api_notice("Failed to load user projects.", error)),
          },
        )
      } else {
        (@rabbita.none, model)
      }
    SecretsLoaded(Ok(response)) =>
      (@rabbita.none, { ..model, secrets: response.items, loading: false })
    SecretsLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          notice: Some(api_notice("Failed to load secrets.", error)),
        },
      )
    RuntimesLoaded(Ok(response)) =>
      (@rabbita.none, { ..model, runtimes: response.items, loading: false })
    RuntimesLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          notice: Some(api_notice("Failed to load Runtimes.", error)),
        },
      )
    ConfigLoaded(Ok(response)) =>
      (@rabbita.none, { ..model, ai_config: response, loading: false })
    ConfigLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          notice: Some(api_notice("Failed to load model config.", error)),
        },
      )
    CatalogLoaded(Ok(response)) =>
      (
        @rabbita.none,
        { ..model, catalog: response.items, loading: false, models_error: None },
      )
    CatalogLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          models_error: Some(api_notice("Failed to load model catalog.", error)),
        },
      )
    ShowView(view) =>
      (
        @rabbita.none,
        {
          ..model,
          view,
          creating_secret: false,
          creating_model: false,
          editing_secret_id: None,
          editing_runtime_id: None,
          confirming_secret_delete_id: None,
          confirming_model_remove_id: None,
          active_action_menu: None,
          notice: None,
        },
      )
    ToggleActionMenu(key) =>
      (
        @rabbita.none,
        {
          ..model,
          active_action_menu: if model.active_action_menu == Some(key) {
            None
          } else {
            Some(key)
          },
        },
      )
    Logout => (logout_cmd(dispatch), { ..model, notice: None })
    LoggedOut(Ok(_)) => (redirect_admin_login_cmd(), model)
    LoggedOut(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to log out.", error)) },
      )
    OpenCreateSecret =>
      (
        @rabbita.none,
        {
          ..model,
          view: Secrets,
          creating_secret: true,
          secret_name: "",
          secret_value: "",
          editing_secret_id: None,
          confirming_secret_delete_id: None,
          active_action_menu: None,
          notice: None,
        },
      )
    CancelCreateSecret =>
      (
        @rabbita.none,
        { ..model, creating_secret: false, secret_name: "", secret_value: "" },
      )
    SecretNameChanged(value) => (@rabbita.none, { ..model, secret_name: value })
    SecretValueChanged(value) =>
      (@rabbita.none, { ..model, secret_value: value })
    SaveCreateSecret =>
      (
        create_secret_cmd(dispatch, model.secret_name, model.secret_value),
        { ..model, notice: None },
      )
    SecretCreated(Ok(secret)) =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: replace_secret(model.secrets, secret),
          creating_secret: false,
          secret_name: "",
          secret_value: "",
          active_action_menu: None,
          notice: Some("Secret added."),
        },
      )
    SecretCreated(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to add secret.", error)) },
      )
    StartEditSecret(id) =>
      match secret_by_id(model.secrets, id) {
        Some(secret) =>
          (
            @rabbita.none,
            {
              ..model,
              creating_secret: false,
              editing_secret_id: Some(id),
              editing_secret_name: secret.name,
              editing_secret_value: "",
              confirming_secret_delete_id: None,
              active_action_menu: None,
            },
          )
        None => (@rabbita.none, model)
      }
    CancelEditSecret =>
      (
        @rabbita.none,
        { ..model, editing_secret_id: None, active_action_menu: None },
      )
    EditSecretNameChanged(value) =>
      (@rabbita.none, { ..model, editing_secret_name: value })
    EditSecretValueChanged(value) =>
      (@rabbita.none, { ..model, editing_secret_value: value })
    SaveEditSecret(id) =>
      (
        update_secret_cmd(
          dispatch,
          id,
          model.editing_secret_name,
          model.editing_secret_value,
        ),
        { ..model, notice: None },
      )
    SecretUpdated(Ok(secret)) =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: replace_secret(model.secrets, secret),
          editing_secret_id: None,
          active_action_menu: None,
          notice: Some("Secret updated."),
        },
      )
    SecretUpdated(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to update secret.", error)) },
      )
    RequestDeleteSecret(id) =>
      if model.confirming_secret_delete_id == Some(id) {
        (
          delete_secret_cmd(dispatch, id),
          {
            ..model,
            notice: None,
            editing_secret_id: None,
            active_action_menu: None,
          },
        )
      } else {
        (
          @rabbita.none,
          {
            ..model,
            confirming_secret_delete_id: Some(id),
            active_action_menu: Some(action_menu_key("secret", id)),
          },
        )
      }
    SecretDeleted(id, Ok(_)) =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: remove_secret(model.secrets, id),
          confirming_secret_delete_id: None,
          active_action_menu: None,
          notice: Some("Secret deleted."),
        },
      )
    SecretDeleted(_, Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to delete secret.", error)) },
      )
    OpenCreateRuntime =>
      (
        @rabbita.none,
        {
          ..model,
          view: Runtimes,
          creating_runtime: true,
          editing_runtime_id: None,
          editing_runtime_name: "",
          editing_runtime_spec_json: default_runtime_spec_json(),
          editing_runtime_enabled: "true",
          editing_runtime_default: "false",
          active_action_menu: None,
          notice: None,
        },
      )
    StartEditRuntime(id) => {
      let selected = runtime_by_id(model.runtimes, id)
      match selected {
        Some(runtime) =>
          (
            @rabbita.none,
            {
              ..model,
              view: Runtimes,
              creating_runtime: false,
              editing_runtime_id: Some(id),
              editing_runtime_name: runtime.name,
              editing_runtime_spec_json: runtime.spec_json,
              editing_runtime_enabled: if runtime.enabled {
                "true"
              } else {
                "false"
              },
              editing_runtime_default: if runtime.is_default {
                "true"
              } else {
                "false"
              },
              active_action_menu: None,
              notice: None,
            },
          )
        None => (@rabbita.none, model)
      }
    }
    CancelEditRuntime =>
      (
        @rabbita.none,
        {
          ..model,
          creating_runtime: false,
          editing_runtime_id: None,
          editing_runtime_name: "",
          editing_runtime_spec_json: "",
          editing_runtime_enabled: "true",
          editing_runtime_default: "false",
          active_action_menu: None,
        },
      )
    RuntimeNameChanged(value) =>
      (@rabbita.none, { ..model, editing_runtime_name: value })
    RuntimeSpecChanged(value) =>
      (@rabbita.none, { ..model, editing_runtime_spec_json: value })
    RuntimeEnabledChanged(value) =>
      (@rabbita.none, { ..model, editing_runtime_enabled: value })
    RuntimeDefaultChanged(value) =>
      (@rabbita.none, { ..model, editing_runtime_default: value })
    SaveCreateRuntime =>
      (
        create_runtime_cmd(
          dispatch,
          model.editing_runtime_name,
          model.editing_runtime_spec_json,
          admin_bool_value(model.editing_runtime_enabled),
          admin_bool_value(model.editing_runtime_default),
        ),
        { ..model, notice: None },
      )
    SaveRuntime(id) =>
      (
        save_runtime_cmd(
          dispatch,
          id,
          model.editing_runtime_name,
          model.editing_runtime_spec_json,
          admin_bool_value(model.editing_runtime_enabled),
          admin_bool_value(model.editing_runtime_default),
        ),
        { ..model, notice: None },
      )
    RuntimeSaved(Ok(runtime)) =>
      (
        @rabbita.none,
        {
          ..model,
          runtimes: replace_runtime(model.runtimes, runtime),
          creating_runtime: false,
          editing_runtime_id: None,
          editing_runtime_name: "",
          editing_runtime_spec_json: "",
          editing_runtime_enabled: "true",
          editing_runtime_default: "false",
          active_action_menu: None,
          notice: Some("Runtime saved."),
        },
      )
    RuntimeSaved(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to save Runtime.", error)) },
      )
    OpenCreateModel =>
      (
        @rabbita.none,
        {
          ..model,
          view: Models,
          creating_model: true,
          model_search: "",
          model_catalog_mode: Recommended,
          confirming_model_remove_id: None,
          active_action_menu: None,
          notice: None,
        },
      )
    CancelCreateModel =>
      (
        @rabbita.none,
        {
          ..model,
          creating_model: false,
          model_search: "",
          active_action_menu: None,
        },
      )
    ModelSearchChanged(value) =>
      (@rabbita.none, { ..model, model_search: value })
    SetModelCatalogMode(mode) =>
      (@rabbita.none, { ..model, model_catalog_mode: mode })
    AddModel(id) => {
      let allowed = append_model(model.ai_config.allowed_models, id)
      let default_model = if model.ai_config.default_model == "" {
        id
      } else {
        model.ai_config.default_model
      }
      (
        save_models_cmd(dispatch, default_model, allowed),
        { ..model, notice: None, active_action_menu: None },
      )
    }
    SetDefaultModel(id) =>
      (
        save_models_cmd(dispatch, id, model.ai_config.allowed_models),
        { ..model, notice: None, active_action_menu: None },
      )
    RequestRemoveModel(id) =>
      if model.confirming_model_remove_id == Some(id) {
        let allowed = remove_model(model.ai_config.allowed_models, id)
        let default_model = if model.ai_config.default_model == id {
          match allowed.get(0) {
            Some(next) => next
            None => ""
          }
        } else {
          model.ai_config.default_model
        }
        (
          save_models_cmd(dispatch, default_model, allowed),
          { ..model, notice: None, active_action_menu: None },
        )
      } else {
        (
          @rabbita.none,
          {
            ..model,
            confirming_model_remove_id: Some(id),
            active_action_menu: Some(action_menu_key("model", id)),
          },
        )
      }
    ModelsUpdated(Ok(config)) =>
      (
        @rabbita.none,
        {
          ..model,
          ai_config: config,
          creating_model: false,
          confirming_model_remove_id: None,
          active_action_menu: None,
          notice: Some("Models updated."),
        },
      )
    ModelsUpdated(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to update models.", error)) },
      )
  }
}
