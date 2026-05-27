///|
struct RuntimeServiceSpec {
  project_id : String
  image : String
  platform : String
  env : Map[String, String]
  secrets : Array[ResolvedRuntimeSecret]
  container_name : String
  workspace_volume : String
  home_volume : String
  network_name : String
}

///|
struct RuntimeServiceEndpoint {
  url : String
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
fn runtime_service_workspace_volume(project_id : String) -> String {
  "mooncraft-workspace-\{project_id}"
}

///|
fn runtime_service_home_volume(project_id : String) -> String {
  "mooncraft-home-\{project_id}"
}

///|
async fn RuntimeServiceSpec::from_settings(
  root : String,
  project_id : String,
  settings : AiRuntimeSettings,
) -> Result[RuntimeServiceSpec, String] noraise {
  let platform = match detect_docker_platform(root) {
    Ok(platform) => platform
    Err(message) => return Err(message)
  }
  Ok({
    project_id,
    image: settings.runtime_spec.image,
    platform,
    env: settings.env,
    secrets: settings.secrets,
    container_name: runtime_service_container_name(project_id),
    workspace_volume: runtime_service_workspace_volume(project_id),
    home_volume: runtime_service_home_volume(project_id),
    network_name: runtime_service_network_name(),
  })
}

///|
fn runtime_service_env_file_content(spec : RuntimeServiceSpec) -> String {
  let content = StringBuilder()
  for key, value in spec.env {
    content <+ "\{docker_env_value(key)}=\{docker_env_value(value)}\n"
  }
  for secret in spec.secrets {
    if secret.env is Some(env) {
      content <+ "\{docker_env_value(env)}=\{docker_env_value(secret.value)}\n"
    }
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
fn runtime_service_secret_dir(root : String, project_id : String) -> String {
  "\{runtime_service_state_dir(root, project_id)}/file-secrets"
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
async fn materialize_runtime_service_file_secrets(
  root : String,
  spec : RuntimeServiceSpec,
) -> Result[String?, String] noraise {
  let secret_dir = runtime_service_secret_dir(root, spec.project_id)
  fs_remove_tree(secret_dir) catch {
    err => return Err("Runtime secret directory could not be reset: \{err}")
  }
  let mut wrote_file = false
  for secret in spec.secrets {
    if secret.file is Some(file) {
      let relative_path = match @sdk.validate_runtime_secret_file_path(file) {
        Ok(path) => path
        Err(message) => return Err(message)
      }
      let target = "\{secret_dir}/\{relative_path}"
      ensure_dir(parent_dir(target)) catch {
        err =>
          return Err("Runtime secret directory could not be created: \{err}")
      }
      @async_fs.write_file(target, secret.value, create=0o600, truncate=true) catch {
        err => return Err("Runtime secret file could not be written: \{err}")
      }
      wrote_file = true
    }
  }
  if wrote_file {
    Ok(Some(secret_dir))
  } else {
    Ok(None)
  }
}

///|
fn runtime_service_create_args(
  spec : RuntimeServiceSpec,
  env_file_path : String,
) -> Array[String] {
  [
    "create",
    "--name",
    spec.container_name,
    "--platform",
    spec.platform,
    "--network",
    spec.network_name,
    "--env-file",
    env_file_path,
    "--label",
    "mooncraft.project_id=\{spec.project_id}",
    "--label",
    "mooncraft.runtime_service=1",
    "--restart",
    "unless-stopped",
    "-v",
    "\{spec.workspace_volume}:\{agent_container_workspace_dir()}",
    "-v",
    "\{spec.home_volume}:\{agent_container_home_dir()}",
    spec.image,
  ]
}

///|
fn runtime_service_endpoint(container_name : String) -> RuntimeServiceEndpoint {
  { url: "http://\{container_name}:8080" }
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
async fn ensure_runtime_service_volumes(
  spec : RuntimeServiceSpec,
) -> Result[Unit, String] noraise {
  if !docker_command_ok(["volume", "create", spec.workspace_volume]) {
    return Err(
      "Runtime workspace volume could not be created: \{spec.workspace_volume}",
    )
  }
  if !docker_command_ok(["volume", "create", spec.home_volume]) {
    return Err("Runtime home volume could not be created: \{spec.home_volume}")
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
  let endpoint = runtime_service_endpoint(container_name)
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
  let secret_dir = match materialize_runtime_service_file_secrets(root, spec) {
    Ok(path) => path
    Err(message) => {
      remove_runtime_service_env_file(env_file_path)
      return Err(message)
    }
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
      ignore(
        fs_remove_tree(runtime_service_secret_dir(root, spec.project_id)) catch {
          _ => ()
        },
      )
      return Err(
        "Runtime container could not be created: \{tail_text(output, 800)}",
      )
    }
    Err(message) => {
      remove_runtime_service_env_file(env_file_path)
      ignore(
        fs_remove_tree(runtime_service_secret_dir(root, spec.project_id)) catch {
          _ => ()
        },
      )
      return Err(message)
    }
  }
  if secret_dir is Some(path) {
    match
      collect_process_text("docker", [
        "cp",
        "\{path}/.",
        "\{spec.container_name}:\{agent_container_home_dir()}/",
      ]) {
      Ok((0, _)) => ()
      Ok((_, output)) => {
        remove_runtime_service_env_file(env_file_path)
        ignore(
          fs_remove_tree(runtime_service_secret_dir(root, spec.project_id)) catch {
            _ => ()
          },
        )
        return Err(
          "Runtime file secrets could not be copied into the home volume: \{tail_text(output, 800)}",
        )
      }
      Err(message) => {
        remove_runtime_service_env_file(env_file_path)
        ignore(
          fs_remove_tree(runtime_service_secret_dir(root, spec.project_id)) catch {
            _ => ()
          },
        )
        return Err(message)
      }
    }
  }
  ignore(
    fs_remove_tree(runtime_service_secret_dir(root, spec.project_id)) catch {
      _ => ()
    },
  )
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
async fn RuntimeGateway::ensure_project_runtime_service(
  self : RuntimeGateway,
  store : Store,
  project_id : String,
) -> Result[RuntimeServiceEndpoint, String] noraise {
  let settings = match store.lease_ai_runtime_settings_for_project(project_id) {
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
  if ensure_runtime_service_volumes(spec) is Err(message) {
    return Err(message)
  }
  match
    store.upsert_runtime_service_record(
      project_id,
      spec.container_name,
      spec.workspace_volume,
      spec.home_volume,
      spec.network_name,
      runtime_service_state_stopped(),
      None,
    ) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  if docker_container_running(spec.container_name) &&
    runtime_service_health_ok(spec.container_name) {
    ignore(
      store.set_runtime_service_state(
        project_id,
        runtime_service_state_ready(),
        Some(runtime_service_idle_expires_at()),
      ),
    )
    return Ok(runtime_service_endpoint(spec.container_name))
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
  match
    store.set_runtime_service_state(
      project_id,
      runtime_service_state_ready(),
      Some(runtime_service_idle_expires_at()),
    ) {
    Ok(_) => Ok(runtime_service_endpoint(spec.container_name))
    Err(message) => Err(message)
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
