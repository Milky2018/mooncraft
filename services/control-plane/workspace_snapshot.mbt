///|
fn project_workspace_snapshot_path(
  root : String,
  project_id : String,
) -> String {
  project_root(root, project_id) + "/workspace.tar"
}

///|
fn project_workspace_snapshot_temp_path(
  root : String,
  project_id : String,
) -> String {
  project_root(root, project_id) + "/workspace.tar.tmp"
}

///|
fn shell_quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\"'\"'") + "'"
}

///|
fn snapshot_workspace(
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
  let snapshot_path = project_workspace_snapshot_path(root, project_id)
  let temp_path = project_workspace_snapshot_temp_path(root, project_id)
  ignore(shell_status("rm -f " + shell_quote(temp_path)))
  let archive_code = shell_status(
    "cd " +
    shell_quote(workspace_path) +
    " && tar --exclude='./_build' --exclude='./preview-dist' -cf " +
    shell_quote(temp_path) +
    " . >/dev/null 2>&1",
  )
  if archive_code != 0 {
    ignore(shell_status("rm -f " + shell_quote(temp_path)))
    return Err(
      "Saving the latest project snapshot failed for \{workspace_path}.",
    )
  }
  let move_code = shell_status(
    "mv " + shell_quote(temp_path) + " " + shell_quote(snapshot_path),
  )
  if move_code != 0 {
    ignore(shell_status("rm -f " + shell_quote(temp_path)))
    return Err(
      "The saved project snapshot could not be finalized at \{snapshot_path}.",
    )
  }
  Ok(())
}

///|
fn restore_workspace_snapshot(
  root : String,
  project_id : String,
  workspace_path : String,
) -> Result[Unit, String] {
  let snapshot_path = project_workspace_snapshot_path(root, project_id)
  if !@fs.path_exists(snapshot_path) {
    if @fs.path_exists(workspace_path) {
      return snapshot_workspace(root, project_id, workspace_path)
    }
    return Err(
      "No persisted workspace snapshot is available for project \{project_id}.",
    )
  }
  safe_remove_tree(workspace_path)
  ensure_dir(workspace_path)
  let restore_code = shell_status(
    "tar -xf " +
    shell_quote(snapshot_path) +
    " -C " +
    shell_quote(workspace_path) +
    " >/dev/null 2>&1",
  )
  if restore_code != 0 {
    return Err(
      "Restoring the saved workspace snapshot failed from \{snapshot_path}.",
    )
  }
  Ok(())
}
