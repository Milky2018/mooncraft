///|
fn generated_project_module_json() -> String {
  (
    #|{
    #|  "name": "moonbitcloud/generated-app",
    #|  "version": "0.1.0",
    #|  "deps": {
    #|    "moonbit-community/rabbita": "0.12.1",
    #|    "oboard/mocket": "0.6.13",
    #|    "moonbitlang/x": "0.4.14"
    #|  },
    #|  "readme": "README.md",
    #|  "repository": "",
    #|  "license": "Apache-2.0",
    #|  "keywords": ["moonbit", "generated-app"],
    #|  "description": "Generated MoonBit Cloud project."
    #|}
  )
}

///|
fn generated_project_readme(project_name : String) -> String {
  "# \{project_name}\n\nThis workspace is managed by MoonBit Cloud.\n"
}

///|
fn generated_shared_moon_pkg() -> String {
  "import {\n  \"moonbitlang/core/json\",\n}\n\nsupported_targets = \"js+native\"\n"
}

///|
fn generated_shared_model() -> String {
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
  )
}

///|
fn generated_frontend_moon_pkg() -> String {
  (
    #|import {
    #|  "moonbitcloud/generated-app/shared" @shared,
    #|  "moonbit-community/rabbita",
    #|  "moonbit-community/rabbita/html" @html,
    #|}
    #|
    #|options(
    #|  "is-main": true,
    #|)
    #|
    #|supported_targets = "js"
  )
}

///|
fn generated_frontend_main() -> String {
  (
    #|///|
    #|struct Model {
    #|  info : @shared.AppInfo
    #|}
    #|
    #|///|
    #|enum Msg {}
    #|
    #|///|
    #|fn view(_dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
    #|  @html.div(
    #|    class="preview-shell",
    #|    [
    #|      @html.div(
    #|        class="preview-card",
    #|        [
    #|          @html.h1(class="preview-title", model.info.title),
    #|          @html.p(class="preview-copy", model.info.subtitle),
    #|          @html.p(
    #|            class="preview-copy muted",
    #|            "This scaffold is intentionally small. The agent will turn it into a real product after your first request.",
    #|          ),
    #|        ],
    #|      ),
    #|    ],
    #|  )
    #|}
    #|
    #|///|
    #|fn main {
    #|  let app = @rabbita.simple_cell(
    #|    model={ info: @shared.default_info() },
    #|    update=(_ : Msg, model) => model,
    #|    view=view,
    #|  )
    #|  @rabbita.new(app).mount("app")
    #|}
  )
}

///|
fn generated_backend_moon_pkg() -> String {
  (
    #|import {
    #|  "moonbitcloud/generated-app/shared" @shared,
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
  )
}

///|
fn generated_backend_main() -> String {
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
    #|  app.get("/app", _ => asset_response(static_dir + "/app.js", "text/javascript; charset=utf-8"))
    #|  app.get("/styles", _ => asset_response(static_dir + "/styles.css", "text/css; charset=utf-8"))
    #|  app.serve(port=port)
    #|}
  )
}

///|
fn generated_preview_index_html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8" />
    #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
    #|    <title>MoonBit Cloud Preview</title>
    #|    <script>
    #|      (() => {
    #|        const theme = new URLSearchParams(window.location.search).get("theme") === "light" ? "light" : "dark";
    #|        document.documentElement.dataset.theme = theme;
    #|        document.documentElement.style.colorScheme = theme;
    #|      })();
    #|    </script>
    #|    <link rel="stylesheet" href="/styles" />
    #|  </head>
    #|  <body>
    #|    <div id="app"></div>
    #|    <script type="module" src="/app"></script>
    #|  </body>
    #|</html>
  )
}

///|
fn generated_preview_styles() -> String {
  (
    #|:root {
    #|  color-scheme: dark;
    #|  font-family: "IBM Plex Sans", "Helvetica Neue", sans-serif;
    #|  --preview-bg: #101113;
    #|  --preview-card: #17181b;
    #|  --preview-border: rgba(255, 255, 255, 0.09);
    #|  --preview-text: #f4f4f5;
    #|  --preview-muted: #8c8e95;
    #|  --preview-shadow: 0 10px 24px rgba(0, 0, 0, 0.22);
    #|  background: var(--preview-bg);
    #|  color: var(--preview-text);
    #|}
    #|
    #|:root[data-theme="light"] {
    #|  color-scheme: light;
    #|  --preview-bg: #f7f9fc;
    #|  --preview-card: #ffffff;
    #|  --preview-border: rgba(25, 35, 48, 0.14);
    #|  --preview-text: #121821;
    #|  --preview-muted: #707b8a;
    #|  --preview-shadow: 0 10px 24px rgba(24, 36, 52, 0.10);
    #|}
    #|
    #|* {
    #|  box-sizing: border-box;
    #|}
    #|
    #|body {
    #|  margin: 0;
    #|  min-height: 100vh;
    #|  background: var(--preview-bg);
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
    #|  padding: 28px;
    #|  border-radius: 8px;
    #|  background: var(--preview-card);
    #|  border: 1px solid var(--preview-border);
    #|  box-shadow: var(--preview-shadow);
    #|}
    #|
    #|.preview-title {
    #|  margin: 0 0 12px;
    #|  font-size: 38px;
    #|  line-height: 1.05;
    #|}
    #|
    #|.preview-copy {
    #|  margin: 0;
    #|  font-size: 16px;
    #|  line-height: 1.6;
    #|}
    #|
    #|.preview-copy.muted {
    #|  margin-top: 14px;
    #|  color: var(--preview-muted);
    #|}
  )
}

///|
fn AppContext::create_project_workspace(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Unit {
  let _ = self
  let workspace_path = project.workspace_path
  ensure_dir(workspace_path)
  ensure_dir(workspace_path + "/frontend")
  ensure_dir(workspace_path + "/frontend/public")
  ensure_dir(workspace_path + "/backend")
  ensure_dir(workspace_path + "/shared")
  safe_write_string(
    workspace_path + "/moon.mod.json",
    generated_project_module_json(),
  )
  safe_write_string(
    workspace_path + "/README.md",
    generated_project_readme(project.display_name),
  )
  safe_write_string(
    workspace_path + "/shared/moon.pkg",
    generated_shared_moon_pkg(),
  )
  safe_write_string(
    workspace_path + "/shared/model.mbt",
    generated_shared_model(),
  )
  safe_write_string(
    workspace_path + "/frontend/moon.pkg",
    generated_frontend_moon_pkg(),
  )
  safe_write_string(
    workspace_path + "/frontend/main.mbt",
    generated_frontend_main(),
  )
  safe_write_string(
    workspace_path + "/frontend/public/index.html",
    generated_preview_index_html(),
  )
  safe_write_string(
    workspace_path + "/frontend/public/styles.css",
    generated_preview_styles(),
  )
  safe_write_string(
    workspace_path + "/backend/moon.pkg",
    generated_backend_moon_pkg(),
  )
  safe_write_string(
    workspace_path + "/backend/main.mbt",
    generated_backend_main(),
  )
}
