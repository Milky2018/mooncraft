///|
fn project_workspace_snapshot_temp_path(
  root : String,
  project_id : String,
) -> String {
  project_workspace_snapshot_dir(root, project_id) + "/workspace.tar.tmp"
}

///|
fn project_workspace_snapshot_dir(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/snapshots"
}

///|
fn project_workspace_snapshot_archive_path(
  root : String,
  project_id : String,
) -> String {
  project_workspace_snapshot_dir(root, project_id) + "/workspace.tar"
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
  match collect_process_text("sha256sum", [path]) {
    Ok((0, output)) => {
      let checksum = first_shell_field(output)
      if checksum != "" {
        return Ok(checksum)
      }
    }
    _ => ignore(())
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
  if !@fs.path_exists(workspace_path) {
    return Err(
      "The workspace directory at \{workspace_path} was not found, so the latest project snapshot could not be saved.",
    )
  }
  let snapshot_dir = project_workspace_snapshot_dir(root, project_id)
  ensure_dir(snapshot_dir)
  let temp_path = project_workspace_snapshot_temp_path(root, project_id)
  let archive_path = project_workspace_snapshot_archive_path(root, project_id)
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
  let size_bytes = match file_size_bytes(temp_path) {
    Ok(size) => size
    Err(message) => {
      @fs.remove_file(temp_path) catch {
        _ => ()
      }
      return Err(message)
    }
  }
  let snapshot_size = @string.parse_uint64(size_bytes) catch { _ => 0UL }
  if snapshot_size == 0UL {
    @fs.remove_file(temp_path) catch {
      _ => ()
    }
    return Err(
      "Saving the latest project snapshot produced an empty archive for \{workspace_path}.",
    )
  }
  let checksum = match file_sha256(temp_path) {
    Ok(checksum) => checksum
    Err(message) => {
      @fs.remove_file(temp_path) catch {
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
    @fs.remove_file(temp_path) catch {
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
  if !@fs.path_exists(snapshot.path) {
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
  safe_remove_tree(target_path)
  ensure_dir(target_path)
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
