///|
fn smoke_runtime_enabled() -> Bool {
  match @env.get_env_var("MOONCRAFT_RUNTIME_FAKE_MODE") {
    Some(value) => value.trim() == "smoke"
    None =>
      match @env.get_env_var("MOONCRAFT_CODEX_FAKE_MODE") {
        Some(value) => value.trim() == "smoke"
        None => false
      }
  }
}

///|
fn fake_runtime_fail_contains() -> String? {
  match @env.get_env_var("MOONCRAFT_RUNTIME_FAKE_FAIL_CONTAINS") {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ =>
      match @env.get_env_var("MOONCRAFT_CODEX_FAKE_FAIL_CONTAINS") {
        Some(value) if value.trim() != "" => Some(value.trim().to_owned())
        _ => None
      }
  }
}

///|
fn prompt_section_after(prompt : String, marker : String) -> String? {
  match prompt.find(marker) {
    Some(index) =>
      Some(
        prompt[index + marker.length():]
        .to_owned()
        .trim(chars="\n\r ")
        .to_owned(),
      )
    None => None
  }
}

///|
fn fake_runtime_user_request(prompt : String) -> String {
  let markers = [
    "Latest user request:\n\n", "Latest user request:\n", "User's requirement:\n\n",
    "User's requirement:\n", "Original project requirement:\n\n", "Original project requirement:\n",
  ]
  for marker in markers {
    match prompt_section_after(prompt, marker) {
      Some(request) if request != "" => return request
      _ => ()
    }
  }
  prompt
}

///|
fn fake_runtime_forced_failure(prompt : String) -> String? {
  match fake_runtime_fail_contains() {
    Some(needle) =>
      if fake_runtime_user_request(prompt).contains(needle) {
        Some("Local builder forced failure for preview audit coverage.")
      } else {
        None
      }
    _ => None
  }
}

///|
fn fake_runtime_state_dir(root : String, project_id : String) -> String {
  project_root(root, project_id) + "/fake-runtime"
}

///|
fn fake_runtime_resume_reset_marker(
  root : String,
  project_id : String,
) -> String {
  fake_runtime_state_dir(root, project_id) + "/resume-reset-once"
}

///|
fn fake_runtime_preview_html(root : String) -> String {
  web_public_string(
    root, "control-plane-assets/smoke-preview/index.html", "MoonCraft smoke preview",
  )
}

///|
fn fake_runtime_update_workspace(
  root : String,
  workspace_path : String,
  prompt : String,
) -> Result[String, String] {
  let normalized = trim_or_default(
    fake_runtime_user_request(prompt),
    "MoonCraft update",
  )
  let async_version = "0.18.1"
  let mocket_version = "0.7.1"
  let x_version = "0.4.43"
  let files : Array[(String, String)] = [
    (
      "/moon.mod.json",
      (
        #|{
        #|  "name": "mooncraft/smoke-app",
        #|  "version": "0.1.0",
        #|  "preferred-target": "native",
        #|  "deps": {
      ) +
      "    \"moonbitlang/async\": \"\{async_version}\",\n" +
      "    \"oboard/mocket\": \"\{mocket_version}\",\n" +
      "    \"moonbitlang/x\": \"\{x_version}\"\n" +
      (
        #|  },
        #|  "readme": "README.md",
        #|  "repository": "",
        #|  "license": "Apache-2.0",
        #|  "keywords": [],
        #|  "description": "MoonCraft smoke app"
        #|}
      ),
    ),
    (
      "/moon.pkg",
      (
        #|import {
        #|  "moonbitlang/async",
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
    ("/index.html", fake_runtime_preview_html(root)),
    (
      "/main.mbt",
      (
        #|///|
        #|fn app_page_html() -> String {
        #|  @fs.read_file_to_string("index.html") catch {
        #|    _ => "MoonCraft smoke preview"
        #|  }
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
    ),
    (
      "/mooncraft-preview.sh",
      (
        #|#!/bin/sh
        #|set -eu
        #|port="${1:-4300}"
        #|moon build
        #|exe="$(find ./_build -name '*.exe' -type f ! -path '*.dSYM/*' ! -path '*/cmd/*' | head -n 1)"
        #|exec "$exe" "$port"
      ),
    ),
    (
      "/main_wbtest.mbt",
      (
        #|///|
        #|test "page includes smoke title" {
        #|  assert_true(app_page_html().contains("MoonCraft smoke preview"))
        #|}
      ),
    ),
    ("/README.md", "# MoonCraft Smoke App\n\n" + normalized + "\n"),
  ]
  for file in files {
    match write_workspace_file(workspace_path + file.0, file.1) {
      Ok(_) => ignore(())
      Err(message) => return Err(message)
    }
  }
  Ok(successful_preview_assistant_message())
}

///|
fn fake_runtime_command_is_resume(command : Array[String]) -> Bool {
  for part in command {
    if part == "resume" {
      return true
    }
  }
  false
}

///|
fn collect_fake_runtime_output(
  root : String,
  project : @sdk.ProjectDetail,
  workspace_path : String,
  command : Array[String],
) -> Result[(Int, String, String?), String] {
  if command.length() < 2 {
    return Err("The local builder command was malformed.")
  }
  let is_resume = fake_runtime_command_is_resume(command)
  let prompt = command[command.length() - 1]
  ensure_dir(fake_runtime_state_dir(root, project.id))
  match fake_runtime_forced_failure(prompt) {
    Some(message) => return Ok((1, message, None))
    None => ignore(())
  }
  if is_resume {
    let runtime_session_id = command[command.length() - 2]
    let reset_marker = fake_runtime_resume_reset_marker(root, project.id)
    if !@fs.path_exists(reset_marker) {
      safe_write_string(reset_marker, "reset")
      return Ok(
        (
          1,
          "Error: runtime/resume: runtime/resume failed: no runtime session found for runtime session id \{runtime_session_id}",
          None,
        ),
      )
    }
    let summary = match
      fake_runtime_update_workspace(root, workspace_path, prompt) {
      Ok(summary) => summary
      Err(message) => return Err(message)
    }
    Ok((0, "{\"type\":\"turn.completed\"}", Some(summary)))
  } else {
    let runtime_session_id = next_id("fake-runtime-session")
    let summary = match
      fake_runtime_update_workspace(root, workspace_path, prompt) {
      Ok(summary) => summary
      Err(message) => return Err(message)
    }
    Ok(
      (
        0,
        "{\"type\":\"runtime.started\",\"runtime_session_id\":\"\{runtime_session_id}\"}\n{\"type\":\"turn.completed\"}",
        Some(summary),
      ),
    )
  }
}
