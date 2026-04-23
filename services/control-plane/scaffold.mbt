///|
struct TemplateEntrypoints {
  frontend_main : String
  backend_main : String
  shared_model : String
} derive(Debug, FromJson)

///|
struct TemplatePreviewConfig {
  public_dir : String
  health_path : String
  frontend_module : String
  backend_module : String
  frontend_package : String
  backend_package : String
} derive(Debug, FromJson)

///|
struct TemplateValidationConfig {
  build_workspace : String
  run_backend : String
} derive(Debug, FromJson)

///|
struct TemplateManifest {
  id : String
  version : String
  name : String
  summary : String
  category : String
  app_shape : String
  storage : String
  tenant_requirement : String
  workspace_dir : String
  entrypoints : TemplateEntrypoints
  preview : TemplatePreviewConfig
  validation : TemplateValidationConfig
  editable_files : Array[String]
  knowledge_doc : String
} derive(Debug, FromJson)

///|
fn default_template_id() -> String {
  "bootstrap-app"
}

///|
fn default_template_version() -> String {
  "0.1.0"
}

///|
fn templates_root(root : String) -> String {
  root + "/templates"
}

///|
fn template_dir(root : String, template_id : String) -> String {
  templates_root(root) + "/" + template_id
}

///|
fn template_manifest_path(root : String, template_id : String) -> String {
  template_dir(root, template_id) + "/template.json"
}

///|
fn template_workspace_dir(root : String, manifest : TemplateManifest) -> String {
  template_dir(root, manifest.id) + "/" + manifest.workspace_dir
}

///|
fn repo_relative_path(root : String, relative : String) -> String {
  root + "/" + relative
}

///|
fn workspace_relative_path(
  workspace_path : String,
  relative : String,
) -> String {
  workspace_path + "/" + relative
}

///|
fn template_entrypoint_paths(manifest : TemplateManifest) -> Array[String] {
  [
    manifest.entrypoints.frontend_main,
    manifest.entrypoints.backend_main,
    manifest.entrypoints.shared_model,
  ]
}

///|
fn template_package_leaf(package_path : String) -> String {
  let parts = package_path.split("/").to_array()
  if parts.length() == 0 {
    package_path
  } else {
    parts[parts.length() - 1].to_string()
  }
}

///|
fn template_build_output_path(
  workspace_path : String,
  build_profile : BuildProfile,
  frontend_module : String,
) -> String {
  workspace_path +
  "/_build/js/" +
  build_profile.build_dir() +
  "/build/" +
  frontend_module +
  "/" +
  template_package_leaf(frontend_module) +
  ".js"
}

///|
fn template_native_executable_path(
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
  template_package_leaf(backend_module) +
  ".exe"
}

///|
fn validate_template_manifest(
  root : String,
  manifest : TemplateManifest,
) -> Result[Unit, String] {
  let workspace_dir = template_workspace_dir(root, manifest)
  if !(@fs.is_dir(workspace_dir) catch { _ => false }) {
    return Err(
      "Template '\{manifest.id}' is missing its workspace directory: \{workspace_dir}",
    )
  }
  if !(@fs.is_file(workspace_dir + "/moon.work") catch { _ => false }) {
    return Err(
      "Template '\{manifest.id}' is missing its workspace manifest: moon.work",
    )
  }
  if @fs.path_exists(workspace_dir + "/moon.mod.json") {
    return Err(
      "Template '\{manifest.id}' must use moon.work at the workspace root, not a root moon.mod.json.",
    )
  }
  for relative in template_entrypoint_paths(manifest) {
    let path = workspace_relative_path(workspace_dir, relative)
    if !(@fs.is_file(path) catch { _ => false }) {
      return Err(
        "Template '\{manifest.id}' is missing a required entrypoint: \{relative}",
      )
    }
  }
  let public_dir = workspace_relative_path(
    workspace_dir,
    manifest.preview.public_dir,
  )
  if !(@fs.is_dir(public_dir) catch { _ => false }) {
    return Err(
      "Template '\{manifest.id}' is missing its preview public directory: \{manifest.preview.public_dir}",
    )
  }
  let knowledge_doc = repo_relative_path(root, manifest.knowledge_doc)
  if !(@fs.is_file(knowledge_doc) catch { _ => false }) {
    return Err(
      "Template '\{manifest.id}' references a missing knowledge document: \{manifest.knowledge_doc}",
    )
  }
  Ok(())
}

