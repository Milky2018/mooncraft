///|
fn preview_health_path() -> String {
  "/api/health"
}

///|
fn preview_script_relative_path() -> String {
  "moonbitcloud-preview.sh"
}

///|
fn preview_script_path(workspace_path : String) -> String {
  workspace_path + "/" + preview_script_relative_path()
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
        "MoonBit Cloud cannot read user-project reference modules from " +
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
      "MoonBit Cloud requires at least one user-project reference module in " +
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
fn user_project_fetch_commands() -> Array[String] {
  let commands : Array[String] = []
  for module_name in required_user_project_fetches() {
    commands.push("moon fetch --no-update " + module_name)
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
      " && moon fetch --no-update " +
      shell_quote(module_name) +
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
  let directory = parent_dir(path)
  if directory != "" {
    ensure_dir(directory)
  }
  @fs.write_string_to_file(path, content) catch {
    err =>
      return Err("Failed to write project workspace file '\{path}': \{err}")
  }
  Ok(())
}

///|
fn empty_workspace_seed_files() -> Array[(String, String)] {
  [
    (
      ".moonbitcloud/bootstrap.md",
      (
        #|# MoonBit Cloud Workspace
        #|
        #|This directory intentionally starts without an app scaffold.
        #|
        #|The Codex agent should create the real MoonBit project with `moon new`, choose the project shape that fits the request, and keep root-level validation commands working.
        #|
        #|Preview contract:
        #|- Keep `moonbitcloud-preview.sh` at the workspace root.
        #|- The script receives `<port> <build-profile>` arguments.
        #|- The script must start the generated app server and keep running.
        #|- The app must serve `/api/health` successfully and serve the user-facing app at `/`.
      ),
    ),
    (
      ".gitignore",
      (
        #|_build/
        #|.mooncakes/
        #|.repos/
        #|preview-dist/
      ),
    ),
  ]
}

///|
async fn AppContext::materialize_project_workspace(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[Unit, String] noraise {
  let workspace_path = project_workspace(self.root, project.id)
  ensure_dir(workspace_path)
  for file in empty_workspace_seed_files() {
    match scaffold_write_file(workspace_path + "/" + file.0, file.1) {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
  }
  match snapshot_workspace(self.store, self.root, project.id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}
