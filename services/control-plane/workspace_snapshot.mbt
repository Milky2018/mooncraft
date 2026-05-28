///|
fn project_workspace_snapshot_temp_path(
  root : String,
  project_id : String,
) -> String {
  "\{project_workspace_snapshot_dir(root, project_id)}/workspace.tar.tmp"
}

///|
fn project_workspace_snapshot_dir(root : String, project_id : String) -> String {
  "\{project_root(root, project_id)}/snapshots"
}

///|
fn project_workspace_snapshot_archive_path(
  root : String,
  project_id : String,
) -> String {
  "\{project_workspace_snapshot_dir(root, project_id)}/workspace.tar"
}

///|
fn first_shell_field(value : String) -> String {
  let parts = value
    .replace_all(old="\t", new=" ")
    .replace_all(old="\n", new=" ")
    .replace_all(old="\r", new=" ")
    .trim()
    .split(" ")
    .to_array()
  for part in parts {
    let field = part.trim().to_owned()
    if field != "" {
      return field
    }
  }
  ""
}

///|
async fn file_size_bytes(path : String) -> Result[String, String] noraise {
  match collect_process_text("wc", ["-c", path]) {
    Ok((0, output)) => {
      let size = first_shell_field(output)
      if size == "" {
        Err("Could not determine the workspace snapshot size.")
      } else {
        Ok(size)
      }
    }
    Ok((code, output)) =>
      Err("Could not determine the workspace snapshot size: \{code} \{output}")
    Err(message) => Err(message)
  }
}

///|
async fn file_sha256(path : String) -> Result[String, String] noraise {
  if collect_process_text("sha256sum", [path]) is Ok((0, output)) {
    let checksum = first_shell_field(output)
    if checksum != "" {
      return Ok(checksum)
    }
  }
  match collect_process_text("shasum", ["-a", "256", path]) {
    Ok((0, output)) => {
      let checksum = first_shell_field(output)
      if checksum == "" {
        Err("Could not determine the workspace snapshot checksum.")
      } else {
        Ok(checksum)
      }
    }
    Ok((code, output)) =>
      Err(
        "Could not determine the workspace snapshot checksum: \{code} \{output}",
      )
    Err(message) => Err(message)
  }
}

///|
async fn snapshot_workspace(
  store : Store,
  root : String,
  project_id : String,
  workspace_path : String,
) -> Result[Unit, String] noraise {
  let workspace_exists = @async_fs.exists(workspace_path) catch {
    err => return Err("The workspace directory could not be checked: \{err}")
  }
  if !workspace_exists {
    return Err(
      "The workspace directory at \{workspace_path} was not found, so the latest project snapshot could not be saved.",
    )
  }
  let snapshot_dir = project_workspace_snapshot_dir(root, project_id)
  ensure_dir(snapshot_dir) catch {
    err =>
      return Err("Workspace snapshot directory could not be created: \{err}")
  }
  let temp_path = project_workspace_snapshot_temp_path(root, project_id)
  let archive_path = project_workspace_snapshot_archive_path(root, project_id)
  @async_fs.remove(temp_path) catch {
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
    @async_fs.remove(temp_path) catch {
      _ => ()
    }
    return Err(
      "Saving the latest project snapshot failed for \{workspace_path}.",
    )
  }
  let size_bytes = match file_size_bytes(temp_path) {
    Ok(size) => size
    Err(message) => {
      @async_fs.remove(temp_path) catch {
        _ => ()
      }
      return Err(message)
    }
  }
  let snapshot_size = @string.parse_uint64(size_bytes) catch { _ => 0UL }
  if snapshot_size == 0UL {
    @async_fs.remove(temp_path) catch {
      _ => ()
    }
    return Err(
      "Saving the latest project snapshot produced an empty archive for \{workspace_path}.",
    )
  }
  let checksum = match file_sha256(temp_path) {
    Ok(checksum) => checksum
    Err(message) => {
      @async_fs.remove(temp_path) catch {
        _ => ()
      }
      return Err(message)
    }
  }
  let move_code = run_process_quiet(
    "mv",
    ["-f", temp_path, archive_path],
    cwd=root,
  )
  if move_code != 0 {
    @async_fs.remove(temp_path) catch {
      _ => ()
    }
    return Err(
      "Saving the latest project snapshot could not move the archive into place for \{workspace_path}.",
    )
  }
  store.save_workspace_snapshot_metadata(
    project_id, archive_path, checksum, size_bytes,
  )
}

///|
async fn load_workspace_snapshot_metadata(
  store : Store,
  project_id : String,
) -> Result[WorkspaceSnapshotMetadata, String] noraise {
  match store.get_workspace_snapshot_metadata(project_id) {
    Some(snapshot) => Ok(snapshot)
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
  let snapshot = match load_workspace_snapshot_metadata(store, project_id) {
    Ok(snapshot) => snapshot
    Err(message) => return Err(message)
  }
  let snapshot_exists = @async_fs.exists(snapshot.path) catch {
    err =>
      return Err(
        "The persisted workspace snapshot could not be checked: \{err}",
      )
  }
  if !snapshot_exists {
    return Err(
      "The persisted workspace snapshot archive for project \{project_id} is missing.",
    )
  }
  let size_bytes = match file_size_bytes(snapshot.path) {
    Ok(size) => size
    Err(message) => return Err(message)
  }
  if size_bytes != snapshot.size_bytes {
    return Err(
      "The persisted workspace snapshot size does not match for project \{project_id}.",
    )
  }
  let checksum = match file_sha256(snapshot.path) {
    Ok(checksum) => checksum
    Err(message) => return Err(message)
  }
  if checksum != snapshot.checksum {
    return Err(
      "The persisted workspace snapshot checksum does not match for project \{project_id}.",
    )
  }
  fs_remove_tree(target_path) catch {
    err => return Err("Restored workspace path could not be reset: \{err}")
  }
  ensure_dir(target_path) catch {
    err => return Err("Restored workspace path could not be created: \{err}")
  }
  let restore_code = run_process_quiet(
    "tar",
    ["-xf", snapshot.path, "-C", target_path],
    cwd=root,
  )
  if restore_code != 0 {
    return Err(
      "Restoring the saved workspace snapshot failed for project \{project_id}.",
    )
  }
  Ok(())
}