///|
fn load_template_manifest(
  root : String,
  template_id : String,
) -> Result[TemplateManifest, String] {
  let path = template_manifest_path(root, template_id)
  if !@fs.path_exists(path) {
    return Err("Unknown template '\{template_id}'.")
  }
  let raw = @fs.read_file_to_string(path) catch {
    err => return Err("Failed to read template manifest '\{path}': \{err}")
  }
  let json = @json.parse(raw) catch {
    _ => return Err("Template manifest '\{path}' is not valid JSON.")
  }
  let manifest : TemplateManifest = @json.from_json(json) catch {
    _ =>
      return Err(
        "Template manifest '\{path}' does not match the expected shape.",
      )
  }
  match validate_template_manifest(root, manifest) {
    Ok(_) => Ok(manifest)
    Err(message) => Err(message)
  }
}

///|
fn is_binary_template_file(path : String) -> Bool {
  path.has_suffix(".png") ||
  path.has_suffix(".jpg") ||
  path.has_suffix(".jpeg") ||
  path.has_suffix(".gif") ||
  path.has_suffix(".webp") ||
  path.has_suffix(".ico") ||
  path.has_suffix(".woff") ||
  path.has_suffix(".woff2") ||
  path.has_suffix(".ttf") ||
  path.has_suffix(".otf")
}

///|
fn is_template_copy_ignored_entry(entry : String) -> Bool {
  entry == "_build" ||
  entry == ".mooncakes" ||
  entry == "preview-dist" ||
  entry == ".DS_Store"
}

///|
fn render_template_text(
  content : String,
  project : @sdk.ProjectDetail,
  manifest : TemplateManifest,
) -> String {
  content
  .replace_all(old="{{PROJECT_NAME}}", new=project.display_name)
  .replace_all(old="{{PROJECT_ID}}", new=project.id)
  .replace_all(old="{{TEMPLATE_ID}}", new=manifest.id)
  .replace_all(old="{{TEMPLATE_VERSION}}", new=manifest.version)
}

///|
fn copy_template_file(
  source : String,
  target : String,
  project : @sdk.ProjectDetail,
  manifest : TemplateManifest,
) -> Result[Unit, String] {
  if is_binary_template_file(source) {
    let content = @fs.read_file_to_bytes(source) catch {
      err => return Err("Failed to read template asset '\{source}': \{err}")
    }
    @fs.write_bytes_to_file(target, content) catch {
      err => return Err("Failed to write template asset '\{target}': \{err}")
    }
    return Ok(())
  }
  let content = @fs.read_file_to_string(source) catch {
    err => return Err("Failed to read template file '\{source}': \{err}")
  }
  @fs.write_string_to_file(
    target,
    render_template_text(content, project, manifest),
  ) catch {
    err => return Err("Failed to write template file '\{target}': \{err}")
  }
  Ok(())
}

///|
fn copy_template_tree(
  source_root : String,
  target_root : String,
  project : @sdk.ProjectDetail,
  manifest : TemplateManifest,
) -> Result[Unit, String] {
  ensure_dir(target_root)
  let entries = @fs.read_dir(source_root) catch {
    err =>
      return Err("Failed to read template directory '\{source_root}': \{err}")
  }
  for entry in entries {
    if entry == "." || entry == ".." {
      continue
    }
    if is_template_copy_ignored_entry(entry) {
      continue
    }
    let source = source_root + "/" + entry
    let target = target_root + "/" + entry
    if (@fs.is_dir(source) catch { _ => false }) {
      match copy_template_tree(source, target, project, manifest) {
        Ok(_) => ignore(())
        Err(message) => return Err(message)
      }
    } else {
      match copy_template_file(source, target, project, manifest) {
        Ok(_) => ignore(())
        Err(message) => return Err(message)
      }
    }
  }
  Ok(())
}

///|
fn AppContext::resolve_template(
  self : AppContext,
  template_id : String?,
) -> Result[TemplateManifest, String] {
  load_template_manifest(
    self.root,
    template_id.unwrap_or(default_template_id()),
  )
}

///|
fn AppContext::load_project_template(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[TemplateManifest, String] {
  load_template_manifest(self.root, project.template_id)
}

///|
fn AppContext::materialize_project_template(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[Unit, String] {
  let manifest = match self.load_project_template(project) {
    Ok(manifest) => manifest
    Err(message) => return Err(message)
  }
  let workspace_path = project.workspace_path
  ensure_dir(workspace_path)
  copy_template_tree(
    template_workspace_dir(self.root, manifest),
    workspace_path,
    project,
    manifest,
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
    #|  color: #5e6d7d;
    #|}
  )
}
