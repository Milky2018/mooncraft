///|
struct RuntimeServiceSpec {
  project_id : String
  image : String
  platform : String
  env : Map[String, String]
  container_name : String
  network_name : String
  publish_ports : Bool
}

///|
struct RuntimeServiceEndpoint {
  url : String
} derive(Debug)

///|
priv struct RuntimeServicePreview {
  preview : @sdk.PreviewTarget
  upstream_url : String
}

///|
fn runtime_service_network_name() -> String {
  match @env.get_env_var("MOONCRAFT_RUNTIME_DOCKER_NETWORK") {
    Some(value) if value.trim() != "" => value.trim().to_owned()
    _ => "mooncraft-runtime"
  }
}

///|
fn runtime_service_container_name(project_id : String) -> String {
  "mooncraft-runtime-\{project_id}"
}

///|
async fn runtime_service_should_publish_ports() -> Bool noraise {
  let in_docker = @async_fs.exists("/.dockerenv") catch { _ => false }
  !in_docker
}

///|
async fn RuntimeServiceSpec::from_settings(
  root : String,
  project_id : String,
  settings : RuntimeSettings,
) -> Result[RuntimeServiceSpec, String] noraise {
  let platform = match detect_docker_platform(root) {
    Ok(platform) => platform
    Err(message) => return Err(message)
  }
  Ok({
    project_id,
    image: settings.runtime_config.launcher.image,
    platform,
    env: settings.env,
    container_name: runtime_service_container_name(project_id),
    network_name: runtime_service_network_name(),
    publish_ports: runtime_service_should_publish_ports(),
  })
}

///|
fn runtime_service_env_file_content(spec : RuntimeServiceSpec) -> String {
  let content = StringBuilder()
  for key, value in spec.env {
    content <+ "\{docker_env_value(key)}=\{docker_env_value(value)}\n"
  }
  content.to_string()
}

///|
fn runtime_service_state_dir(root : String, project_id : String) -> String {
  "\{root}/data/runtime-services/\{project_id}"
}

///|
fn runtime_service_env_file_path(root : String, project_id : String) -> String {
  "\{runtime_service_state_dir(root, project_id)}/runtime.env"
}

///|
async fn write_runtime_service_env_file(
  root : String,
  spec : RuntimeServiceSpec,
) -> Result[String, String] noraise {
  let path = runtime_service_env_file_path(root, spec.project_id)
  ensure_dir(parent_dir(path)) catch {
    err => return Err("Runtime env directory could not be created: \{err}")
  }
  @async_fs.write_file(
    path,
    runtime_service_env_file_content(spec),
    create=0o644,
    truncate=true,
  ) catch {
    err => return Err("Runtime env file could not be written: \{err}")
  }
  Ok(path)
}

///|
async fn remove_runtime_service_env_file(path : String) -> Unit noraise {
  @async_fs.remove(path) catch {
    _ => ()
  }
}

///|
fn runtime_service_create_args(
  spec : RuntimeServiceSpec,
  env_file_path : String,
) -> Array[String] {
  let args : Array[String] = [
    "create",
    "--name",
    spec.container_name,
    "--platform",
    spec.platform,
    "--network",
    spec.network_name,
  ]
  if spec.publish_ports {
    args.push("-p")
    args.push("127.0.0.1::8080")
  }
  args.push("--env-file")
  args.push(env_file_path)
  args.push("--label")
  args.push("mooncraft.project_id=\{spec.project_id}")
  args.push("--label")
  args.push("mooncraft.runtime_service=1")
  args.push("--restart")
  args.push("unless-stopped")
  args.push(spec.image)
  args
}

///|
fn runtime_service_endpoint(container_name : String) -> RuntimeServiceEndpoint {
  { url: "http://\{container_name}:8080" }
}

///|
fn docker_port_output_port(output : String) -> String? {
  let lines = output.replace_all(old="\r\n", new="\n").split("\n").to_array()
  if lines.length() == 0 {
    return None
  }
  let line = lines[0].to_owned().trim().to_owned()
  let parts = line.split(":").to_array()
  if parts.length() < 2 {
    None
  } else {
    let port = parts[parts.length() - 1].to_owned().trim().to_owned()
    if port == "" {
      None
    } else {
      Some(port)
    }
  }
}

