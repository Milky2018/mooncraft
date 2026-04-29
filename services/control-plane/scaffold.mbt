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
fn required_user_project_fetches() -> Array[String] {
  ["moonbitlang/async", "moonbitlang/x", "oboard/mocket"]
}

///|
fn optional_user_project_fetches() -> Array[String] {
  ["moonbit-community/isomorphic", "moonbit-community/selene"]
}

///|
fn user_project_fetch_commands() -> Array[String] {
  let commands : Array[String] = []
  for module_name in required_user_project_fetches() {
    commands.push("moon fetch --no-update " + module_name)
  }
  for module_name in optional_user_project_fetches() {
    commands.push(
      "moon fetch --no-update " +
      module_name +
      " || echo optional-moon-fetch-failed:" +
      module_name,
    )
  }
  commands
}

///|
fn fetch_user_project_dependencies(
  workspace_path : String,
) -> Result[Unit, String] {
  for module_name in required_user_project_fetches() {
    let status = shell_status(
      "cd " +
      shell_quote(workspace_path) +
      " && moon fetch " +
      shell_quote(module_name) +
      " >/dev/null 2>&1",
    )
    if status != 0 {
      return Err(
        "MoonBit dependency fetch failed for '\{module_name}', so the preview could not be rebuilt.",
      )
    }
  }
  for module_name in optional_user_project_fetches() {
    ignore(
      shell_status(
        "cd " +
        shell_quote(workspace_path) +
        " && moon fetch " +
        shell_quote(module_name) +
        " >/dev/null 2>&1",
      ),
    )
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
