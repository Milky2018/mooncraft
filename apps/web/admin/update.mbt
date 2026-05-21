///|
fn api_notice(prefix : String, error : @sdk.ApiError) -> String {
  prefix + " " + error.message
}

///|
fn parse_priority(value : String) -> Int {
  @string.parse_int(value.trim().to_owned()) catch {
    _ => 100
  }
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
fn replace_key(
  keys : Array[@sdk.AdminAiKeySummary],
  replacement : @sdk.AdminAiKeySummary,
) -> Array[@sdk.AdminAiKeySummary] {
  let next = []
  let mut found = false
  for key in keys {
    if key.id == replacement.id {
      next.push(replacement)
      found = true
    } else {
      next.push(key)
    }
  }
  if !found {
    next.push(replacement)
  }
  next
}

///|
fn remove_key(
  keys : Array[@sdk.AdminAiKeySummary],
  id : String,
) -> Array[@sdk.AdminAiKeySummary] {
  let next = []
  for key in keys {
    if key.id != id {
      next.push(key)
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
fn key_by_id(
  keys : Array[@sdk.AdminAiKeySummary],
  id : String,
) -> @sdk.AdminAiKeySummary? {
  for key in keys {
    if key.id == id {
      return Some(key)
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
    KeysLoaded(Ok(response)) =>
      (@rabbita.none, { ..model, keys: response.items, loading: false })
    KeysLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          notice: Some(api_notice("Failed to load keys.", error)),
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
          creating_key: false,
          creating_model: false,
          editing_key_id: None,
          editing_runtime_id: None,
          confirming_key_delete_id: None,
          confirming_model_remove_id: None,
          notice: None,
        },
      )
    Logout => (logout_cmd(dispatch), { ..model, notice: None })
    LoggedOut(Ok(_)) => (redirect_admin_login_cmd(), model)
    LoggedOut(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to log out.", error)) },
      )
    OpenCreateKey =>
      (
        @rabbita.none,
        {
          ..model,
          view: Keys,
          creating_key: true,
          key_label: "",
          key_secret: "",
          key_priority: "100",
          editing_key_id: None,
          confirming_key_delete_id: None,
          notice: None,
        },
      )
    CancelCreateKey =>
      (
        @rabbita.none,
        { ..model, creating_key: false, key_label: "", key_secret: "" },
      )
    KeyLabelChanged(value) => (@rabbita.none, { ..model, key_label: value })
    KeySecretChanged(value) => (@rabbita.none, { ..model, key_secret: value })
    KeyPriorityChanged(value) =>
      (@rabbita.none, { ..model, key_priority: value })
    SaveCreateKey =>
      (
        create_key_cmd(
          dispatch,
          model.key_label,
          model.key_secret,
          parse_priority(model.key_priority),
        ),
        { ..model, notice: None },
      )
    KeyCreated(Ok(key)) =>
      (
        @rabbita.none,
        {
          ..model,
          keys: replace_key(model.keys, key),
          creating_key: false,
          key_label: "",
          key_secret: "",
          notice: Some("Key added."),
        },
      )
    KeyCreated(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to add key.", error)) },
      )
    StartEditKey(id) =>
      match key_by_id(model.keys, id) {
        Some(key) =>
          (
            @rabbita.none,
            {
              ..model,
              creating_key: false,
              editing_key_id: Some(id),
              editing_key_label: key.label,
              editing_key_secret: "",
              editing_key_status: key.status,
              editing_key_priority: key.priority.to_string(),
              confirming_key_delete_id: None,
            },
          )
        None => (@rabbita.none, model)
      }
    CancelEditKey => (@rabbita.none, { ..model, editing_key_id: None })
    EditKeyLabelChanged(value) =>
      (@rabbita.none, { ..model, editing_key_label: value })
    EditKeySecretChanged(value) =>
      (@rabbita.none, { ..model, editing_key_secret: value })
    EditKeyStatusChanged(value) =>
      (@rabbita.none, { ..model, editing_key_status: value })
    EditKeyPriorityChanged(value) =>
      (@rabbita.none, { ..model, editing_key_priority: value })
    SaveEditKey(id) =>
      (
        update_key_cmd(
          dispatch,
          id,
          model.editing_key_label,
          model.editing_key_secret,
          model.editing_key_status,
          parse_priority(model.editing_key_priority),
        ),
        { ..model, notice: None },
      )
    KeyUpdated(Ok(key)) =>
      (
        @rabbita.none,
        {
          ..model,
          keys: replace_key(model.keys, key),
          editing_key_id: None,
          notice: Some("Key updated."),
        },
      )
    KeyUpdated(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to update key.", error)) },
      )
    RequestDeleteKey(id) =>
      if model.confirming_key_delete_id == Some(id) {
        (
          delete_key_cmd(dispatch, id),
          { ..model, notice: None, editing_key_id: None },
        )
      } else {
        (@rabbita.none, { ..model, confirming_key_delete_id: Some(id) })
      }
    KeyDeleted(id, Ok(_)) =>
      (
        @rabbita.none,
        {
          ..model,
          keys: remove_key(model.keys, id),
          confirming_key_delete_id: None,
          notice: Some("Key deleted."),
        },
      )
    KeyDeleted(_, Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to delete key.", error)) },
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
          editing_runtime_id: None,
          editing_runtime_name: "",
          editing_runtime_spec_json: "",
          editing_runtime_enabled: "true",
          editing_runtime_default: "false",
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
          editing_runtime_id: None,
          editing_runtime_name: "",
          editing_runtime_spec_json: "",
          editing_runtime_enabled: "true",
          editing_runtime_default: "false",
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
          notice: None,
        },
      )
    CancelCreateModel =>
      (@rabbita.none, { ..model, creating_model: false, model_search: "" })
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
        { ..model, notice: None },
      )
    }
    SetDefaultModel(id) =>
      (
        save_models_cmd(dispatch, id, model.ai_config.allowed_models),
        { ..model, notice: None },
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
          { ..model, notice: None },
        )
      } else {
        (@rabbita.none, { ..model, confirming_model_remove_id: Some(id) })
      }
    ModelsUpdated(Ok(config)) =>
      (
        @rabbita.none,
        {
          ..model,
          ai_config: config,
          creating_model: false,
          confirming_model_remove_id: None,
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
