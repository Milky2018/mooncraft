///|
fn preview_health_path() -> String {
  "/api/health"
}

///|
fn preview_script_relative_path() -> String {
  "mooncraft-preview.sh"
}

///|
fn preview_script_path(workspace_path : String) -> String {
  workspace_path + "/" + preview_script_relative_path()
}

///|
fn implementation_required_marker_relative_path() -> String {
  ".mooncraft/implementation-required"
}

///|
fn implementation_required_marker_path(workspace_path : String) -> String {
  workspace_path + "/" + implementation_required_marker_relative_path()
}

///|
fn moonbit_string_literal(value : String) -> String {
  "\"" +
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n") +
  "\""
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
fn scaffold_remove_file(path : String) -> Result[Unit, String] {
  let status = shell_status("rm -f " + shell_quote(path))
  if status == 0 {
    Ok(())
  } else {
    Err("Failed to remove project workspace file '\{path}'.")
  }
}

///|
fn scaffold_write_mocket_preview_app(
  workspace_path : String,
  title : String,
  subtitle : String,
  description : String,
  require_implementation~ : Bool,
) -> Result[Unit, String] {
  let async_version = required_reference_module_version("moonbitlang/async")
  let mocket_version = required_reference_module_version("oboard/mocket")
  let x_version = required_reference_module_version("moonbitlang/x")
  match
    scaffold_write_file(
      workspace_path + "/moon.mod.json",
      (
        #|{
        #|  "name": "mooncraft/generated-app",
        #|  "version": "0.1.0",
        #|  "preferred-target": "native",
        #|  "deps": {
      ) +
      "    \"moonbitlang/async\": \"" +
      async_version +
      "\",\n" +
      "    \"oboard/mocket\": \"" +
      mocket_version +
      "\",\n" +
      "    \"moonbitlang/x\": \"" +
      x_version +
      "\"\n" +
      (
        #|  },
        #|  "readme": "README.md",
        #|  "repository": "",
        #|  "license": "Apache-2.0",
        #|  "keywords": ["moonbit", "mooncraft", "generated"],
        #|  "description":
      ) +
      moonbit_string_literal(description) +
      "\n}\n",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    scaffold_write_file(
      workspace_path + "/moon.pkg",
      (
        #|import {
        #|  "moonbitlang/async",
        #|  "oboard/mocket",
        #|  "moonbitlang/core/env",
        #|  "moonbitlang/core/string",
        #|}
        #|
        #|options(
        #|  "is-main": true,
        #|)
        #|
        #|supported_targets = "native"
      ),
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    scaffold_write_file(
      workspace_path + "/main.mbt",
      (
        #|///|
        #|fn app_page_html() -> String {
        #|  let title =
      ) +
      moonbit_string_literal(title) +
      (
        #|
        #|  let subtitle =
      ) +
      moonbit_string_literal(subtitle) +
      (
        #|
        #|  "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>" + title + "</title><style>body{font-family:sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;background:#f6fbf8;color:#10231b}.card{max-width:720px;padding:40px;border-radius:28px;background:white;box-shadow:0 30px 90px #d7e4dc}p{color:#52645b;line-height:1.6}.marker{font-size:12px;text-transform:uppercase;letter-spacing:.16em;color:#2d7a58}</style></head><body><main class='card'><p class='marker'>Mooncraft app shell</p><h1>" + title + "</h1><p>" + subtitle + "</p></main></body></html>"
        #|}
        #|
        #|///|
        #|async fn main {
        #|  let args = @env.args()
        #|  let port = if args.length() > 1 {
        #|    @string.parse_int(args[1]) catch {
        #|      _ => 4300
        #|    }
        #|  } else {
        #|    4300
        #|  }
        #|  let app = @mocket.new()
        #|  app.get("/api/health", _ => @mocket.HttpResponse::new(OK, headers={ "Content-Type": "application/json" }).body("{\"ok\":true}"))
        #|  app.get("/", _ => @mocket.HttpResponse::new(OK, headers={ "Content-Type": "text/html; charset=utf-8" }).body(app_page_html()))
        #|  app.listen("0.0.0.0:\{port}")
        #|}
      ),
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    scaffold_write_file(
      workspace_path + "/main_wbtest.mbt",
      (
        #|///|
        #|test "page includes shell title" {
        #|  assert_true(app_page_html().contains("Mooncraft"))
        #|}
      ),
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    scaffold_write_file(
      workspace_path + "/" + preview_script_relative_path(),
      (
        #|#!/usr/bin/env bash
        #|set -euo pipefail
        #|port="${1:-4300}"
        #|profile="${2:-debug}"
        #|exe="$(find "_build/native/${profile}/build" -name '*.exe' -type f | head -n 1)"
        #|if [ -z "${exe}" ]; then
        #|  echo "No native MoonBit executable was found for profile ${profile}." >&2
        #|  exit 1
        #|fi
        #|exec "${exe}" "${port}"
      ),
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match
    scaffold_write_file(
      workspace_path + "/README.md",
      "# Mooncraft App\n\n" + subtitle + "\n",
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  if require_implementation {
    scaffold_write_file(
      implementation_required_marker_path(workspace_path),
      (
        #|This workspace contains Mooncraft's structural preview shell.
        #|
        #|Replace the placeholder app with the user's requested app, then delete this file before finishing.
      ),
    )
  } else {
    scaffold_remove_file(implementation_required_marker_path(workspace_path))
  }
}

///|
fn empty_workspace_seed_files() -> Array[(String, String)] {
  [
    (
      ".mooncraft/bootstrap.md",
      (
        #|# Mooncraft Workspace
        #|
        #|This directory starts with Mooncraft's minimal MoonBit preview shell.
        #|
        #|The Codex agent should replace the placeholder app with the user's requested app while keeping this workspace root as the runnable MoonBit project root.
        #|
        #|If `moon new` is used as a helper and creates a child directory, move or adapt the generated files so this workspace root remains the runnable project root.
        #|
        #|Preview contract:
        #|- Keep `mooncraft-preview.sh` at the workspace root.
        #|- The script receives `<port> <build-profile>` arguments.
        #|- The script must start the generated app server and keep running.
        #|- The app must serve `/api/health` successfully and serve the user-facing app at `/`.
        #|
        #|Completion contract:
        #|- Replace the placeholder app shell with the user's requested app.
        #|- Delete `.mooncraft/implementation-required` before finishing.
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
  match
    scaffold_write_mocket_preview_app(
      workspace_path,
      "Mooncraft App",
      "Describe what to build and Mooncraft will replace this shell.",
      "Mooncraft structural preview shell.",
      require_implementation=true,
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
  }
  match snapshot_workspace(self.store, self.root, project.id, workspace_path) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}
