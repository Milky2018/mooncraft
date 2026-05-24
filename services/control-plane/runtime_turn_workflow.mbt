///|
priv struct ProjectRunWorkflow {
  root : String
  store : Store
  previews : PreviewManager
  runtime_gateway : RuntimeGateway
}

///|
fn ProjectRunWorkflow::from_context(ctx : AppContext) -> ProjectRunWorkflow {
  {
    root: ctx.root,
    store: ctx.store,
    previews: ctx.previews,
    runtime_gateway: ctx.runtime_gateway,
  }
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
  match self.store.set_project_preview(project_id, current_preview) {
    Some(_) => ignore(())
    None => {
      self.store.finish_run_failure(
        project_id,
        run_id,
        preview_audit_repair_failed_assistant_message(),
        "The preview target could not be persisted before preview audit.",
        current_thread_id,
      )
      return
    }
  }
  let mut audit = run_preview_audit(
    self.root,
    project_id,
    run_id,
    current_preview,
  )
  if !audit.enabled || audit.passed {
    self.store.finish_run_success(
      project_id, run_id, current_summary, current_thread_id, current_preview,
    )
    return
  }
  let mut audit_error = audit.message
  for _ in 0..<preview_audit_repair_attempts() {
    self.store.append_run_event(
      project_id,
      run_id,
      "status",
      @sdk.run_event_code_preview_repairing(),
      "Repairing browser preview errors.",
    )
    let repair_project = match self.store.get_project_detail(project_id) {
      Some(project) => project
      None => {
        self.store.finish_run_failure(
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
      preview_audit_repair_prompt(
        audit_error, initial_project_prompt, user_prompt,
      ),
      raw_prompt=true,
      resume_existing=false,
    )
    let repair = match repair_result {
      Ok(repair) => repair
      Err(failure) => {
        self.store.finish_run_failure_with_debug(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit failed: " +
          audit_error +
          "\n\nPreview audit repair failed: " +
          failure.error_message,
          failure.thread_id,
          failure.failure_debug,
        )
        return
      }
    }
    current_thread_id = repair.thread_id
    current_summary = successful_preview_assistant_message()
    let repair_restore_result = restore_workspace_snapshot(
      self.store,
      self.root,
      project_id,
      workspace_path,
    )
    match repair_restore_result {
      Ok(_) => ignore(())
      Err(restore_message) => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit repair completed, but the saved snapshot could not be restored into the local cache: " +
          restore_message,
          current_thread_id,
        )
        return
      }
    }
    match current_thread_id {
      Some(thread_id) =>
        self.store.save_project_runtime_session_id(project_id, thread_id)
      None => ignore(())
    }
    let repaired_project = match self.store.get_project_detail(project_id) {
      Some(project) => project
      None => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The repaired project workspace could not be loaded.",
          current_thread_id,
        )
        return
      }
    }
    let repaired_preview = match
      self.previews.rebuild_and_restart(repaired_project) {
      Ok(preview) => preview
      Err(message) => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "Preview audit repair completed, but the repaired preview could not be started: " +
          message,
          current_thread_id,
        )
        return
      }
    }
    current_preview = repaired_preview
    match self.store.set_project_preview(project_id, current_preview) {
      Some(_) => ignore(())
      None => {
        self.store.finish_run_failure(
          project_id,
          run_id,
          preview_audit_repair_failed_assistant_message(),
          "The repaired preview target could not be persisted before preview audit.",
          current_thread_id,
        )
        return
      }
    }
    audit = run_preview_audit(self.root, project_id, run_id, current_preview)
    if !audit.enabled || audit.passed {
      self.store.finish_run_success(
        project_id, run_id, current_summary, current_thread_id, current_preview,
      )
      return
    }
    audit_error = audit.message
  }
  self.store.finish_run_failure(
    project_id,
    run_id,
    preview_audit_repair_failed_assistant_message(),
    "Preview audit failed: " + audit_error,
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
      self.store.finish_run_failure(
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
      self.store.finish_run_failure(
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
      self.store.finish_run_failure(
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
      self.store.finish_run_failure(
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
    prompt,
  )
  match agent_result {
    Ok(result) => {
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        workspace_path,
      )
      match restore_cache_result {
        Ok(_) => ignore(())
        Err(message) => {
          self.store.finish_run_failure(
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
          self.store.finish_run_failure(
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
          ignore(
            self.store.set_project_runtime_session_id(project_id, thread_id),
          )
        None => ignore(())
      }
      let preview_result = self.previews.rebuild_and_restart(updated_project)
      match preview_result {
        Ok(preview) =>
          self.finish_run_with_preview_audit(
            project_id, run_id, workspace_path, initial_project_prompt, prompt, result,
            preview,
          )
        Err(message) =>
          if preview_error_needs_startup_repair(message) {
            self.store.append_run_event(
              project_id,
              run_id,
              "status",
              @sdk.run_event_code_preview_preparing(),
              "Preparing the live preview.",
            )
            let repair_project = match
              self.store.get_project_detail(project_id) {
              Some(project) => project
              None => {
                self.store.finish_run_failure(
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
              preview_setup_repair_prompt(),
              raw_prompt=true,
              resume_existing=false,
            )
            match repair_result {
              Ok(repair) => {
                let repair_restore_result = restore_workspace_snapshot(
                  self.store,
                  self.root,
                  project_id,
                  workspace_path,
                )
                match repair_restore_result {
                  Ok(_) => ignore(())
                  Err(restore_message) => {
                    self.store.finish_run_failure(
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
                    ignore(
                      self.store.set_project_runtime_session_id(
                        project_id, thread_id,
                      ),
                    )
                  None => ignore(())
                }
                let repaired_project = match
                  self.store.get_project_detail(project_id) {
                  Some(project) => project
                  None => {
                    self.store.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      "The repaired project workspace could not be loaded.",
                      repair.thread_id,
                    )
                    return
                  }
                }
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
                    self.store.finish_run_failure(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      message +
                      "\n\nPreview repair did not produce a usable preview: " +
                      repair_preview_message,
                      repair.thread_id,
                    )
                }
              }
              Err(failure) => {
                let repair_restore_result = restore_workspace_snapshot(
                  self.store,
                  self.root,
                  project_id,
                  workspace_path,
                )
                match repair_restore_result {
                  Ok(_) => ignore(())
                  Err(restore_message) =>
                    return self.store.finish_run_failure_with_debug(
                      project_id,
                      run_id,
                      preview_setup_repair_failed_assistant_message(),
                      message +
                      "\n\nPreview repair failed: " +
                      failure.error_message +
                      "\n\nWorkspace restore failed: " +
                      restore_message,
                      failure.thread_id,
                      failure.failure_debug,
                    )
                }
                self.store.finish_run_failure_with_debug(
                  project_id,
                  run_id,
                  preview_setup_repair_failed_assistant_message(),
                  message +
                  "\n\nPreview repair failed: " +
                  failure.error_message,
                  failure.thread_id,
                  failure.failure_debug,
                )
              }
            }
          } else {
            self.store.finish_run_failure(
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
      let restore_cache_result = restore_workspace_snapshot(
        self.store,
        self.root,
        project_id,
        workspace_path,
      )
      match restore_cache_result {
        Ok(_) => ignore(())
        Err(message) =>
          return self.store.finish_run_failure_with_debug(
            project_id,
            run_id,
            failure.assistant_message +
            "\n\nWorkspace status: the saved snapshot could not be restored into the local cache.",
            failure.error_message + "\n\nWorkspace restore failed: " + message,
            failure.thread_id,
            failure.failure_debug,
          )
      }
      self.store.finish_run_failure_with_debug(
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