///|
async fn docker_container_host_port(
  container_name : String,
  container_port : Int,
) -> Result[String, String] noraise {
  match
    collect_process_text("docker", [
      "port",
      container_name,
      "\{container_port}/tcp",
    ]) {
    Ok((0, output)) =>
      match docker_port_output_port(output) {
        Some(port) => Ok(port)
        None =>
          Err("Runtime container did not publish port \{container_port}/tcp.")
      }
    Ok((_, output)) =>
      Err(
        "Runtime container port \{container_port}/tcp could not be inspected: \{tail_text(output, 800)}",
      )
    Err(message) => Err(message)
  }
}

///|
async fn resolved_runtime_service_endpoint(
  container_name : String,
) -> Result[RuntimeServiceEndpoint, String] noraise {
  if !runtime_service_should_publish_ports() {
    return Ok(runtime_service_endpoint(container_name))
  }
  let api_port = match docker_container_host_port(container_name, 8080) {
    Ok(port) => port
    Err(message) => return Err(message)
  }
  Ok({ url: "http://127.0.0.1:\{api_port}" })
}

///|
fn runtime_service_preview_target(
  project : @sdk.ProjectDetail,
) -> @sdk.PreviewTarget {
  { url: public_preview_url(project.preview_public_id), port: 0, healthy: true }
}

///|
async fn docker_command_ok(args : Array[String]) -> Bool noraise {
  run_process_quiet("docker", args) == 0
}

///|
async fn ensure_runtime_service_network(
  network_name : String,
) -> Result[Unit, String] noraise {
  if !docker_command_ok(["network", "inspect", network_name]) {
    if !docker_command_ok(["network", "create", network_name]) {
      return Err("Runtime Docker network could not be created: \{network_name}")
    }
  }
  if @env.get_env_var("HOSTNAME") is Some(hostname) {
    let container_id = hostname.trim().to_owned()
    let in_docker = @async_fs.exists("/.dockerenv") catch { _ => false }
    if container_id != "" && in_docker {
      ignore(
        run_process_quiet("docker", [
          "network", "connect", network_name, container_id,
        ]),
      )
    }
  }
  Ok(())
}

///|
async fn docker_container_running(container_name : String) -> Bool noraise {
  match
    collect_process_text("docker", [
      "inspect", "-f", "{{.State.Running}}", container_name,
    ]) {
    Ok((0, output)) => output.trim() == "true"
    _ => false
  }
}

///|
async fn runtime_service_health_ok(container_name : String) -> Bool noraise {
  let endpoint = match resolved_runtime_service_endpoint(container_name) {
    Ok(endpoint) => endpoint
    Err(_) => return false
  }
  let result = try @http.get("\{endpoint.url}/health") catch {
    _ => return false
  } noraise {
    value => value
  }
  let (response, _) = result
  response.code >= 200 && response.code < 300
}

///|
fn runtime_service_health_attempts() -> Int {
  env_uint64_or("MOONCRAFT_RUNTIME_HEALTH_ATTEMPTS", 40UL).to_int()
}

///|
fn runtime_service_health_interval_millis() -> Int {
  env_uint64_or("MOONCRAFT_RUNTIME_HEALTH_INTERVAL_MS", 500UL).to_int()
}

///|
async fn wait_runtime_service_health(
  container_name : String,
) -> Result[Unit, String] noraise {
  for _ in 0..<runtime_service_health_attempts() {
    if runtime_service_health_ok(container_name) {
      return Ok(())
    }
    @async.sleep(runtime_service_health_interval_millis()) catch {
      _ => return Err("Runtime Service health check was cancelled.")
    }
  }
  Err("Runtime Service did not become healthy at /health.")
}

