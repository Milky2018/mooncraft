///|
fn project_workspace_snapshot_temp_path(
  root : String,
  project_id : String,
) -> String {
  project_root(root, project_id) + "/workspace.tar.tmp"
}

///|
async fn snapshot_workspace(
  store : Store,
  root : String,
  project_id : String,
  workspace_path : String,
) -> Result[Unit, String] noraise {
  if !@fs.path_exists(workspace_path) {
    return Err(
      "The workspace directory at \{workspace_path} was not found, so the latest project snapshot could not be saved.",
    )
  }
  let project_dir = project_root(root, project_id)
  ensure_dir(project_dir)
  let temp_path = project_workspace_snapshot_temp_path(root, project_id)
  @fs.remove_file(temp_path) catch {
    _ => ()
  }
  let archive_code = run_process_quiet(
    "tar",
    [
      "--exclude=./_build", "--exclude=./.mooncakes", "--exclude=./.repos", "--exclude=./preview-dist",
      "-cf", temp_path, "-C", workspace_path, ".",
    ],
    cwd=root,
  )
  if archive_code != 0 {
    @fs.remove_file(temp_path) catch {
      _ => ()
    }
    return Err(
      "Saving the latest project snapshot failed for \{workspace_path}.",
    )
  }
  let archive = safe_read_bytes_or(temp_path, b"")
  @fs.remove_file(temp_path) catch {
    _ => ()
  }
  if archive.is_empty() {
    return Err(
      "Saving the latest project snapshot produced an empty archive for \{workspace_path}.",
    )
  }
  store.save_workspace_snapshot(project_id, archive)
}

///|
async fn load_workspace_snapshot_archive(
  store : Store,
  project_id : String,
) -> Result[Bytes, String] noraise {
  match store.get_workspace_snapshot(project_id) {
    Some(archive) => Ok(archive)
    None =>
      Err(
        "No persisted workspace snapshot is available for project \{project_id}.",
      )
  }
}

///|
async fn restore_workspace_snapshot_to_path(
  store : Store,
  root : String,
  project_id : String,
  target_path : String,
) -> Result[Unit, String] noraise {
  let archive = match load_workspace_snapshot_archive(store, project_id) {
    Ok(archive) => archive
    Err(message) => return Err(message)
  }
  let project_dir = project_root(root, project_id)
  ensure_dir(project_dir)
  let temp_path = project_workspace_snapshot_temp_path(root, project_id)
  safe_write_bytes(temp_path, archive)
  safe_remove_tree(target_path)
  ensure_dir(target_path)
  let restore_code = run_process_quiet(
    "tar",
    ["-xf", temp_path, "-C", target_path],
    cwd=root,
  )
  @fs.remove_file(temp_path) catch {
    _ => ()
  }
  if restore_code != 0 {
    return Err(
      "Restoring the saved workspace snapshot failed for project \{project_id}.",
    )
  }
  Ok(())
}

///|
async fn restore_workspace_snapshot(
  store : Store,
  root : String,
  project_id : String,
  workspace_path : String,
) -> Result[Unit, String] noraise {
  restore_workspace_snapshot_to_path(store, root, project_id, workspace_path)
}

///|
async fn restore_project_workspace_for_run(
  store : Store,
  root : String,
  project_id : String,
) -> Result[String, String] noraise {
  let workspace_path = project_workspace(root, project_id)
  match
    restore_workspace_snapshot_to_path(store, root, project_id, workspace_path) {
    Ok(_) => Ok(workspace_path)
    Err(message) => Err(message)
  }
}
