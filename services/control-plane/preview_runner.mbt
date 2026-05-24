///|
priv struct PreviewRuntime {
  port : Int
}

///|
priv struct PreviewManager {
  root : String
  runtimes : Map[String, PreviewRuntime]
}

///|
fn preview_script_missing_message() -> String {
  "MoonCraft could not find `mooncraft-preview.sh` at the project root."
}

///|
fn preview_error_needs_startup_repair(message : String) -> Bool {
  message == preview_script_missing_message() ||
  message == "The preview process could not be started." ||
  message ==
  "The preview process started, but it did not become healthy in time."
}

///|
fn PreviewManager::new(root : String) -> PreviewManager {
  { root, runtimes: {} }
}

///|
fn PreviewManager::allocate_port(
  self : PreviewManager,
  project_id : String,
  preferred? : Int,
) -> Int {
  if preferred.unwrap_or(0) > 0 {
    return preferred.unwrap_or(0)
  }
  let mut hash = 0
  for byte in @utf8.encode(project_id) {
    hash = (hash * 33 + byte.to_int()) % 1000
  }
  let mut port = 4200 + hash
  while self.is_port_in_use(port, project_id) {
    port = port + 1
  }
  port
}

///|
fn PreviewManager::is_port_in_use(
  self : PreviewManager,
  port : Int,
  project_id : String,
) -> Bool {
  for id, runtime in self.runtimes {
    if id != project_id && runtime.port == port {
      return true
    }
  }
  false
}

///|
fn PreviewManager::stop_port(self : PreviewManager, port : Int) -> Unit {
  let _ = self
  ignore(
    shell_status("lsof -ti tcp:\{port} | xargs kill >/dev/null 2>&1 || true"),
  )
}

///|
fn PreviewManager::remove_project_runtime(
  self : PreviewManager,
  project_id : String,
  preview : @sdk.PreviewTarget?,
) -> Unit {
  match self.runtimes.get(project_id) {
    Some(runtime) => self.stop_port(runtime.port)
    None => ignore(())
  }
  match preview {
    Some(target) => self.stop_port(target.port)
    None => ignore(())
  }
  ignore(self.runtimes.remove(project_id))
}

///|
fn PreviewManager::is_healthy(
  self : PreviewManager,
  port : Int,
  health_path : String,
) -> Bool {
  let _ = self
  shell_status(
    "curl --silent --fail http://127.0.0.1:\{port}\{health_path} >/dev/null 2>&1",
  ) ==
  0
}

///|
fn PreviewManager::is_preview_reachable(
  self : PreviewManager,
  port : Int,
) -> Bool {
  self.is_healthy(port, preview_health_path()) || self.is_healthy(port, "/")
}

///|
fn PreviewManager::wait_until_preview_reachable(
  self : PreviewManager,
  port : Int,
  attempts : Int,
) -> Bool {
  for _ in 0..<attempts {
    if self.is_preview_reachable(port) {
      return true
    }
    ignore(shell_status("sleep 1"))
  }
  false
}

///|
fn preview_health_attempts() -> Int {
  match @env.get_env_var("MOONCRAFT_PREVIEW_HEALTH_ATTEMPTS") {
    Some(value) => {
      let attempts = @string.parse_int(value.trim().to_owned()) catch {
        _ => 60
      }
      if attempts > 0 {
        attempts
      } else {
        60
      }
    }
    None => 60
  }
}

///|
fn preview_script_relative_path() -> String {
  "./mooncraft-preview.sh"
}

///|
fn preview_script_log_path(project_id : String) -> String {
  "/tmp/mooncraft-preview-\{project_id}.log"
}

///|
fn PreviewManager::rebuild_and_restart(
  self : PreviewManager,
  project : @sdk.ProjectDetail,
) -> Result[@sdk.PreviewTarget, String] {
  let workspace_path = project_workspace(self.root, project.id)
  let script_probe_code = shell_status(
    "cd " +
    shell_quote(workspace_path) +
    " && test -f " +
    shell_quote(preview_script_relative_path()),
  )
  if script_probe_code != 0 {
    return Err(preview_script_missing_message())
  }
  let preferred_port = project.preview.map(fn(target) { target.port })
  let port = self.allocate_port(
    project.id,
    preferred=preferred_port.unwrap_or(0),
  )
  self.stop_port(port)
  let start_code = shell_status(
    "cd " +
    shell_quote(workspace_path) +
    " && chmod +x " +
    shell_quote(preview_script_relative_path()) +
    " && nohup " +
    shell_quote(preview_script_relative_path()) +
    " \{port} >" +
    shell_quote(preview_script_log_path(project.id)) +
    " 2>&1 &",
  )
  if start_code != 0 {
    return Err("The preview process could not be started.")
  }
  if !self.wait_until_preview_reachable(port, preview_health_attempts()) {
    return Err(
      "The preview process started, but it did not become healthy in time.",
    )
  }
  self.runtimes[project.id] = { port, }
  Ok({ url: public_preview_url(project.preview_public_id), port, healthy: true })
}