///|
async fn create_runtime_service_container(
  root : String,
  spec : RuntimeServiceSpec,
) -> Result[Unit, String] noraise {
  let env_file_path = match write_runtime_service_env_file(root, spec) {
    Ok(path) => path
    Err(message) => return Err(message)
  }
  ignore(run_process_quiet("docker", ["rm", "-f", spec.container_name]))
  match
    collect_process_text(
      "docker",
      runtime_service_create_args(spec, env_file_path),
    ) {
    Ok((0, _)) => ()
    Ok((_, output)) => {
      remove_runtime_service_env_file(env_file_path)
      return Err(
        "Runtime container could not be created: \{tail_text(output, 800)}",
      )
    }
    Err(message) => {
      remove_runtime_service_env_file(env_file_path)
      return Err(message)
    }
  }
  let started = match
    collect_process_text("docker", ["start", spec.container_name]) {
    Ok((0, _)) => true
    Ok((_, output)) => {
      remove_runtime_service_env_file(env_file_path)
      return Err(
        "Runtime container could not be started: \{tail_text(output, 800)}",
      )
    }
    Err(message) => {
      remove_runtime_service_env_file(env_file_path)
      return Err(message)
    }
  }
  remove_runtime_service_env_file(env_file_path)
  if started {
    Ok(())
  } else {
    Err("Runtime container could not be started.")
  }
}

///|
async fn RuntimeGateway::ensure_project_runtime_service_with_idle_refresh(
  self : RuntimeGateway,
  store : Store,
  project_id : String,
  refresh_idle : Bool,
) -> Result[RuntimeServiceEndpoint, String] noraise {
  let project = match store.get_project_detail(project_id) {
    Some(project) => project
    None => return Err("Project not found.")
  }
  let existing = store.get_runtime_service_record(project_id)
  let ready_idle_expires_at = if refresh_idle {
    Some(runtime_service_idle_expires_at())
  } else {
    match existing {
      Some(record) => record.idle_expires_at
      None => None
    }
  }
  let settings = match store.lease_runtime_settings_for_project(project_id) {
    Ok(settings) => settings
    Err(message) => return Err(message)
  }
  let init_request = match
    runtime_service_init_request(
      project,
      settings.source_credential,
      settings.secrets,
    ) {
    Ok(request) => request
    Err(message) => return Err(message)
  }
  let spec = match
    RuntimeServiceSpec::from_settings(self.root, project_id, settings) {
    Ok(spec) => spec
    Err(message) => return Err(message)
  }
  if ensure_runtime_service_network(spec.network_name) is Err(message) {
    return Err(message)
  }
  match
    store.upsert_runtime_service_record(
      project_id,
      spec.container_name,
      spec.network_name,
      runtime_service_state_stopped(),
      None,
    ) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  if docker_container_running(spec.container_name) &&
    runtime_service_health_ok(spec.container_name) {
    let endpoint = match
      resolved_runtime_service_endpoint(spec.container_name) {
      Ok(endpoint) => endpoint
      Err(message) => return Err(message)
    }
    if runtime_service_post_init(endpoint, init_request) is Err(message) {
      return Err(message)
    }
    ignore(
      store.set_runtime_service_state(
        project_id,
        runtime_service_state_ready(),
        ready_idle_expires_at,
      ),
    )
    return Ok(endpoint)
  }
  if create_runtime_service_container(self.root, spec) is Err(message) {
    return Err(message)
  }
  if wait_runtime_service_health(spec.container_name) is Err(message) {
    ignore(run_process_quiet("docker", ["rm", "-f", spec.container_name]))
    ignore(
      store.set_runtime_service_state(
        project_id,
        runtime_service_state_stopped(),
        None,
      ),
    )
    return Err(message)
  }
  let endpoint = match resolved_runtime_service_endpoint(spec.container_name) {
    Ok(endpoint) => endpoint
    Err(message) => return Err(message)
  }
  if runtime_service_post_init(endpoint, init_request) is Err(message) {
    ignore(run_process_quiet("docker", ["rm", "-f", spec.container_name]))
    ignore(
      store.set_runtime_service_state(
        project_id,
        runtime_service_state_stopped(),
        None,
      ),
    )
    return Err(message)
  }
  match
    store.set_runtime_service_state(
      project_id,
      runtime_service_state_ready(),
      ready_idle_expires_at,
    ) {
    Ok(_) => Ok(endpoint)
    Err(message) => Err(message)
  }
}

