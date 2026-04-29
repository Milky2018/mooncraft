///|
fn generated_frontend_module() -> String {
  "moonbitcloud/generated/frontend"
}

///|
fn generated_backend_module() -> String {
  "moonbitcloud/generated/backend"
}

///|
fn generated_frontend_backend() -> String {
  "js"
}

///|
fn generated_preview_health_path() -> String {
  "/api/health"
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
fn workspace_relative_path(
  workspace_path : String,
  relative : String,
) -> String {
  workspace_path + "/" + relative
}

///|
fn generated_package_leaf(package_path : String) -> String {
  let parts = package_path.split("/").to_array()
  if parts.length() == 0 {
    package_path
  } else {
    parts[parts.length() - 1].to_string()
  }
}

///|
fn generated_build_output_extension(backend : String) -> String {
  match backend {
    "js" => ".js"
    "wasm" | "wasm-gc" => ".wasm"
    _ => ""
  }
}

///|
fn generated_build_output_path(
  workspace_path : String,
  build_profile : BuildProfile,
  source_module : String,
  backend : String,
) -> String {
  let build_root = workspace_path +
    "/_build/" +
    backend +
    "/" +
    build_profile.build_dir() +
    "/build/"
  let basename = generated_package_leaf(source_module) +
    generated_build_output_extension(backend)
  let nested = build_root + source_module + "/" + basename
  if @fs.path_exists(nested) {
    nested
  } else {
    build_root + basename
  }
}

///|
fn generated_native_executable_path(
  workspace_path : String,
  build_profile : BuildProfile,
  backend_module : String,
) -> String {
  workspace_path +
  "/_build/native/" +
  build_profile.build_dir() +
  "/build/" +
  backend_module +
  "/" +
  generated_package_leaf(backend_module) +
  ".exe"
}

///|
fn scaffold_write_file(path : String, content : String) -> Result[Unit, String] {
  let directory = parent_dir(path)
  if directory != "" {
    ensure_dir(directory)
  }
  @fs.write_string_to_file(path, content) catch {
    err =>
      return Err("Failed to write generated project file '\{path}': \{err}")
  }
  Ok(())
}

///|
fn generated_workspace_files() -> Array[(String, String)] {
  [
    (
      "moon.work",
      (
        #|members = [
        #|  "shared",
        #|  "frontend",
        #|  "backend",
        #|]
      ),
    ),
    (
      "README.md",
      (
        #|# MoonBit Cloud Generated App
        #|
        #|This workspace is owned by MoonBit Cloud and edited by the agent.
        #|
        #|- `frontend/` contains the browser entrypoint and static preview assets.
        #|- `backend/` contains the Mocket HTTP server used by the live preview.
        #|- `shared/` contains request/response types shared by frontend and backend.
        #|
        #|Keep the project runnable with `moon fmt`, `moon check`, `moon test`, and `moon build`.
      ),
    ),
    (
      "shared/moon.mod.json",
      (
        #|{
        #|  "name": "moonbitcloud/generated/shared",
        #|  "version": "0.1.0",
        #|  "preferred-target": "native",
        #|  "deps": {},
        #|  "readme": "README.md",
        #|  "repository": "",
        #|  "license": "Apache-2.0",
        #|  "keywords": ["moonbit", "moonbitcloud", "generated"],
        #|  "description": "Shared types for a MoonBit Cloud generated app."
        #|}
      ),
    ),
    (
      "shared/moon.pkg",
      (
        #|import {
        #|  "moonbitlang/core/json",
        #|}
        #|
        #|supported_targets = "js+native"
      ),
    ),
    (
      "shared/README.md",
      (
        #|# Shared
        #|
        #|Put request, response, and domain model types here.
      ),
    ),
    (
      "shared/model.mbt",
      (
        #|///|
        #|pub(all) struct AppInfo {
        #|  title : String
        #|  subtitle : String
        #|} derive(Debug, ToJson, FromJson)
        #|
        #|///|
        #|pub(all) struct HealthStatus {
        #|  ok : Bool
        #|  title : String
        #|  subtitle : String
        #|} derive(Debug, ToJson, FromJson)
        #|
        #|///|
        #|pub fn default_info() -> AppInfo {
        #|  {
        #|    title: "MoonBit Cloud App",
        #|    subtitle: "Describe what you want, then let the agent reshape this project.",
        #|  }
        #|}
      ),
    ),
    (
      "frontend/moon.mod.json",
      (
        #|{
        #|  "name": "moonbitcloud/generated/frontend",
        #|  "version": "0.1.0",
        #|  "preferred-target": "js",
        #|  "deps": {
        #|    "moonbitcloud/generated/shared": "0.1.0"
        #|  },
        #|  "readme": "README.md",
        #|  "repository": "",
        #|  "license": "Apache-2.0",
        #|  "keywords": ["moonbit", "moonbitcloud", "frontend"],
        #|  "description": "Frontend for a MoonBit Cloud generated app."
        #|}
      ),
    ),
    (
      "frontend/moon.pkg",
      (
        #|options(
        #|  "is-main": true,
        #|)
        #|
        #|supported_targets = "js"
      ),
    ),
    (
      "frontend/README.md",
      (
        #|# Frontend
        #|
        #|Build the browser UI here. The live preview serves `public/index.html`, `public/styles.css`, and the generated `app.js`.
      ),
    ),
    (
      "frontend/main.mbt",
      (
        #|///|
        #|fn main {
        #|  println("MoonBit Cloud preview loaded")
        #|}
      ),
    ),
    (
      "frontend/public/index.html",
      (
        #|<!doctype html>
        #|<html lang="en">
        #|  <head>
        #|    <meta charset="utf-8" />
        #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
        #|    <title>MoonBit Cloud Preview</title>
        #|    <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%23060b10'/%3E%3Cpath d='M14 18h14v28H14zm22 0h14v28H36z' fill='%2338efb7'/%3E%3C/svg%3E" />
        #|    <link rel="stylesheet" href="styles.css" />
        #|  </head>
        #|  <body>
        #|    <main class="preview-shell">
        #|      <section class="preview-card">
        #|        <p class="eyebrow">MoonBit Cloud</p>
        #|        <h1>Ready for your first prompt.</h1>
        #|        <p>Tell the agent what to build. This placeholder will become the generated app.</p>
        #|      </section>
        #|    </main>
        #|    <script type="module" src="app.js"></script>
        #|  </body>
        #|</html>
      ),
    ),
    (
      "frontend/public/styles.css",
      (
        #|:root {
        #|  color-scheme: light;
        #|  font-family: "Inter", "Helvetica Neue", sans-serif;
        #|  background:
        #|    radial-gradient(circle at top left, #eefdf4, transparent 32%),
        #|    radial-gradient(circle at bottom right, #edf4ff, transparent 36%),
        #|    #fbfcff;
        #|  color: #112033;
        #|}
        #|
        #|* {
        #|  box-sizing: border-box;
        #|}
        #|
        #|body {
        #|  margin: 0;
        #|  min-height: 100vh;
        #|}
        #|
        #|.preview-shell {
        #|  min-height: 100vh;
        #|  display: grid;
        #|  place-items: center;
        #|  padding: 32px;
        #|}
        #|
        #|.preview-card {
        #|  width: min(560px, 100%);
        #|  padding: 32px;
        #|  border-radius: 28px;
        #|  background: rgba(255, 255, 255, 0.9);
        #|  border: 1px solid rgba(17, 32, 51, 0.08);
        #|  box-shadow: 0 30px 80px rgba(24, 62, 92, 0.12);
        #|}
        #|
        #|.eyebrow {
        #|  margin: 0 0 12px;
        #|  color: #16845f;
        #|  font-size: 12px;
        #|  font-weight: 700;
        #|  letter-spacing: 0.12em;
        #|  text-transform: uppercase;
        #|}
        #|
        #|h1 {
        #|  margin: 0 0 12px;
        #|  font-size: 38px;
        #|  line-height: 1.05;
        #|}
        #|
        #|p {
        #|  margin: 0;
        #|  font-size: 16px;
        #|  line-height: 1.6;
        #|  color: #5e6d7d;
        #|}
      ),
    ),
    (
      "backend/moon.mod.json",
      (
        #|{
        #|  "name": "moonbitcloud/generated/backend",
        #|  "version": "0.1.0",
        #|  "preferred-target": "native",
        #|  "deps": {
        #|    "moonbitcloud/generated/shared": "0.1.0",
        #|    "oboard/mocket": "0.6.13",
        #|    "moonbitlang/x": "0.4.14"
        #|  },
        #|  "readme": "README.md",
        #|  "repository": "",
        #|  "license": "Apache-2.0",
        #|  "keywords": ["moonbit", "moonbitcloud", "backend"],
        #|  "description": "Backend for a MoonBit Cloud generated app."
        #|}
      ),
    ),
    (
      "backend/moon.pkg",
      (
        #|import {
        #|  "moonbitcloud/generated/shared" @shared,
        #|  "oboard/mocket",
        #|  "moonbitlang/core/env",
        #|  "moonbitlang/core/string",
        #|  "moonbitlang/x/fs",
        #|}
        #|
        #|options(
        #|  "is-main": true,
        #|)
        #|
        #|supported_targets = "native"
      ),
    ),
    (
      "backend/README.md",
      (
        #|# Backend
        #|
        #|Build Mocket HTTP APIs here. Keep `/api/health` available so MoonBit Cloud can verify the live preview.
      ),
    ),
    (
      "backend/main.mbt",
      (
        #|///|
        #|fn asset_response(
        #|  path : String,
        #|  content_type : String,
        #|) -> @mocket.HttpResponse {
        #|  @mocket.HttpResponse::new(
        #|    OK,
        #|    headers={ "Content-Type": content_type },
        #|    raw_body=@fs.read_file_to_bytes(path),
        #|  ) catch {
        #|    _ => @mocket.HttpResponse::new(NotFound).body("Not Found")
        #|  }
        #|}
        #|
        #|///|
        #|fn main {
        #|  let args = @env.args()
        #|  let port = if args.length() > 1 {
        #|    @string.parse_int(args[1]) catch {
        #|      _ => 4300
        #|    }
        #|  } else {
        #|    4300
        #|  }
        #|  let static_dir = if args.length() > 2 { args[2] } else { "./preview-dist" }
        #|  let info = @shared.default_info()
        #|  let app = @mocket.new()
        #|  app.get("/api/health", _ => @shared.HealthStatus::{
        #|    ok: true,
        #|    title: info.title,
        #|    subtitle: info.subtitle,
        #|  }.to_json())
        #|  app.get("/", _ => asset_response(static_dir + "/index.html", "text/html; charset=utf-8"))
        #|  app.get("/app.js", _ => asset_response(static_dir + "/app.js", "text/javascript; charset=utf-8"))
        #|  app.get("/styles.css", _ => asset_response(static_dir + "/styles.css", "text/css; charset=utf-8"))
        #|  app.serve(port=port)
        #|}
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
  for file in generated_workspace_files() {
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

///|
fn preview_fallback_index_html(root : String) -> String {
  control_plane_asset_string(root, "preview-fallback/index.html", "")
}

///|
fn preview_fallback_styles(root : String) -> String {
  control_plane_asset_string(root, "preview-fallback/styles.css", "")
}
