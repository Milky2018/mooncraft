///|
async fn write_workspace_file(
  path : String,
  content : String,
) -> Result[Unit, String] noraise {
  ensure_dir(parent_dir(path)) catch {
    err => return Err("Failed to create parent directory for \{path}: \{err}")
  }
  @async_fs.write_file(path, content, create=0o644, truncate=true) catch {
    err => return Err("Failed to write \{path}: \{err}")
  }
  Ok(())
}

///|
async fn create_empty_project_workspace(
  workspace_path : String,
) -> Result[Unit, String] noraise {
  fs_remove_tree(workspace_path) catch {
    err => return Err("Failed to reset workspace \{workspace_path}: \{err}")
  }
  ensure_dir(workspace_path) catch {
    err => return Err("Failed to create workspace \{workspace_path}: \{err}")
  }
  Ok(())
}

///|
async fn AppContext::materialize_project_workspace(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[Unit, String] noraise {
  let workspace_path = project_workspace(self.root, project.id)
  if create_empty_project_workspace(workspace_path) is Err(message) {
    return Err(message)
  }
  match snapshot_workspace(self.store, self.root, project.id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}
