///|
struct TemplateEntrypoints {
  frontend_main : String
  backend_main : String?
  shared_model : String?
} derive(Debug, FromJson)

///|
struct TemplatePreviewArtifact {
  backend : String
  source_module : String?
  encoding : String?
  target_path : String
} derive(Debug, FromJson)

///|
struct TemplatePreviewConfig {
  kind : String?
  public_dir : String
  health_path : String?
  frontend_module : String
  frontend_backend : String?
  backend_module : String?
  frontend_package : String?
  backend_package : String?
  build_artifacts : Array[TemplatePreviewArtifact]?
} derive(Debug, FromJson)

///|
struct TemplateValidationConfig {
  build_workspace : String
  run_preview : String?
  run_backend : String?
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
  workspace_kind : String?
  workspace_dir : String
  entrypoints : TemplateEntrypoints
  preview : TemplatePreviewConfig
  validation : TemplateValidationConfig
  editable_files : Array[String]
  knowledge_doc : String
} derive(Debug, FromJson)

///|
fn default_template_id() -> String {
  "web-app-todolist"
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
fn template_workspace_kind(manifest : TemplateManifest) -> String {
  manifest.workspace_kind.unwrap_or("workspace")
}

///|
fn template_preview_kind(manifest : TemplateManifest) -> String {
  manifest.preview.kind.unwrap_or("backend")
}

///|
fn template_frontend_backend(manifest : TemplateManifest) -> String {
  manifest.preview.frontend_backend.unwrap_or("js")
}

///|
fn template_preview_health_path(manifest : TemplateManifest) -> String {
  match manifest.preview.health_path {
    Some(path) if path != "" => path
    _ =>
      if template_preview_kind(manifest) == "static" {
        "/__health"
      } else {
        "/api/health"
      }
  }
}

///|
fn template_build_output_extension(backend : String) -> String {
  match backend {
    "js" => ".js"
    "wasm" | "wasm-gc" => ".wasm"
    _ => ""
  }
}

///|
fn template_default_build_artifact(
  manifest : TemplateManifest,
) -> TemplatePreviewArtifact {
  let backend = template_frontend_backend(manifest)
  {
    backend,
    source_module: Some(manifest.preview.frontend_module),
    encoding: None,
    target_path: if backend == "js" {
      "app.js"
    } else {
      "app.wasm"
    },
  }
}

///|
fn template_preview_build_artifacts(
  manifest : TemplateManifest,
) -> Array[TemplatePreviewArtifact] {
  match manifest.preview.build_artifacts {
    Some(artifacts) if artifacts.length() > 0 => artifacts
    _ => [template_default_build_artifact(manifest)]
  }
}

///|
fn template_preview_artifact_source_module(
  manifest : TemplateManifest,
  artifact : TemplatePreviewArtifact,
) -> String {
  artifact.source_module.unwrap_or(manifest.preview.frontend_module)
}

///|
fn template_preview_artifact_encoding(
  artifact : TemplatePreviewArtifact,
) -> String {
  artifact.encoding.unwrap_or("identity")
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
  source_module : String,
  backend : String,
) -> String {
  let build_root = workspace_path +
    "/_build/" +
    backend +
    "/" +
    build_profile.build_dir() +
    "/build/"
  let basename = template_package_leaf(source_module) +
    template_build_output_extension(backend)
  let nested = build_root + source_module + "/" + basename
  if @fs.path_exists(nested) {
    nested
  } else {
    build_root + basename
  }
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
  match template_workspace_kind(manifest) {
    "workspace" => {
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
    }
    "module" => {
      if !(@fs.is_file(workspace_dir + "/moon.mod.json") catch { _ => false }) {
        return Err(
          "Template '\{manifest.id}' is missing its module manifest: moon.mod.json",
        )
      }
      if @fs.path_exists(workspace_dir + "/moon.work") {
        return Err(
          "Template '\{manifest.id}' is a single-module template and must not include moon.work.",
        )
      }
    }
    other =>
      return Err(
        "Template '\{manifest.id}' has unsupported workspace_kind '\{other}'.",
      )
  }
  let frontend_path = workspace_relative_path(
    workspace_dir,
    manifest.entrypoints.frontend_main,
  )
  if !(@fs.is_file(frontend_path) catch { _ => false }) {
    return Err(
      "Template '\{manifest.id}' is missing a required entrypoint: \{manifest.entrypoints.frontend_main}",
    )
  }
  match manifest.entrypoints.backend_main {
    Some(relative) => {
      let path = workspace_relative_path(workspace_dir, relative)
      if !(@fs.is_file(path) catch { _ => false }) {
        return Err(
          "Template '\{manifest.id}' is missing a required entrypoint: \{relative}",
        )
      }
    }
    None => ignore(())
  }
  match manifest.entrypoints.shared_model {
    Some(relative) => {
      let path = workspace_relative_path(workspace_dir, relative)
      if !(@fs.is_file(path) catch { _ => false }) {
        return Err(
          "Template '\{manifest.id}' is missing a required entrypoint: \{relative}",
        )
      }
    }
    None => ignore(())
  }
  match template_preview_kind(manifest) {
    "backend" =>
      match manifest.preview.backend_module {
        Some(module_name) if module_name != "" => ignore(())
        _ =>
          return Err(
            "Template '\{manifest.id}' uses backend preview mode but is missing preview.backend_module.",
          )
      }
    "static" => ignore(())
    other =>
      return Err(
        "Template '\{manifest.id}' has unsupported preview kind '\{other}'.",
      )
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
  let preview_build_artifacts = template_preview_build_artifacts(manifest)
  for artifact in preview_build_artifacts {
    if artifact.target_path == "" ||
      artifact.target_path.has_prefix("/") ||
      artifact.target_path.contains("..") {
      return Err(
        "Template '\{manifest.id}' has invalid preview build artifact target '\{artifact.target_path}'.",
      )
    }
    let backend = artifact.backend
    if template_build_output_extension(backend) == "" {
      return Err(
        "Template '\{manifest.id}' uses unsupported preview build backend '\{backend}'.",
      )
    }
    let encoding = template_preview_artifact_encoding(artifact)
    if encoding != "identity" && encoding != "base64" {
      return Err(
        "Template '\{manifest.id}' uses unsupported preview artifact encoding '\{encoding}'.",
      )
    }
    let module_name = template_preview_artifact_source_module(
      manifest, artifact,
    )
    if module_name == "" {
      return Err(
        "Template '\{manifest.id}' has a preview build artifact without a source module.",
      )
    }
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
async fn AppContext::materialize_project_template(
  self : AppContext,
  project : @sdk.ProjectDetail,
) -> Result[Unit, String] noraise {
  let manifest = match self.load_project_template(project) {
    Ok(manifest) => manifest
    Err(message) => return Err(message)
  }
  let workspace_path = project_workspace(self.root, project.id)
  ensure_dir(workspace_path)
  match
    copy_template_tree(
      template_workspace_dir(self.root, manifest),
      workspace_path,
      project,
      manifest,
    ) {
    Ok(_) => ignore(())
    Err(message) => return Err(message)
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