///|
async fn RuntimeGateway::prepare_project_runtime_storage(
  self : RuntimeGateway,
  store : Store,
  project_id : String,
) -> Result[Unit, String] noraise {
  let settings = match store.lease_runtime_settings_for_project(project_id) {
    Ok(settings) => settings
    Err(message) => return Err(message)
  }
  let spec = match
    RuntimeServiceSpec::from_settings(self.root, project_id, settings) {
    Ok(spec) => spec
    Err(message) => return Err(message)
  }
  if ensure_runtime_service_network(spec.network_name) is Err(message) {
    return Err(message)
  }
  store.upsert_runtime_service_record(
    project_id,
    spec.container_name,
    spec.network_name,
    runtime_service_state_stopped(),
    None,
  )
}

///|
async fn RuntimeGateway::ensure_project_runtime_service(
  self : RuntimeGateway,
  store : Store,
  project_id : String,
) -> Result[RuntimeServiceEndpoint, String] noraise {
  self.ensure_project_runtime_service_with_idle_refresh(store, project_id, true)
}

///|
async fn RuntimeGateway::delete_project_runtime_storage(
  self : RuntimeGateway,
  store : Store,
  project_id : String,
) -> Result[Unit, String] noraise {
  let record = store.get_runtime_service_record(project_id)
  let container_name = match record {
    Some(record) => record.container_name
    None => runtime_service_container_name(project_id)
  }
  ignore(run_process_quiet("docker", ["rm", "-f", container_name]))
  fs_remove_tree(runtime_service_state_dir(self.root, project_id)) catch {
    err =>
      return Err("Runtime Service state directory could not be removed: \{err}")
  }
  Ok(())
}

///|
async fn RuntimeGateway::project_runtime_preview(
  self : RuntimeGateway,
  store : Store,
  project : @sdk.ProjectDetail,
) -> Result[RuntimeServicePreview, String] noraise {
  if smoke_runtime_enabled() {
    let preview = runtime_service_preview_target(project)
    ignore(store.set_project_preview(project.id, preview))
    return Ok({ preview, upstream_url: "" })
  }
  let previous = store.get_runtime_service_record(project.id)
  let endpoint = match
    self.ensure_project_runtime_service_with_idle_refresh(
      store,
      project.id,
      false,
    ) {
    Ok(endpoint) => endpoint
    Err(message) => return Err(message)
  }
  match runtime_service_get_preview(endpoint) {
    Ok(_) => {
      let preview = runtime_service_preview_target(project)
      ignore(
        store.set_runtime_service_state(
          project.id,
          runtime_service_state_ready(),
          Some(runtime_service_idle_expires_at()),
        ),
      )
      ignore(store.set_project_preview(project.id, preview))
      Ok({ preview, upstream_url: endpoint.url })
    }
    Err(message) => {
      match previous {
        Some(record) if record.idle_expires_at is Some(_) => ignore(())
        _ => {
          ignore(
            run_process_quiet("docker", [
              "rm",
              "-f",
              runtime_service_container_name(project.id),
            ]),
          )
          ignore(
            store.set_runtime_service_state(
              project.id,
              runtime_service_state_stopped(),
              None,
            ),
          )
        }
      }
      Err(message)
    }
  }
}

///|
async fn RuntimeGateway::stop_expired_idle_services(
  self : RuntimeGateway,
  store : Store,
) -> Int noraise {
  ignore(self)
  let records = store.list_expired_ready_runtime_services()
  let mut stopped = 0
  for record in records {
    if run_process_quiet("docker", ["rm", "-f", record.container_name]) == 0 {
      ignore(
        store.set_runtime_service_state(
          record.project_id,
          runtime_service_state_stopped(),
          None,
        ),
      )
      stopped = stopped + 1
    }
  }
  stopped
}

///|
async fn AppContext::run_runtime_service_ttl_loop(
  self : AppContext,
) -> Unit noraise {
  while true {
    ignore(self.runtime_gateway.stop_expired_idle_services(self.store))
    @async.sleep(60_000) catch {
      _ => return
    }
  }
}
