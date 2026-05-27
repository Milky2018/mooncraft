///|
priv struct ProjectRunWorkflow {
  root : String
  store : Store
  runtime_gateway : RuntimeGateway
  worker_id : String
  attempt : Int
}

///|
fn ProjectRunWorkflow::from_context(
  ctx : AppContext,
  worker_id : String,
  attempt : Int,
) -> ProjectRunWorkflow {
  {
    root: ctx.root,
    store: ctx.store,
    runtime_gateway: ctx.runtime_gateway,
    worker_id,
    attempt,
  }
}

///|
async fn ProjectRunWorkflow::append_status_event(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
  code : String,
  content : String,
) -> Unit {
  self.store.append_worker_run_event(
    project_id,
    run_id,
    self.worker_id,
    self.attempt,
    "status",
    code,
    content,
  )
}

///|
async fn ProjectRunWorkflow::finish_run_success(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
  summary : String,
  thread_id : String?,
  preview : @sdk.PreviewTarget,
) -> Unit {
  self.store.finish_run_success_for_worker(
    project_id,
    run_id,
    self.worker_id,
    self.attempt,
    summary,
    thread_id,
    preview,
  )
}

///|
async fn ProjectRunWorkflow::finish_run_failure(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
  assistant_message : String,
  error_message : String,
  thread_id : String?,
) -> Unit {
  self.store.finish_run_failure_for_worker(
    project_id,
    run_id,
    self.worker_id,
    self.attempt,
    assistant_message,
    error_message,
    thread_id,
    None,
  )
}

///|
async fn ProjectRunWorkflow::finish_run_failure_with_debug(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
  assistant_message : String,
  error_message : String,
  thread_id : String?,
  failure_debug : @sdk.RunFailureDebug?,
) -> Unit {
  self.store.finish_run_failure_for_worker(
    project_id,
    run_id,
    self.worker_id,
    self.attempt,
    assistant_message,
    error_message,
    thread_id,
    failure_debug,
  )
}

///|
async fn ProjectRunWorkflow::save_project_runtime_session_id(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
  thread_id : String,
) -> Unit {
  self.store.save_project_runtime_session_id_for_worker(
    project_id,
    run_id,
    self.worker_id,
    self.attempt,
    thread_id,
  )
}

///|
async fn ProjectRunWorkflow::run(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
) -> Unit {
  let project = match self.store.get_project_detail(project_id) {
    Some(project) => project
    None => {
      self.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        "The project for this run was not found.",
        None,
      )
      return
    }
  }
  let prompt = match self.store.get_run_prompt(project_id, run_id) {
    Some(prompt) => prompt
    None => {
      self.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        "The user message for this run was not found.",
        project.runtime_session_id,
      )
      return
    }
  }
  let initial_project_prompt = match
    self.store.get_initial_project_prompt(project_id) {
    Some(prompt) => prompt
    None => {
      self.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        "The initial project prompt was not persisted for this project.",
        project.runtime_session_id,
      )
      return
    }
  }
  let workspace_path = match
    restore_project_workspace_for_run(self.store, self.root, project_id) {
    Ok(path) => path
    Err(message) => {
      self.finish_run_failure(
        project_id,
        run_id,
        default_failure_assistant_message(),
        message,
        project.runtime_session_id,
      )
      return
    }
  }
  let agent_result = self.runtime_gateway.run_turn(
    self.store,
    project,
    initial_project_prompt,
    workspace_path,
    run_id,
    self.worker_id,
    self.attempt,
    prompt,
  )
  match agent_result {
    Ok(result) => {
      self.append_status_event(
        project_id,
        run_id,
        @sdk.run_event_code_workspace_restoring(),
        "Restoring the updated workspace.",
      )
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        workspace_path,
      )
      if restore_cache_result is Err(message) {
        self.finish_run_failure(
          project_id,
          run_id,
          result.summary +
          "\n\nWorkspace status: the saved snapshot could not be restored into the local cache.",
          message,
          result.thread_id,
        )
        return
      }
      let updated_project = match self.store.get_project_detail(project_id) {
        Some(project) => project
        None => {
          self.finish_run_failure(
            project_id,
            run_id,
            default_failure_assistant_message(),
            "The updated project workspace could not be loaded after the builder finished.",
            result.thread_id,
          )
          return
        }
      }
      if result.thread_id is Some(thread_id) {
        self.save_project_runtime_session_id(project_id, run_id, thread_id)
      }
      self.append_status_event(
        project_id,
        run_id,
        @sdk.run_event_code_preview_auditing(),
        "Checking the Runtime preview.",
      )
      match
        self.runtime_gateway.project_runtime_preview(
          self.store,
          updated_project,
        ) {
        Ok(runtime_preview) =>
          self.finish_run_success(
            project_id,
            run_id,
            result.summary,
            result.thread_id,
            runtime_preview.preview,
          )
        Err(message) =>
          self.finish_run_failure(
            project_id,
            run_id,
            preview_refresh_failed_assistant_message(),
            message,
            result.thread_id,
          )
      }
    }
    Err(failure) => {
      self.append_status_event(
        project_id,
        run_id,
        @sdk.run_event_code_workspace_restoring(),
        "Restoring the previous workspace.",
      )
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        workspace_path,
      )
      if restore_cache_result is Err(message) {
        return self.finish_run_failure_with_debug(
          project_id,
          run_id,
          "\{failure.assistant_message}\n\nWorkspace status: the saved snapshot could not be restored into the local cache.",
          "\{failure.error_message}\n\nWorkspace restore failed: \{message}",
          failure.thread_id,
          failure.failure_debug,
        )
      }
      self.finish_run_failure_with_debug(
        project_id,
        run_id,
        failure.assistant_message,
        failure.error_message,
        failure.thread_id,
        failure.failure_debug,
      )
    }
  }
}
