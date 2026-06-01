///|
fn api_notice(prefix : String, error : @sdk.ApiError) -> String {
  "\{prefix} \{error.message}"
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
fn default_runtime_config_json() -> String {
  @sdk.default_runtime_config_json()
}

///|
fn new_runtime_editor() -> AdminRuntimeEditor {
  {
    id: None,
    name: "",
    config_json: default_runtime_config_json(),
    enabled: "true",
    is_default: "false",
  }
}

///|
fn runtime_editor_from_runtime(
  runtime : @sdk.RuntimeDetail,
) -> AdminRuntimeEditor {
  {
    id: Some(runtime.id),
    name: runtime.name,
    config_json: runtime.config_json,
    enabled: if runtime.enabled {
      "true"
    } else {
      "false"
    },
    is_default: if runtime.is_default {
      "true"
    } else {
      "false"
    },
  }
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
          active_action_menu: None,
        },
      )
    UsersLoaded(Ok(response)) =>
      (
        @rabbita.none,
        {
          ..model,
          users: { ..model.users, items: response.items },
          loading: false,
        },
      )
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
      if model.users.expanded_user_id == Some(user_id) {
        (
          @rabbita.none,
          {
            ..model,
            users: {
              ..model.users,
              expanded_user_id: None,
              expanded_projects: [],
            },
          },
        )
      } else {
        (
          load_user_projects_cmd(dispatch, user_id),
          {
            ..model,
            users: {
              ..model.users,
              expanded_user_id: Some(user_id),
              expanded_projects: [],
              projects_loading: true,
            },
            notice: None,
          },
        )
      }
    UserProjectsLoaded(user_id, Ok(response)) =>
      if model.users.expanded_user_id == Some(user_id) {
        (
          @rabbita.none,
          {
            ..model,
            users: {
              ..model.users,
              expanded_projects: response.projects,
              projects_loading: false,
            },
          },
        )
      } else {
        (@rabbita.none, model)
      }
    UserProjectsLoaded(user_id, Err(error)) =>
      if model.users.expanded_user_id == Some(user_id) {
        (
          @rabbita.none,
          {
            ..model,
            users: { ..model.users, projects_loading: false },
            notice: Some(api_notice("Failed to load user projects.", error)),
          },
        )
      } else {
        (@rabbita.none, model)
      }
    SecretsLoaded(Ok(response)) =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: { ..model.secrets, items: response.items },
          loading: false,
        },
      )
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
      (
        @rabbita.none,
        {
          ..model,
          runtimes: { ..model.runtimes, items: response.items },
          loading: false,
        },
      )
    RuntimesLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          loading: false,
          notice: Some(api_notice("Failed to load Runtimes.", error)),
        },
      )
    ShowView(view) =>
      (
        @rabbita.none,
        {
          ..model,
          view,
          secrets: {
            ..model.secrets,
            create: None,
            edit: None,
            confirming_delete_id: None,
          },
          runtimes: { ..model.runtimes, editor: None },
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
          secrets: {
            ..model.secrets,
            create: Some({ name: "", value: "" }),
            edit: None,
            confirming_delete_id: None,
          },
          active_action_menu: None,
          notice: None,
        },
      )
    CancelCreateSecret =>
      (@rabbita.none, { ..model, secrets: { ..model.secrets, create: None } })
    SecretNameChanged(value) => {
      let create = model.secrets.create.map(fn(state) {
        { ..state, name: value }
      })
      (@rabbita.none, { ..model, secrets: { ..model.secrets, create, } })
    }
    SecretValueChanged(value) => {
      let create = model.secrets.create.map(fn(state) { { ..state, value, } })
      (@rabbita.none, { ..model, secrets: { ..model.secrets, create, } })
    }
    SaveCreateSecret =>
      match model.secrets.create {
        Some(create) =>
          (
            create_secret_cmd(dispatch, create.name, create.value),
            { ..model, notice: None },
          )
        None => (@rabbita.none, model)
      }
    SecretCreated(Ok(secret)) =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: {
            ..model.secrets,
            items: replace_secret(model.secrets.items, secret),
            create: None,
          },
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
      match secret_by_id(model.secrets.items, id) {
        Some(secret) =>
          (
            @rabbita.none,
            {
              ..model,
              secrets: {
                ..model.secrets,
                create: None,
                edit: Some({ id, name: secret.name, value: "" }),
                confirming_delete_id: None,
              },
              active_action_menu: None,
            },
          )
        None => (@rabbita.none, model)
      }
    CancelEditSecret =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: { ..model.secrets, edit: None },
          active_action_menu: None,
        },
      )
    EditSecretNameChanged(value) => {
      let edit = model.secrets.edit.map(fn(state) { { ..state, name: value } })
      (@rabbita.none, { ..model, secrets: { ..model.secrets, edit, } })
    }
    EditSecretValueChanged(value) => {
      let edit = model.secrets.edit.map(fn(state) { { ..state, value, } })
      (@rabbita.none, { ..model, secrets: { ..model.secrets, edit, } })
    }
    SaveEditSecret(id) =>
      match model.secrets.edit {
        Some(edit) =>
          (
            update_secret_cmd(dispatch, id, edit.name, edit.value),
            { ..model, notice: None },
          )
        None => (@rabbita.none, model)
      }
    SecretUpdated(Ok(secret)) =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: {
            ..model.secrets,
            items: replace_secret(model.secrets.items, secret),
            edit: None,
          },
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
      if model.secrets.confirming_delete_id == Some(id) {
        (
          delete_secret_cmd(dispatch, id),
          {
            ..model,
            notice: None,
            secrets: { ..model.secrets, edit: None },
            active_action_menu: None,
          },
        )
      } else {
        (
          @rabbita.none,
          {
            ..model,
            secrets: { ..model.secrets, confirming_delete_id: Some(id) },
            active_action_menu: Some(action_menu_key("secret", id)),
          },
        )
      }
    SecretDeleted(id, Ok(_)) =>
      (
        @rabbita.none,
        {
          ..model,
          secrets: {
            ..model.secrets,
            items: remove_secret(model.secrets.items, id),
            confirming_delete_id: None,
          },
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
          runtimes: { ..model.runtimes, editor: Some(new_runtime_editor()) },
          active_action_menu: None,
          notice: None,
        },
      )
    StartEditRuntime(id) => {
      let selected = runtime_by_id(model.runtimes.items, id)
      match selected {
        Some(runtime) =>
          (
            @rabbita.none,
            {
              ..model,
              view: Runtimes,
              runtimes: {
                ..model.runtimes,
                editor: Some(runtime_editor_from_runtime(runtime)),
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
          runtimes: { ..model.runtimes, editor: None },
          active_action_menu: None,
        },
      )
    RuntimeNameChanged(value) => {
      let editor = model.runtimes.editor.map(fn(state) {
        { ..state, name: value }
      })
      (@rabbita.none, { ..model, runtimes: { ..model.runtimes, editor, } })
    }
    RuntimeConfigChanged(value) => {
      let editor = model.runtimes.editor.map(fn(state) {
        { ..state, config_json: value }
      })
      (@rabbita.none, { ..model, runtimes: { ..model.runtimes, editor, } })
    }
    RuntimeEnabledChanged(value) => {
      let editor = model.runtimes.editor.map(fn(state) {
        { ..state, enabled: value }
      })
      (@rabbita.none, { ..model, runtimes: { ..model.runtimes, editor, } })
    }
    RuntimeDefaultChanged(value) => {
      let editor = model.runtimes.editor.map(fn(state) {
        { ..state, is_default: value }
      })
      (@rabbita.none, { ..model, runtimes: { ..model.runtimes, editor, } })
    }
    SaveCreateRuntime =>
      match model.runtimes.editor {
        Some(editor) =>
          (
            create_runtime_cmd(
              dispatch,
              editor.name,
              editor.config_json,
              admin_bool_value(editor.enabled),
              admin_bool_value(editor.is_default),
            ),
            { ..model, notice: None },
          )
        None => (@rabbita.none, model)
      }
    SaveRuntime(id) =>
      match model.runtimes.editor {
        Some(editor) =>
          (
            save_runtime_cmd(
              dispatch,
              id,
              editor.name,
              editor.config_json,
              admin_bool_value(editor.enabled),
              admin_bool_value(editor.is_default),
            ),
            { ..model, notice: None },
          )
        None => (@rabbita.none, model)
      }
    RuntimeSaved(Ok(runtime)) =>
      (
        @rabbita.none,
        {
          ..model,
          runtimes: {
            items: replace_runtime(model.runtimes.items, runtime),
            editor: None,
          },
          active_action_menu: None,
          notice: Some("Runtime saved."),
        },
      )
    RuntimeSaved(Err(error)) =>
      (
        @rabbita.none,
        { ..model, notice: Some(api_notice("Failed to save Runtime.", error)) },
      )
  }
}
