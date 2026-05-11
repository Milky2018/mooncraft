///|
fn preview_health_path() -> String {
  "/api/health"
}

///|
fn user_project_reference_modules_path() -> String {
  @env.current_dir().unwrap_or(".") +
  "/config/user_project_reference_modules.txt"
}

///|
fn required_user_project_fetches() -> Array[String] {
  let content = @fs.read_file_to_string(user_project_reference_modules_path()) catch {
    err =>
      abort(
        "MoonCraft cannot read user-project reference modules from " +
        user_project_reference_modules_path() +
        ": \{err}",
      )
  }
  let modules : Array[String] = []
  for raw_line in content.split("\n") {
    let line = raw_line.trim().to_owned()
    if line != "" && !line.has_prefix("#") {
      modules.push(line)
    }
  }
  if modules.length() == 0 {
    abort(
      "MoonCraft requires at least one user-project reference module in " +
      user_project_reference_modules_path(),
    )
  }
  modules
}

///|
fn moon_fetch_no_update_command(module_name : String) -> String {
  "moon fetch --no-update " + shell_quote(module_name)
}

///|
fn moon_fetch_no_update_retry_command(module_name : String) -> String {
  "for attempt in 1 2 3 4 5; do " +
  moon_fetch_no_update_command(module_name) +
  " && break; " +
  "if [ \"$attempt\" = \"5\" ]; then exit 1; fi; " +
  "sleep $((attempt * 2)); " +
  "done"
}

///|
fn user_project_fetch_commands() -> Array[String] {
  let commands : Array[String] = []
  for module_name in required_user_project_fetches() {
    commands.push(moon_fetch_no_update_retry_command(module_name))
  }
  commands
}

///|
fn reference_module_version(module_name : String) -> String? {
  let prefix = module_name + "@"
  for fetch_spec in required_user_project_fetches() {
    match fetch_spec.strip_prefix(prefix) {
      Some(version) => return Some(version.to_owned())
      None => ignore(())
    }
  }
  None
}

///|
fn required_reference_module_version(module_name : String) -> String {
  match reference_module_version(module_name) {
    Some(version) => version
    None =>
      abort(
        "required user-project reference module is missing from config/user_project_reference_modules.txt: " +
        module_name,
      )
  }
}

///|
fn fetch_user_project_dependencies(
  workspace_path : String,
) -> Result[Unit, String] {
  for module_name in required_user_project_fetches() {
    let status = shell_status(
      "cd " +
      shell_quote(workspace_path) +
      " && " +
      moon_fetch_no_update_retry_command(module_name) +
      " >/dev/null 2>&1",
    )
    if status != 0 {
      return Err(
        "MoonBit dependency fetch failed for '\{module_name}', so the preview could not be rebuilt.",
      )
    }
  }
  Ok(())
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
fn moon_new_project_name() -> String {
  "generated_app"
}

///|
fn create_moon_new_project_workspace(
  root : String,
  project_id : String,
  workspace_path : String,
) -> Result[Unit, String] {
  let temp_dir = project_root(root, project_id) + "/.mooncraft-moon-new"
  let source_dir = temp_dir + "/source"
  safe_remove_tree(temp_dir)
  safe_remove_tree(workspace_path)
  ensure_dir(temp_dir)
  let status = shell_status(
    "cd " +
    shell_quote(temp_dir) +
    " && moon new --user mooncraft --name " +
    shell_quote(moon_new_project_name()) +
    " source >/dev/null 2>&1",
  )
  if status != 0 {
    safe_remove_tree(temp_dir)
    return Err(
      "MoonCraft could not initialize a new MoonBit project with `moon new`.",
    )
  }
  ensure_dir(workspace_path)
  let copy_status = shell_status(
    "cp -R " +
    shell_quote(source_dir + "/.") +
    " " +
    shell_quote(workspace_path + "/"),
  )
  safe_remove_tree(temp_dir)
  if copy_status != 0 {
    return Err(
      "MoonCraft could not copy the `moon new` workspace into the project directory.",
    )
  }
  safe_remove_tree(workspace_path + "/.git")
  safe_remove_tree(workspace_path + "/.github")
  safe_remove_tree(workspace_path + "/.githooks")
  Ok(())
}

///|
async fn AppContext::materialize_project_workspace(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[Unit, String] noraise {
  let workspace_path = project_workspace(self.root, project.id)
  match
    create_moon_new_project_workspace(self.root, project.id, workspace_path) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match snapshot_workspace(self.store, self.root, project.id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}
