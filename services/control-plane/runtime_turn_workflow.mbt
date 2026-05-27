///|
priv struct ProjectRunWorkflow {
  root : String
  store : Store
  previews : PreviewManager
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
    previews: ctx.previews,
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
async fn ProjectRunWorkflow::set_project_preview(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
  preview : @sdk.PreviewTarget,
) -> @sdk.ProjectDetail? {
  self.store.set_project_preview_for_worker(
    project_id,
    run_id,
    self.worker_id,
    self.attempt,
    preview,
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
async fn ProjectRunWorkflow::finish_run_with_preview_audit(
  self : ProjectRunWorkflow,
  project_id : String,
  run_id : String,
  workspace_path : String,
  initial_project_prompt : String,
  user_prompt : String,
  result : AgentTurnSuccess,
  preview : @sdk.PreviewTarget,
) -> Unit {
  let mut current_preview = preview
  let mut current_thread_id = result.thread_id
  let mut current_summary = result.summary
  self.append_status_event(
    project_id,
    run_id,
    @sdk.run_event_code_preview_publishing(),
    "Publishing the live preview.",
  )
  match self.set_project_preview(project_id, run_id, current_preview) {
    Some(_) => ignore(())
    None => {
      self.finish_run_failure(
        project_id,
        run_id,
        preview_audit_repair_failed_assistant_message(),
        "The preview target could not be persisted before preview audit.",
        current_thread_id,
      )
      return
    }
  }
  self.append_status_event(
    project_id,
    run_id,
    @sdk.run_event_code_preview_auditing(),
    "Checking the live preview.",
  )
  let mut audit = run_preview_audit(
    self.root,
    project_id,
    run_id,
    current_preview,
  )
  if !audit.enabled || audit.passed {
    self.finish_run_success(
      project_id, run_id, current_summary, current_thread_id, current_preview,
    )
    return
  }
  let mut audit_error = audit.message
  for _ in 0..<preview_audit_repair_attempts() {
    self.append_status_event(
      project_id,
      run_id,
      @sdk.run_event_code_preview_repairing(),
      "Repairing browser preview errors.",
    )
    let repair_project = match self.store.get_project_detail(project_id) {
      Some(project) => project
      None => {
        self.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The updated project workspace could not be loaded before preview audit repair.",
          current_thread_id,
        )
        return
      }
    }
    let repair_result = self.runtime_gateway.run_turn(
      self.store,
      repair_project,
      initial_project_prompt,
      workspace_path,
      run_id,
      self.worker_id,
      self.attempt,
      preview_audit_repair_prompt(
        audit_error, initial_project_prompt, user_prompt,
      ),
      raw_prompt=true,
      resume_existing=false,
    )
    let repair = match repair_result {
      Ok(repair) => repair
      Err(failure) => {
        self.finish_run_failure_with_debug(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit failed: \{audit_error}\n\nPreview audit repair failed: \{failure.error_message}",
          failure.thread_id,
          failure.failure_debug,
        )
        return
      }
    }
    current_thread_id = repair.thread_id
    current_summary = successful_preview_assistant_message()
    self.append_status_event(
      project_id,
      run_id,
      @sdk.run_event_code_workspace_restoring(),
      "Restoring the repaired workspace.",
    )
    let repair_restore_result = restore_workspace_snapshot(
      self.store,
      self.root,
      project_id,
      workspace_path,
    )
    match repair_restore_result {
      Ok(_) => ignore(())
      Err(restore_message) => {
        self.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit repair completed, but the saved snapshot could not be restored into the local cache: \{restore_message}",
          current_thread_id,
        )
        return
      }
    }
    match current_thread_id {
      Some(thread_id) =>
        self.save_project_runtime_session_id(project_id, run_id, thread_id)
      None => ignore(())
    }
    let repaired_project = match self.store.get_project_detail(project_id) {
      Some(project) => project
      None => {
        self.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The repaired project workspace could not be loaded.",
          current_thread_id,
        )
        return
      }
    }
    self.append_status_event(
      project_id,
      run_id,
      @sdk.run_event_code_preview_starting(),
      "Starting the repaired preview.",
    )
    let repaired_preview = match
      self.previews.rebuild_and_restart(repaired_project) {
      Ok(preview) => preview
      Err(message) => {
        self.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit repair completed, but the repaired preview could not be started: \{message}",
          current_thread_id,
        )
        return
      }
    }
    current_preview = repaired_preview
    self.append_status_event(
      project_id,
      run_id,
      @sdk.run_event_code_preview_publishing(),
      "Publishing the repaired preview.",
    )
    match self.set_project_preview(project_id, run_id, current_preview) {
      Some(_) => ignore(())
      None => {
        self.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The repaired preview target could not be persisted before preview audit.",
          current_thread_id,
        )
        return
      }
    }
    self.append_status_event(
      project_id,
      run_id,
      @sdk.run_event_code_preview_auditing(),
      "Checking the repaired live preview.",
    )
    audit = run_preview_audit(self.root, project_id, run_id, current_preview)
    if !audit.enabled || audit.passed {
      self.finish_run_success(
        project_id, run_id, current_summary, current_thread_id, current_preview,
      )
      return
    }
    audit_error = audit.message
  }
  self.finish_run_failure(
    project_id,
    run_id,
    preview_audit_repair_failed_assistant_message(),
    "Preview audit failed: \{audit_error}",
    current_thread_id,
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
      match restore_cache_result {
        Ok(_) => ignore(())
        Err(message) => {
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
      match result.thread_id {
        Some(thread_id) =>
          self.save_project_runtime_session_id(project_id, run_id, thread_id)
        None => ignore(())
      }
      self.append_status_event(
        project_id,
        run_id,
        @sdk.run_event_code_preview_starting(),
        "Starting the live preview.",
      )
      let preview_result = self.previews.rebuild_and_restart(updated_project)
      match preview_result {
        Ok(preview) =>
          self.finish_run_with_preview_audit(
            project_id, run_id, workspace_path, initial_project_prompt, prompt, result,
            preview,
          )
        Err(message) =>
          if preview_error_needs_startup_repair(message) {
            self.append_status_event(
              project_id,
              run_id,
              @sdk.run_event_code_preview_repairing(),
              "Repairing preview startup.",
            )
            let repair_project = match
              self.store.get_project_detail(project_id) {
              Some(project) => project
              None => {
                self.finish_run_failure(
                  project_id,
                  run_id,
                  preview_setup_repair_failed_assistant_message(),
                  "The updated project workspace could not be loaded before preview repair.",
                  result.thread_id,
                )
                return
              }
            }
            let repair_result = self.runtime_gateway.run_turn(
              self.store,
              repair_project,
              initial_project_prompt,
              workspace_path,
              run_id,
              self.worker_id,
              self.attempt,
              preview_setup_repair_prompt(),
              raw_prompt=true,
              resume_existing=false,
            )
            match repair_result {
              Ok(repair) => {
                self.append_status_event(
                  project_id,
                  run_id,
                  @sdk.run_event_code_workspace_restoring(),
                  "Restoring the repaired workspace.",
                )
                let repair_restore_result = restore_workspace_snapshot(
                  self.store,
                  self.root,
                  project_id,
                  workspace_path,
                )
                match repair_restore_result {
                  Ok(_) => ignore(())
                  Err(restore_message) => {
                    self.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      restore_message,
                      repair.thread_id,
                    )
                    return
                  }
                }
                match repair.thread_id {
                  Some(thread_id) =>
                    self.save_project_runtime_session_id(
                      project_id, run_id, thread_id,
                    )
                  None => ignore(())
                }
                let repaired_project = match
                  self.store.get_project_detail(project_id) {
                  Some(project) => project
                  None => {
                    self.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      "The repaired project workspace could not be loaded.",
                      repair.thread_id,
                    )
                    return
                  }
                }
                self.append_status_event(
                  project_id,
                  run_id,
                  @sdk.run_event_code_preview_starting(),
                  "Starting the repaired preview.",
                )
                match self.previews.rebuild_and_restart(repaired_project) {
                  Ok(preview) =>
                    self.finish_run_with_preview_audit(
                      project_id,
                      run_id,
                      workspace_path,
                      initial_project_prompt,
                      prompt,
                      {
                        summary: successful_preview_assistant_message(),
                        thread_id: repair.thread_id,
                      },
                      preview,
                    )
                  Err(repair_preview_message) =>
                    self.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      "\{message}\n\nPreview repair did not produce a usable preview: \{repair_preview_message}",
                      repair.thread_id,
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
                let repair_restore_result = restore_workspace_snapshot(
                  self.store,
                  self.root,
                  project_id,
                  workspace_path,
                )
                match repair_restore_result {
                  Ok(_) => ignore(())
                  Err(restore_message) =>
                    return self.finish_run_failure_with_debug(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      "\{message}\n\nPreview repair failed: \{failure.error_message}\n\nWorkspace restore failed: \{restore_message}",
                      failure.thread_id,
                      failure.failure_debug,
                    )
                }
                self.finish_run_failure_with_debug(
                  project_id,
                  run_id,
                  preview_setup_repair_failed_assistant_message(),
                  "\{message}\n\nPreview repair failed: \{failure.error_message}",
                  failure.thread_id,
                  failure.failure_debug,
                )
              }
            }
          } else {
            self.finish_run_failure(
              project_id,
              run_id,
              preview_refresh_failed_assistant_message(),
              message,
              result.thread_id,
            )
          }
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
      match restore_cache_result {
        Ok(_) => ignore(())
        Err(message) =>
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
