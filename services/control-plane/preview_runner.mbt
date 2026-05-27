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
async fn PreviewManager::stop_port(
  self : PreviewManager,
  port : Int,
) -> Unit noraise {
  let result = match
    collect_process_text(
      "lsof",
      ["-tiTCP:\{port}", "-sTCP:LISTEN"],
      cwd=self.root,
    ) {
    Ok(result) => result
    Err(_) => return
  }
  let (exit_code, output) = result
  if exit_code != 0 {
    return
  }
  for raw_line in output.split("\n") {
    let line = raw_line.trim().to_owned()
    if line == "" {
      continue
    }
    let pid = @string.parse_int(line) catch { _ => continue }
    terminate_process_tree(pid)
  }
}

///|
async fn PreviewManager::remove_project_runtime(
  self : PreviewManager,
  project_id : String,
  preview : @sdk.PreviewTarget?,
) -> Unit noraise {
  if self.runtimes.get(project_id) is Some(runtime) {
    self.stop_port(runtime.port)
  }
  if preview is Some(target) {
    self.stop_port(target.port)
  }
  ignore(self.runtimes.remove(project_id))
}

///|
async fn PreviewManager::is_healthy(
  self : PreviewManager,
  port : Int,
  health_path : String,
) -> Bool noraise {
  let _ = self
  let target_url = "http://127.0.0.1:\{port}\{health_path}"
  let result = try
    @async.with_timeout_opt(1000, () => {
      let response = try @mocket.fetch(target_url, GET) catch {
        _ => return false
      } noraise {
        response => response
      }
      http_status_success(response.status_code)
    })
  catch {
    _ => None
  } noraise {
    value => value
  }
  match result {
    Some(ok) => ok
    None => false
  }
}

///|
async fn PreviewManager::is_preview_reachable(
  self : PreviewManager,
  port : Int,
) -> Bool noraise {
  self.is_healthy(port, preview_health_path()) || self.is_healthy(port, "/")
}

///|
async fn PreviewManager::wait_until_preview_reachable(
  self : PreviewManager,
  port : Int,
  attempts : Int,
) -> Bool noraise {
  for _ in 0..<attempts {
    if self.is_preview_reachable(port) {
      return true
    }
    @async.sleep(1000) catch {
      _ => ()
    }
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
async fn PreviewManager::rebuild_and_restart(
  self : PreviewManager,
  project : @sdk.ProjectDetail,
) -> Result[@sdk.PreviewTarget, String] noraise {
  let workspace_path = project_workspace(self.root, project.id)
  let preview_script = "\{workspace_path}/\{preview_script_relative_path()}"
  let preview_script_exists = @async_fs.exists(preview_script) catch {
    err => return Err("Preview script could not be checked: \{err}")
  }
  if !preview_script_exists {
    return Err(preview_script_missing_message())
  }
  let preferred_port = project.preview.map(fn(target) { target.port })
  let port = self.allocate_port(
    project.id,
    preferred=preferred_port.unwrap_or(0),
  )
  self.stop_port(port)
  let chmod_code = run_process_quiet(
    "chmod",
    ["+x", preview_script_relative_path()],
    cwd=workspace_path,
  )
  if chmod_code != 0 {
    return Err("The preview process could not be started.")
  }
  let log_path = preview_script_log_path(project.id)
  let stdout = try
    @process.redirect_to_file(log_path, create=0o644, truncate=true)
  catch {
    _ => return Err("The preview process could not be started.")
  } noraise {
    output => output
  }
  let stderr = try
    @process.redirect_to_file(log_path, append=true, create=0o644)
  catch {
    _ => return Err("The preview process could not be started.")
  } noraise {
    output => output
  }
  let _ = try
    @process.spawn_orphan(
      preview_script_relative_path(),
      [port.to_string()],
      stdout~,
      stderr~,
      cwd=workspace_path,
    )
  catch {
    _ => return Err("The preview process could not be started.")
  } noraise {
    pid => pid
  }
  if !self.wait_until_preview_reachable(port, preview_health_attempts()) {
    return Err(
      "The preview process started, but it did not become healthy in time.",
    )
  }
  self.runtimes[project.id] = { port, }
  Ok({ url: public_preview_url(project.preview_public_id), port, healthy: true })
}
