///|
fn project_workspace_snapshot_temp_path(
  root : String,
  project_id : String,
) -> String {
  project_root(root, project_id) + "/workspace.tar.tmp"
}

///|
fn project_run_workspaces_root(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/run-workspaces"
}

///|
fn project_run_workspace_path(
  root : String,
  project_id : String,
  run_id : String,
) -> String {
  project_run_workspaces_root(root, project_id) + "/" + run_id
}

///|
fn snapshot_workspace(
  store : Store,
  root : String,
  project_id : String,
  workspace_path : String,
) -> Result[Unit, String] {
  if !@fs.path_exists(workspace_path) {
    return Err(
      "The workspace directory at \{workspace_path} was not found, so the latest project snapshot could not be saved.",
    )
  }
  let project_dir = project_root(root, project_id)
  ensure_dir(project_dir)
  let temp_path = project_workspace_snapshot_temp_path(root, project_id)
  ignore(shell_status("rm -f " + shell_quote(temp_path)))
  let archive_code = shell_status(
    "cd " +
    shell_quote(workspace_path) +
    " && tar --exclude='./_build' --exclude='./.mooncakes' --exclude='./preview-dist' -cf " +
    shell_quote(temp_path) +
    " . >/dev/null 2>&1",
  )
  if archive_code != 0 {
    ignore(shell_status("rm -f " + shell_quote(temp_path)))
    return Err(
      "Saving the latest project snapshot failed for \{workspace_path}.",
    )
  }
  let archive = safe_read_bytes_or(temp_path, b"")
  ignore(shell_status("rm -f " + shell_quote(temp_path)))
  if archive.is_empty() {
    return Err(
      "Saving the latest project snapshot produced an empty archive for \{workspace_path}.",
    )
  }
  store.save_workspace_snapshot(project_id, archive)
}

///|
fn load_workspace_snapshot_archive(
  store : Store,
  project_id : String,
) -> Result[Bytes, String] {
  match store.get_workspace_snapshot(project_id) {
    Some(archive) => Ok(archive)
    None =>
      Err(
        "No persisted workspace snapshot is available for project \{project_id}.",
      )
  }
}

///|
fn restore_workspace_snapshot_to_path(
  store : Store,
  root : String,
  project_id : String,
  target_path : String,
) -> Result[Unit, String] {
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
  let restore_code = shell_status(
    "tar -xf " +
    shell_quote(temp_path) +
    " -C " +
    shell_quote(target_path) +
    " >/dev/null 2>&1",
  )
  ignore(shell_status("rm -f " + shell_quote(temp_path)))
  if restore_code != 0 {
    return Err(
      "Restoring the saved workspace snapshot failed for project \{project_id}.",
    )
  }
  Ok(())
}

///|
fn restore_workspace_snapshot(
  store : Store,
  root : String,
  project_id : String,
  workspace_path : String,
) -> Result[Unit, String] {
  restore_workspace_snapshot_to_path(store, root, project_id, workspace_path)
}

///|
fn hydrate_run_workspace(
  store : Store,
  root : String,
  project_id : String,
  run_id : String,
) -> Result[String, String] {
  let run_workspace_path = project_run_workspace_path(root, project_id, run_id)
  match
    restore_workspace_snapshot_to_path(
      store, root, project_id, run_workspace_path,
    ) {
    Ok(_) => Ok(run_workspace_path)
    Err(message) => Err(message)
  }
}

///|
fn remove_run_workspace(
  root : String,
  project_id : String,
  run_id : String,
) -> Unit {
  safe_remove_tree(project_run_workspace_path(root, project_id, run_id))
}
