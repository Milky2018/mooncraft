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
  @shared.get_json(@sdk.session_path(), fn(result) {
    dispatch(SessionLoaded(result))
  })
}

///|
fn load_projects_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  @shared.get_json(@sdk.projects_path(), fn(result) {
    dispatch(ProjectsLoaded(result))
  })
}

///|
fn load_runtimes_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  @shared.get_json(@sdk.runtimes_path(), fn(result) {
    dispatch(RuntimesLoaded(result))
  })
}

///|
fn load_messages_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  @shared.get_json(@sdk.messages_path(project_id), fn(result) {
    dispatch(MessagesLoaded(project_id, result))
  })
}

///|
fn load_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  @rabbita.batch([
    @shared.get_json(@sdk.project_path(project_id), fn(result) {
      dispatch(ProjectLoaded(project_id, result))
    }),
    load_messages_cmd(dispatch, project_id),
  ])
}

///|
fn create_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  display_name : String,
  runtime_id : String?,
) -> @rabbita.Cmd {
  let payload : @sdk.CreateProjectRequest = { display_name, runtime_id }
  @shared.post_json(@sdk.projects_path(), payload, fn(result) {
    dispatch(ProjectCreated(result))
  })
}

///|
fn rename_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  display_name : String,
) -> @rabbita.Cmd {
  let payload : @sdk.UpdateProjectRequest = { display_name: Some(display_name) }
  @shared.put_json(@sdk.project_path(project_id), payload, fn(result) {
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
  @shared.post_json(@sdk.create_run_path(project_id), payload, fn(result) {
    dispatch(RunCreated(result))
  })
}

///|
fn cancel_run_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  run_id : String,
) -> @rabbita.Cmd {
  @shared.post_empty_json(@sdk.cancel_run_path(project_id, run_id), fn(result) {
    dispatch(RunCancelled(result))
  })
}

///|
fn delete_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  @shared.delete_empty(@sdk.project_path(project_id), fn(result) {
    dispatch(ProjectDeleted(project_id, result))
  })
}

///|
fn load_run_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  run_id : String,
) -> @rabbita.Cmd {
  @shared.get_json(@sdk.run_path(project_id, run_id), fn(result) {
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
  @shared.get_json(@sdk.run_events_path(project_id, run_id, after_seq), fn(
    result,
  ) {
    dispatch(RunEventsLoaded(project_id, result))
  })
}

///|
fn logout_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  @shared.post_empty(@sdk.logout_path(), fn(result) {
    dispatch(LoggedOut(result))
  })
}
