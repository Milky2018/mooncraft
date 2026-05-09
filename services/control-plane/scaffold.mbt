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
        "Mooncraft cannot read user-project reference modules from " +
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
      "Mooncraft requires at least one user-project reference module in " +
      user_project_reference_modules_path(),
    )
  }
  modules
}

///|
fn reference_modules_sentence() -> String {
  let modules = required_user_project_fetches()
  if modules.length() == 0 {
    "the configured reference modules"
  } else {
    modules.join(", ")
  }
}

///|
fn reference_modules_prompt_rule() -> String {
  "- The runtime has already fetched reference MoonBit packages with `moon fetch`; inspect `.repos` or `.mooncakes` when useful for examples from " +
  reference_modules_sentence() +
  "."
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
fn default_project_seed_dir() -> String {
  @env.current_dir().unwrap_or(".") + "/examples/project-seeds/native-mocket"
}

///|
fn configured_project_seed_dir() -> String {
  match @env.get_env_var("MOONCRAFT_PROJECT_SEED_DIR") {
    Some(value) if value.trim() != "" => trim_mount_path(value)
    _ => default_project_seed_dir()
  }
}

///|
fn required_project_seed_files() -> Array[String] {
  [
    ".gitignore", "README.md", "moon.mod.json", "moon.pkg", "main.mbt", "main_wbtest.mbt",
  ]
}

///|
fn project_seed_error(seed_dir : String) -> String? {
  if !@fs.path_exists(seed_dir) {
    return Some("Mooncraft project seed directory does not exist: \{seed_dir}")
  }
  for file in required_project_seed_files() {
    let path = seed_dir + "/" + file
    if !@fs.path_exists(path) {
      return Some("Mooncraft project seed is missing required file: \{path}")
    }
  }
  None
}

///|
fn copy_project_seed(
  seed_dir : String,
  workspace_path : String,
) -> Result[Unit, String] {
  match project_seed_error(seed_dir) {
    Some(message) => return Err(message)
    None => ignore(())
  }
  ensure_dir(workspace_path)
  let status = shell_status(
    "cp -R " +
    shell_quote(trim_mount_path(seed_dir) + "/.") +
    " " +
    shell_quote(trim_mount_path(workspace_path) + "/"),
  )
  if status == 0 {
    Ok(())
  } else {
    Err(
      "Failed to copy Mooncraft project seed from \{seed_dir} to \{workspace_path}.",
    )
  }
}

///|
async fn AppContext::materialize_project_workspace(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[Unit, String] noraise {
  let workspace_path = project_workspace(self.root, project.id)
  ensure_dir(workspace_path)
  match copy_project_seed(configured_project_seed_dir(), workspace_path) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match snapshot_workspace(self.store, self.root, project.id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}
