///|
fn load_theme_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  @cmd.custom_cmd(fn(scheduler) {
    js_load_theme_mode(succeed=(mode, resolved_mode) => {
      scheduler.add(
        dispatch(
          ThemeModeLoaded(
            theme_mode_from_string(mode),
            resolved_theme_mode_from_string(resolved_mode),
          ),
        ),
      )
    })
  })
}

///|
fn persist_theme_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  theme_mode : ThemeMode,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(fn(scheduler) {
    js_persist_theme_mode(theme_mode.storage_value(), succeed=resolved_mode => {
      scheduler.add(
        dispatch(
          ThemeModeLoaded(
            theme_mode,
            resolved_theme_mode_from_string(resolved_mode),
          ),
        ),
      )
    })
  })
}

///|
fn load_session_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  get_json(@sdk.session_path(), fn(result) { dispatch(SessionLoaded(result)) })
}

///|
fn load_projects_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  get_json(@sdk.projects_path(), fn(result) { dispatch(ProjectsLoaded(result)) })
}

///|
fn load_messages_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  get_json(@sdk.messages_path(project_id), fn(result) {
    dispatch(MessagesLoaded(result))
  })
}

///|
fn load_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  @rabbita.batch([
    get_json(@sdk.project_path(project_id), fn(result) {
      dispatch(ProjectLoaded(result))
    }),
    load_messages_cmd(dispatch, project_id),
  ])
}

///|
fn create_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  display_name : String,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateProjectRequest = { display_name, }
  post_json(@sdk.projects_path(), payload, fn(result) {
    dispatch(ProjectCreated(result))
  })
}

///|
fn rename_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  display_name : String,
) -> @rabbita.Cmd {
  let payload : @sdk.UpdateProjectRequest = { display_name, }
  put_json(@sdk.project_path(project_id), payload, fn(result) {
    dispatch(ProjectRenamed(result))
  })
}

///|
fn create_run_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  content : String,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateRunRequest = { content, }
  post_json(@sdk.create_run_path(project_id), payload, fn(result) {
    dispatch(RunCreated(result))
  })
}

///|
fn delete_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  delete_empty(@sdk.project_path(project_id), fn(result) {
    dispatch(ProjectDeleted(project_id, result))
  })
}

///|
fn load_run_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  run_id : String,
) -> @rabbita.Cmd {
  get_json(@sdk.run_path(project_id, run_id), fn(result) {
    dispatch(RunLoaded(project_id, run_id, result))
  })
}

///|
fn load_run_events_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  run_id : String,
  after_seq : Int,
) -> @rabbita.Cmd {
  get_json(@sdk.run_events_path(project_id, run_id, after_seq), fn(result) {
    dispatch(RunEventsLoaded(result))
  })
}

///|
fn logout_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  post_empty(@sdk.logout_path(), fn(result) { dispatch(LoggedOut(result)) })
}

///|
fn save_ai_settings_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Cmd {
  let payload : @sdk.UpdateAiSettingsRequest = {
    provider: model.account_ai_provider,
    model: model.account_ai_model,
    api_key: model.account_ai_api_key,
  }
  put_json(@sdk.ai_settings_path(), payload, fn(result) {
    dispatch(AiSettingsSaved(result))
  })
}

///|
fn load_model_options_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  provider : String,
) -> @rabbita.Cmd {
  get_json(@sdk.ai_model_options_path(provider), fn(result) {
    dispatch(ModelOptionsLoaded(provider, result))
  })
}
