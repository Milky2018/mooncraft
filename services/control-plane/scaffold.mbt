///|
fn preview_health_path() -> String {
  "/api/health"
}

///|
fn scaffold_write_file(path : String, content : String) -> Result[Unit, String] {
  ensure_dir(parent_dir(path))
  @fs.write_string_to_file(path, content) catch {
    err => return Err("Failed to write \{path}: \{err}")
  }
  Ok(())
}

///|
fn create_empty_project_workspace(
  workspace_path : String,
) -> Result[Unit, String] {
  safe_remove_tree(workspace_path)
  ensure_dir(workspace_path)
  Ok(())
}

///|
async fn AppContext::materialize_project_workspace(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[Unit, String] noraise {
  let workspace_path = project_workspace(self.root, project.id)
  match create_empty_project_workspace(workspace_path) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match snapshot_workspace(self.store, self.root, project.id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}
