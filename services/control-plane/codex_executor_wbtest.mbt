///|
test "extract thread id from codex json event" {
  let events = "{\"type\":\"thread.started\",\"thread_id\":\"019db86f-4b45-75c3-a409-984993d1f897\"}\n{\"type\":\"turn.started\"}"
  debug_inspect(
    extract_thread_id(events),
    content="Some(\"019db86f-4b45-75c3-a409-984993d1f897\")",
  )
}

///|
test "stateless agent summary parser extracts streamed assistant text" {
  let output = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"thinking\",\"thinking\":\"hidden\"}]}}\n{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Preview is ready.\"}]}}\n{\"type\":\"result\",\"result\":\"\"}"
  debug_inspect(
    extract_agent_text_event(output),
    content="Some(\"Preview is ready.\")",
  )
}

///|
test "raw codex commands do not wrap compact repair prompts" {
  let repair = workspace_contract_repair_prompt(
    "missing root manifest", "Build a counter", "Make it previewable",
  )
  let exec_command = codex_exec_raw_command("openai/gpt-5.5", repair)
  inspect(exec_command[exec_command.length() - 1], content=repair)
  assert_false(exec_command.join(" ").contains("Working rules"))

  let resume_command = codex_resume_raw_command(
    "openai/gpt-5.5", "thread-1", repair,
  )
  inspect(resume_command[resume_command.length() - 1], content=repair)
  assert_false(resume_command.join(" ").contains("Continue building"))
}

///|
test "fake codex extracts only the user request from wrapped prompts" {
  let bootstrap = bootstrap_prompt("Build a todo app")
  inspect(fake_codex_user_request(bootstrap), content="Build a todo app")
  assert_false(fake_codex_user_request(bootstrap).contains("Working rules"))
  let followup = followup_prompt("Add labels and due dates")
  inspect(fake_codex_user_request(followup), content="Add labels and due dates")
  let recovery = recovery_prompt("Build a todo app", "Add labels and due dates")
  inspect(fake_codex_user_request(recovery), content="Add labels and due dates")
}

///|
test "success summary copy is shared across run completion paths" {
  inspect(
    default_success_summary(),
    content="The app is updated and the preview is ready.",
  )
  inspect(
    successful_preview_assistant_message(),
    content="The app is updated and the preview is ready.",
  )
}

///|
test "preview startup failures use user-safe copy" {
  inspect(
    preview_error_needs_startup_repair(preview_executable_missing_message()),
    content="true",
  )
  assert_true(
    preview_setup_repair_prompt().contains(
      "built native executable starts the server",
    ),
  )
  assert_true(
    preview_setup_repair_prompt().contains(
      "replace it with a native HTTP server",
    ),
  )
  assert_true(preview_setup_repair_prompt().contains("@env.args()"))
  assert_true(
    preview_setup_repair_prompt().contains("moon build --target native"),
  )
  assert_true(
    preview_setup_repair_prompt().contains("Do not send progress messages"),
  )
  assert_false(preview_setup_repair_prompt().contains("mooncraft-preview.sh"))
  assert_false(
    preview_refresh_failed_assistant_message().contains("mooncraft-preview.sh"),
  )
  assert_false(
    preview_setup_repair_failed_assistant_message().contains(
      "mooncraft-preview.sh",
    ),
  )
}

///|
test "preview executable discovery excludes debug symbols" {
  let command = preview_executable_find_command("_build/native/debug/build")
  assert_true(command.contains("-name '*.exe'"))
  assert_true(command.contains("! -path '*.dSYM/*'"))
}

///|
test "workspace contract requires root MoonBit project" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/control-plane-test-roots/" +
    next_id("workspace-contract")
  let workspace = root + "/workspace"
  safe_remove_tree(root)
  ensure_dir(workspace)

  let missing_project = workspace_contract_error(workspace)
  debug_inspect(
    missing_project.map(fn(message) {
      message.contains("MoonBit project at the workspace root")
    }),
    content="Some(true)",
  )

  safe_write_string(workspace + "/moon.mod.json", "{\"name\":\"test/app\"}\n")
  debug_inspect(
    workspace_contract_error(workspace).map(fn(message) {
      message.contains("did not create any MoonBit source files")
    }),
    content="Some(true)",
  )
  safe_write_string(workspace + "/main.mbt", "fn main { println(\"Hello\") }\n")
  debug_inspect(
    workspace_contract_error(workspace).map(fn(message) {
      message.contains("/api/health")
    }),
    content="Some(true)",
  )
  safe_write_string(
    workspace + "/main.mbt",
    "fn main { let _ = \"/api/health\" }\n",
  )
  debug_inspect(workspace_contract_error(workspace), content="None")
  safe_write_string(
    workspace + "/main.mbt",
    "fn main { let _ = \"/api/health MoonCraft Starter\" }\n",
  )
  debug_inspect(
    workspace_contract_error(workspace).map(fn(message) {
      message.contains("default MoonCraft starter page")
    }),
    content="Some(true)",
  )
  safe_write_string(
    workspace + "/main.mbt",
    "fn main { let _ = \"/api/health Snake\" }\n",
  )
  safe_write_string(
    workspace + "/main_wbtest.mbt",
    "test \"starter absent\" { assert_false(\"Snake\".contains(\"MoonCraft Starter\")) }\n",
  )
  debug_inspect(workspace_contract_error(workspace), content="None")
  safe_remove_tree(root)
}

///|
test "new project workspace seed is a valid native preview substrate" {
  let seed_dir = configured_project_seed_dir()
  debug_inspect(project_seed_error(seed_dir), content="None")
  for file in required_project_seed_files() {
    assert_true(@fs.path_exists(seed_dir + "/" + file))
  }
  let moon_mod = safe_read_string_or(seed_dir + "/moon.mod.json", "")
  let moon_pkg = safe_read_string_or(seed_dir + "/moon.pkg", "")
  let main = safe_read_string_or(seed_dir + "/main.mbt", "")
  assert_true(main.contains("/api/health"))
  assert_true(main.contains("MoonCraft Starter"))
  assert_true(moon_pkg.contains("supported_targets = \"native\""))
  assert_true(
    moon_mod.contains(
      "\"moonbitlang/async\": \"" +
      required_reference_module_version("moonbitlang/async") +
      "\"",
    ),
  )
  assert_true(
    moon_mod.contains(
      "\"moonbitlang/x\": \"" +
      required_reference_module_version("moonbitlang/x") +
      "\"",
    ),
  )
  assert_true(
    moon_mod.contains(
      "\"oboard/mocket\": \"" +
      required_reference_module_version("oboard/mocket") +
      "\"",
    ),
  )
}

///|
test "project workspace seed can be copied into a workspace" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/control-plane-test-roots/" +
    next_id("project-seed-copy")
  let workspace = root + "/workspace"
  safe_remove_tree(root)
  ensure_dir(workspace)
  match copy_project_seed(configured_project_seed_dir(), workspace) {
    Ok(_) => ignore(())
    Err(message) => abort(message)
  }
  for file in required_project_seed_files() {
    assert_true(@fs.path_exists(workspace + "/" + file))
  }
  assert_true(
    safe_read_string_or(workspace + "/main.mbt", "").contains("/api/health"),
  )
  safe_remove_tree(root)
}

///|
test "workspace contract repair prompt is self-contained" {
  let prompt = workspace_contract_repair_prompt(
    "The root MoonBit project is missing.", "Build a Snake game", "Make it browser-playable",
  )
  assert_true(prompt.contains("The root MoonBit project is missing."))
  assert_true(prompt.contains("Original project requirement"))
  assert_true(prompt.contains("Build a Snake game"))
  assert_true(prompt.contains("Latest user request"))
  assert_true(prompt.contains("Make it browser-playable"))
  assert_true(prompt.contains("You must edit files in this workspace"))
  assert_true(
    prompt.contains(
      "Do not read skills, examples, or dependency internals before editing the workspace.",
    ),
  )
  assert_true(prompt.contains("replace that starter page"))
  assert_true(prompt.contains("Do not send progress messages"))
  assert_true(prompt.contains("moon build --target native"))
  assert_false(prompt.contains("mooncraft-preview.sh"))
  assert_false(prompt.contains("implementation-required"))
}

///|
test "public run status hides failure diagnostics outside development mode" {
  let run : @sdk.RunStatusResponse = {
    run_id: "run-1",
    project_id: "project-1",
    state: Failed,
    summary: Some("The update failed before the preview could be refreshed."),
    error_message: Some("raw command output and private log paths"),
    failure_debug: Some({
      stage: "Codex session startup",
      command: Some("codex exec <prompt>"),
      exit_code: Some(125),
      codex_log_path: Some("/private/codex.log"),
      validation_log_path: Some("/private/validation.log"),
      final_summary_path: Some("/private/last_message.txt"),
    }),
    preview: None,
    started_at: "1",
    finished_at: Some("2"),
  }
  let public = public_run_status(run)
  debug_inspect(
    public.error_message,
    content="Some(\"The update failed before the preview could be refreshed.\")",
  )
  debug_inspect(public.failure_debug, content="None")
}

///|
test "admin bearer token parser accepts standard authorization header" {
  debug_inspect(
    bearer_token("Bearer operator-secret"),
    content="Some(\"operator-secret\")",
  )
  debug_inspect(bearer_token("operator-secret"), content="None")
  assert_true(admin_token_hash("operator-secret") != "operator-secret")
}

///|
test "OpenRouter model list parser keeps usable model metadata" {
  let models = openrouter_models_from_response(
    (
      #|{
      #|  "data": [
      #|    {
      #|      "id": "anthropic/claude-sonnet-4.5",
      #|      "name": "Claude Sonnet 4.5",
      #|      "context_length": 200000,
      #|      "pricing": {
      #|        "prompt": "0.000003",
      #|        "completion": "0.000015"
      #|      }
      #|    },
      #|    { "name": "missing id" }
      #|  ]
      #|}
    ),
  ).unwrap()
  inspect(models.length(), content="1")
  inspect(models[0].id, content="anthropic/claude-sonnet-4.5")
  inspect(models[0].name, content="Claude Sonnet 4.5")
  inspect(models[0].context_length, content="200000")
  inspect(models[0].prompt_price, content="0.000003")
  inspect(models[0].completion_price, content="0.000015")
}

///|
test "admin log reader returns structured file content" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/test-admin-logs/" +
    next_id("admin-log")
  let log_path = root + "/builder.log"
  safe_remove_tree(root)
  ensure_dir(root)
  safe_write_string(log_path, "builder output")
  let file = read_admin_log_file("builder", Some(log_path))
  inspect(file.label, content="builder")
  inspect(file.exists, content="true")
  inspect(file.truncated, content="false")
  debug_inspect(file.content, content="Some(\"builder output\")")
  debug_inspect(file.error, content="None")
  safe_remove_tree(root)
}

///|
test "admin log reader reports missing paths without failing" {
  let file = read_admin_log_file("validation", None)
  inspect(file.label, content="validation")
  inspect(file.exists, content="false")
  debug_inspect(file.content, content="None")
  debug_inspect(
    file.error,
    content="Some(\"No log path was recorded for this run.\")",
  )
}

///|
test "fake codex forced failure is disabled unless configured" {
  debug_inspect(fake_codex_forced_failure("Force fake failure"), content="None")
}

///|
test "resume session missing detection matches codex cli error" {
  inspect(
    resume_session_missing(
      "Error: thread/resume: thread/resume failed: no rollout found for thread id 00000000-0000-0000-0000-000000000000",
    ),
    content="true",
  )
}

///|
test "codex commands pin the configured model" {
  let exec_command = codex_exec_command("gpt-5.5", "Build a todo app")
  inspect(exec_command[2], content="--model")
  inspect(exec_command[3], content="gpt-5.5")
  let resume_command = codex_resume_command(
    "gpt-5.5", "local-thread", "Add labels",
  )
  assert_true(codex_command_is_resume(resume_command))
  inspect(resume_command[3], content="--model")
  inspect(resume_command[4], content="gpt-5.5")
}

///|
test "docker validation uses initialized image registry in one shell" {
  let script = validation_shell_script(include_update=false)
  assert_true(script.has_prefix("set -e"))
  assert_true(required_user_project_fetches().length() > 0)
  for module_name in required_user_project_fetches() {
    assert_true(script.contains(moon_fetch_no_update_command(module_name)))
  }
  assert_true(script.contains("for attempt in 1 2 3 4 5"))
  assert_true(script.contains("moon fmt"))
  assert_true(script.contains("moon check"))
  assert_true(script.contains("moon build"))
  assert_true(script.contains("moon test"))
}

///|
test "docker codex command fetches reference modules before codex starts" {
  let command = agent_runtime_entry_command(["codex", "exec", "Build an app"])
  inspect(command[0], content="sh")
  inspect(command[1], content="-c")
  assert_true(required_user_project_fetches().length() > 0)
  for module_name in required_user_project_fetches() {
    assert_true(command[2].contains(moon_fetch_no_update_command(module_name)))
  }
  assert_true(command[2].contains("for attempt in 1 2 3 4 5"))
  assert_true(command[2].contains("exec \"$@\""))
  inspect(command[3], content="mooncraft-agent")
  inspect(command[4], content="codex")
  inspect(command[5], content="exec")
}

///|
test "agent runtime doctor bypasses project fetch wrapper" {
  let command = agent_runtime_entry_command(agent_runtime_doctor_command())
  inspect(command[0], content="sh")
  inspect(command[1], content="-c")
  assert_true(
    command[2].contains(
      "if [ \"${1:-}\" = \"mooncraft-agent-doctor\" ]; then exec \"$@\"; fi",
    ),
  )
  match command[2].find("mooncraft-agent-doctor") {
    Some(doctor_index) =>
      match command[2].find("moon fetch --no-update") {
        Some(fetch_index) => assert_true(doctor_index < fetch_index)
        None => abort("expected runtime wrapper to contain moon fetch")
      }
    None => abort("expected runtime wrapper to contain doctor command")
  }
  inspect(command[4], content="mooncraft-agent-doctor")
}

///|
test "reference module versions come from the single config file" {
  let mocket_version = required_reference_module_version("oboard/mocket")
  let x_version = required_reference_module_version("moonbitlang/x")
  assert_true(mocket_version.length() > 0)
  assert_true(x_version.length() > 0)
  assert_true(
    required_user_project_fetches().contains("oboard/mocket@" + mocket_version),
  )
  assert_true(
    required_user_project_fetches().contains("moonbitlang/x@" + x_version),
  )
}

///|
test "mooncakes tls failures get a user friendly assistant message" {
  let output =
    #|Error: error sending request for url (https://download.mooncakes.io/user/oboard%2Fmocket%2Fpackage.zip)
    #|
    #|Caused by:
    #|    0: client error (Connect)
    #|    1: tls handshake eof
  assert_true(moonbit_registry_fetch_failed(output))
  assert_true(
    dependency_fetch_failure_assistant_message(output, "fallback").contains(
      "usually temporary",
    ),
  )
}

///|
test "github oauth helpers build pkce authorization url" {
  let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  let url = github_authorization_url(
    "client-id", "http://localhost:3000/auth/github/callback", "state value", verifier,
  )
  assert_true(url.has_prefix("https://github.com/login/oauth/authorize?"))
  assert_true(url.contains("response_type=code"))
  assert_true(url.contains("client_id=client-id"))
  assert_true(
    url.contains(
      "redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Fgithub%2Fcallback",
    ),
  )
  assert_true(url.contains("scope=read%3Auser%20user%3Aemail"))
  assert_true(url.contains("state=state%20value"))
  assert_true(
    url.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"),
  )
  assert_true(url.contains("code_challenge_method=S256"))
  assert_true(url.contains("prompt=select_account"))
}

///|
test "github oauth helpers build token request and parse access token" {
  let body = github_token_request_body(
    "client-id", "client secret", "code value", "http://localhost:3000/auth/github/callback",
    "verifier value",
  )
  assert_true(body.contains("grant_type=authorization_code"))
  assert_true(body.contains("client_id=client-id"))
  assert_true(body.contains("client_secret=client%20secret"))
  assert_true(body.contains("code=code%20value"))
  assert_true(
    body.contains(
      "redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Fgithub%2Fcallback",
    ),
  )
  assert_true(body.contains("code_verifier=verifier%20value"))
  inspect(
    github_access_token_from_response(
      "{\"access_token\":\"token-123\",\"token_type\":\"bearer\"}",
    ),
    content="Ok(\"token-123\")",
  )
  assert_true(github_access_token_from_response("{}") is Err(_))
}

///|
test "github oauth status handling accepts custom 200" {
  assert_true(http_status_success(Custom(200)))
  assert_false(http_status_success(Custom(400)))
}

///|
test "github user profile parser accepts large ids" {
  let profile = github_user_profile_from_response(
    (
      #|{"id":1234567890123,"login":"octo","email":null,"name":null}
    ),
  )
  inspect(
    match profile {
      Ok(profile) => "\{profile.id}:\{profile.login}"
      Err(message) => message
    },
    content="1234567890123:octo",
  )
}

///|
test "github user profile parser accepts optional strings" {
  inspect(
    match
      github_user_profile_from_response(
        (
          #|{"id":123,"login":"octo","email":"octo@example.com","name":"Octo"}
        ),
      ) {
      Ok(profile) => "\{profile.id}:\{profile.login}"
      Err(message) => message
    },
    content="123:octo",
  )
}

///|
test "docker command receives leased platform AI settings" {
  let config : AgentRuntimeConfig = {
    image: "codex:test",
    platform: "linux/amd64",
    agent_cli: "codex",
    provider: "openrouter",
    model: "anthropic/claude-sonnet-4.5",
    api_key: "leased-key",
    container_home: "/root",
    container_data_dir: "/app/data",
    host_data_dir: Some("/srv/mooncraft/test/data"),
  }
  let artifacts : RunArtifacts = {
    project_id: "project-1",
    run_id: "run-1",
    dir: "/app/data/runtime/projects/project-1/artifacts/runs/run-1",
    last_message_path: "/app/data/runtime/projects/project-1/artifacts/runs/run-1/last_message.txt",
    agent_log_path: "/app/data/runtime/projects/project-1/artifacts/runs/run-1/agent.log",
    validation_log_path: "/app/data/runtime/projects/project-1/artifacts/runs/run-1/validation.log",
  }
  let args = docker_command_args(
    config,
    "/app/data/runtime/projects/project-1/artifacts/runs/run-1/agent.env",
    "/app/data/runtime/projects/project-1/workspace",
    Some("/app/data/agent-sessions/project-1/codex"),
    artifacts,
    ["codex", "exec", "Build an app"],
  )
  assert_true(args.contains("--platform"))
  assert_true(args.contains("linux/amd64"))
  assert_true(args.contains("--name"))
  assert_true(args.contains("mooncraft-project-1-run-1"))
  assert_true(args.contains("--env-file"))
  assert_true(
    args.contains(
      "/app/data/runtime/projects/project-1/artifacts/runs/run-1/agent.env",
    ),
  )
  assert_false(args.contains("MOONCRAFT_AI_PROVIDER=openrouter"))
  assert_false(args.contains("MOONCRAFT_AI_MODEL=anthropic/claude-sonnet-4.5"))
  assert_false(args.contains("MOONCRAFT_AI_API_KEY=leased-key"))
  assert_false(args.contains("CODEX_HOME=/root/.codex"))
  assert_true(
    args.contains(
      "/srv/mooncraft/test/data/agent-sessions/project-1/codex:/root",
    ),
  )
  assert_true(
    args.contains(
      "/srv/mooncraft/test/data/runtime/projects/project-1/workspace:/workspace",
    ),
  )
  assert_true(
    args.contains(
      "/srv/mooncraft/test/data/runtime/projects/project-1/artifacts/runs/run-1:/artifacts",
    ),
  )
  assert_false(
    args.contains("/app/data/runtime/projects/project-1/workspace:/workspace"),
  )
  assert_false(args.contains("OPENAI_API_KEY"))
  let env_file = docker_env_file_content(config)
  assert_true(env_file.contains("MOONCRAFT_AI_PROVIDER=openrouter"))
  assert_true(
    env_file.contains("MOONCRAFT_AI_MODEL=anthropic/claude-sonnet-4.5"),
  )
  assert_true(env_file.contains("MOONCRAFT_AI_API_KEY=leased-key"))
  assert_true(env_file.contains("CODEX_HOME=/root/.codex"))
}

///|
test "claude docker command mounts non-root home" {
  let config : AgentRuntimeConfig = {
    image: "agent:test",
    platform: "linux/amd64",
    agent_cli: "claude_code",
    provider: "openrouter",
    model: "anthropic/claude-opus-4.6",
    api_key: "leased-key",
    container_home: "/home/mooncraft",
    container_data_dir: "/app/data",
    host_data_dir: Some("/srv/mooncraft/test/data"),
  }
  let artifacts : RunArtifacts = {
    project_id: "project-1",
    run_id: "run-1",
    dir: "/app/data/runtime/projects/project-1/artifacts/runs/run-1",
    last_message_path: "/app/data/runtime/projects/project-1/artifacts/runs/run-1/last_message.txt",
    agent_log_path: "/app/data/runtime/projects/project-1/artifacts/runs/run-1/agent.log",
    validation_log_path: "/app/data/runtime/projects/project-1/artifacts/runs/run-1/validation.log",
  }
  let args = docker_command_args(
    config,
    "/app/data/runtime/projects/project-1/artifacts/runs/run-1/agent.env",
    "/app/data/runtime/projects/project-1/workspace",
    Some("/app/data/agent-sessions/project-1/claude_code"),
    artifacts,
    ["claude", "--bare", "-p", "Build an app"],
  )
  assert_false(args.contains("--user"))
  assert_true(args.contains("HOME=/home/mooncraft"))
  assert_true(
    args.contains(
      "/srv/mooncraft/test/data/agent-sessions/project-1/claude_code:/home/mooncraft",
    ),
  )
}

///|
test "docker host architecture maps to supported container platforms" {
  inspect(
    normalize_docker_architecture("amd64\n"),
    content="Ok(\"linux/amd64\")",
  )
  inspect(
    normalize_docker_architecture("x86_64"),
    content="Ok(\"linux/amd64\")",
  )
  inspect(normalize_docker_architecture("arm64"), content="Ok(\"linux/arm64\")")
  inspect(
    normalize_docker_architecture("aarch64"),
    content="Ok(\"linux/arm64\")",
  )
  assert_true(normalize_docker_architecture("riscv64") is Err(_))
}

///|
test "project Codex home is platform managed and outside the runtime workspace cache" {
  let root = "/tmp/mooncraft-root"
  let project_id = "project-123"
  inspect(
    project_codex_home(root, project_id),
    content="/tmp/mooncraft-root/data/codex-sessions/project-123/.codex",
  )
  assert_false(
    project_codex_home(root, project_id).contains("/runtime/projects/"),
  )
  assert_false(project_codex_home(root, project_id).contains("/workspace"))
}

///|
test "project agent homes are platform managed and preserve Codex compatibility" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/control-plane-test-roots/" +
    next_id("agent-home-paths")
  safe_remove_tree(root)
  let project_id = "project-123"
  inspect(
    project_agent_home(root, project_id, "claude_code"),
    content=root + "/data/agent-sessions/project-123/claude_code",
  )
  inspect(
    project_runtime_agent_home(root, project_id, "codex"),
    content=root + "/data/agent-sessions/project-123/codex",
  )
  ensure_dir(project_codex_home(root, project_id))
  inspect(
    project_runtime_agent_home(root, project_id, "codex"),
    content=root + "/data/codex-sessions/project-123",
  )
  safe_remove_tree(root)
}

///|
async test "delete project removes persisted agent homes" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/control-plane-test-roots/" +
    next_id("agent-home-delete")
  safe_remove_tree(root)
  let db_path = root + "/data/control-plane/state-v2.sqlite"
  ensure_dir(parent_dir(db_path))
  let store = try_new_async(db_path).unwrap()
  let ctx = AppContext::{
    root,
    build_profile: Debug,
    store,
    previews: PreviewManager::new(root, Debug),
    agent_gateway: new(root),
  }
  let project_id = next_id("project")
  ignore(
    ctx.store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      "Agent Home Delete Test",
      "codex",
      default_openrouter_model(),
      project_workspace(root, project_id),
    ),
  )
  let codex_home = project_codex_home(root, project_id)
  let kimi_home = project_agent_home(root, project_id, "kimi_code")
  ensure_dir(codex_home)
  ensure_dir(kimi_home)
  safe_write_string(codex_home + "/state.json", "{}")
  safe_write_string(kimi_home + "/state.json", "{}")

  inspect(@fs.path_exists(codex_home + "/state.json"), content="true")
  inspect(@fs.path_exists(kimi_home + "/state.json"), content="true")
  ctx.delete_project(project_id).unwrap()
  inspect(
    @fs.path_exists(project_codex_session_root(root, project_id)),
    content="false",
  )
  inspect(
    @fs.path_exists(project_agent_session_root(root, project_id)),
    content="false",
  )
  safe_remove_tree(root)
}

///|
test "codex display events hide protocol noise" {
  debug_inspect(
    codex_display_event("Reading additional input from stdin..."),
    content="None",
  )
  debug_inspect(
    codex_display_event(
      "2026-04-27T07:31:22Z ERROR codex_core_skills::manager: failed to install system skills",
    ),
    content="None",
  )
  debug_inspect(
    codex_display_event(
      "{\"type\":\"thread.started\",\"thread_id\":\"local-thread\"}",
    ),
    content="Some((\"status\", \"Started the builder session.\"))",
  )
  debug_inspect(
    codex_display_event("{\"type\":\"turn.started\"}"),
    content="Some((\"status\", \"Planning the change.\"))",
  )
  debug_inspect(
    codex_display_event("{\"type\":\"turn.completed\"}"),
    content="Some((\"status\", \"Builder session ended.\"))",
  )
  debug_inspect(
    codex_display_event(
      "{\"type\":\"item.started\",\"item\":{\"type\":\"command_execution\",\"command\":\"/bin/bash -lc 'moon check'\",\"status\":\"in_progress\"}}",
    ),
    content="Some((\"status\", \"Checking the workspace.\"))",
  )
  debug_inspect(
    codex_display_event(
      "{\"type\":\"item.completed\",\"item\":{\"type\":\"file_change\",\"status\":\"completed\"}}",
    ),
    content="Some((\"status\", \"Updated project files.\"))",
  )
}

///|
test "recovery prompt includes original and latest requests" {
  let prompt = recovery_prompt("Build a todo app", "Add labels and due dates")
  assert_true(prompt.contains("Original project requirement"))
  assert_true(prompt.contains("Build a todo app"))
  assert_true(prompt.contains("Latest user request"))
  assert_true(prompt.contains("Add labels and due dates"))
}

///|
fn cleanup_test_db(db_path : String) -> Unit {
  safe_remove_tree(db_path)
  safe_remove_tree(db_path + "-shm")
  safe_remove_tree(db_path + "-wal")
}

///|
async fn new_test_store(root : String, prefix : String) -> (Store, String) {
  let db_dir = root + "/data/control-plane-test-dbs"
  ensure_dir(db_dir)
  let db_path = db_dir + "/" + next_id(prefix) + ".sqlite"
  cleanup_test_db(db_path)
  (try_new_async(db_path).unwrap(), db_path)
}

///|
test "store reports database open failures" {
  let root = @env.current_dir().unwrap_or(".")
  let db_dir = root + "/data/control-plane-test-dbs"
  ensure_dir(db_dir)
  let db_path = db_dir + "/" + next_id("db-open-failure")
  safe_remove_tree(db_path)
  ensure_dir(db_path)

  let result = try_new(db_path)

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  safe_remove_tree(db_path)
}

///|
test "app context cleans legacy project workspaces at startup" {
  let root = @env.current_dir().unwrap_or(".") +
    "/data/control-plane-test-roots/" +
    next_id("legacy-cleanup")
  let legacy_root = legacy_project_workspaces_root(root)
  safe_remove_tree(root)
  ensure_dir(legacy_root + "/project-legacy/workspace")
  safe_write_string(
    legacy_root + "/project-legacy/workspace/README.md",
    "legacy\n",
  )

  let result = AppContext::try_new_with_recovery(root, false)

  inspect(
    match result {
      Ok(_) => @fs.path_exists(legacy_root)
      Err(_) => true
    },
    content="false",
  )
  safe_remove_tree(root)
}

///|
async test "start_run persists the initial project prompt once" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "initial-project-prompt")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      "Prompt Test",
      "codex",
      default_openrouter_model(),
      project_workspace(root, project_id),
    ),
  )

  debug_inspect(store.get_initial_project_prompt(project_id), content="None")
  let first_run = store.start_run(project_id, "Build a todo app").unwrap()
  debug_inspect(
    store.get_initial_project_prompt(project_id),
    content="Some(\"Build a todo app\")",
  )
  store.finish_run_failure(
    project_id,
    first_run.run_id,
    "first failed",
    "first failed",
    None,
  )
  let second_run = store.start_run(project_id, "Add labels").unwrap()
  let _ = second_run
  debug_inspect(
    store.get_initial_project_prompt(project_id),
    content="Some(\"Build a todo app\")",
  )
  cleanup_test_db(db_path)
}

///|
async test "finish_run_cancelled clears active project run" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "cancel-run")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      "Cancel Test",
      "codex",
      default_openrouter_model(),
      project_workspace(root, project_id),
    ),
  )
  let run = store.start_run(project_id, "Build a game").unwrap()
  store.set_run_worker_pid(project_id, run.run_id, 12345)
  debug_inspect(
    store
    .get_running_run_worker(project_id, run.run_id)
    .map(fn(worker) { worker.worker_pid }),
    content="Some(12345)",
  )

  store.finish_run_cancelled(project_id, run.run_id)

  let cancelled = store.get_run(project_id, run.run_id).unwrap()
  inspect(cancelled.state == Cancelled, content="true")
  debug_inspect(cancelled.summary, content="Some(\"Stopped.\")")
  let project = store.get_project_detail(project_id).unwrap()
  inspect(project.status == Cancelled, content="true")
  debug_inspect(project.current_run_id, content="None")
  let retry_run = store.start_run(project_id, "Try again")
  inspect(retry_run is Ok(_), content="true")
  cleanup_test_db(db_path)
}

///|
async test "run events append and list after sequence" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "run-events")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      "Events Test",
      "codex",
      default_openrouter_model(),
      project_workspace(root, project_id),
    ),
  )
  let run = store.start_run(project_id, "Build a todo app").unwrap()

  store.append_run_event(
    project_id,
    run.run_id,
    "status",
    "Starting Codex session.",
  )
  store.append_run_event(
    project_id,
    run.run_id,
    "codex",
    "{\"type\":\"turn.started\"}",
  )
  let first_page = store.list_run_events(project_id, run.run_id, 0)
  inspect(first_page.length(), content="2")
  inspect(first_page[0].seq, content="1")
  inspect(first_page[1].kind, content="codex")
  let second_page = store.list_run_events(project_id, run.run_id, 1)
  inspect(second_page.length(), content="1")
  inspect(second_page[0].content, content="{\"type\":\"turn.started\"}")
  cleanup_test_db(db_path)
}

///|
async test "admin run and project listings are project agnostic" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "admin-listings")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      "Admin Listings",
      "codex",
      default_openrouter_model(),
      project_workspace(root, project_id),
    ),
  )
  let run = store.start_run(project_id, "Build a todo app").unwrap()
  store.finish_run_failure(
    project_id,
    run.run_id,
    "The update failed before the preview could be refreshed.",
    "raw internal failure",
    None,
  )

  let recent_runs = store.list_recent_runs(10)
  inspect(recent_runs.length(), content="1")
  inspect(recent_runs[0].run_id, content=run.run_id)
  let project_runs = store.list_project_runs(project_id, 10)
  inspect(project_runs.length(), content="1")
  inspect(project_runs[0].project_id, content=project_id)
  let recent_projects = store.list_recent_projects(10)
  inspect(recent_projects.length(), content="1")
  inspect(recent_projects[0].id, content=project_id)
  cleanup_test_db(db_path)
}

///|
async test "OpenRouter key pool leases and finishes usage per run" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "ai-key-pool")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      "AI Pool",
      "codex",
      "openrouter/project-model",
      project_workspace(root, project_id),
    ),
  )
  let key = store.create_admin_ai_key("Test Key", "sk-test-secret", 10).unwrap()
  let _ = key
  ignore(
    store.update_admin_ai_config("openrouter/test-model", [
      "openrouter/test-model",
    ]),
  )
  let run = store.start_run(project_id, "Build a todo app").unwrap()

  let settings = store
    .lease_ai_runtime_settings_for_project(project_id, run.run_id)
    .unwrap()
  inspect(settings.provider, content="openrouter")
  inspect(settings.model, content="openrouter/project-model")
  inspect(settings.api_key, content="sk-test-secret")
  let usages = store.list_recent_ai_key_usages(10)
  inspect(usages.length(), content="1")
  inspect(usages[0].run_id, content=run.run_id)
  inspect(usages[0].state, content="started")

  store.finish_run_success(project_id, run.run_id, "done", Some("thread-1"), {
    url: "/p/test/",
    port: 4300,
    healthy: true,
  })
  let finished = store.list_recent_ai_key_usages(10)
  inspect(finished[0].state, content="succeeded")
  assert_true(finished[0].finished_at is Some(_))
  cleanup_test_db(db_path)
}

///|
async test "startup recovery makes stale running runs retryable" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "stale-running-run")
  let project_id = next_id("project")
  ignore(
    store.create_project(
      project_id,
      "user-1",
      "preview-" + project_id,
      "Recovery Test",
      "codex",
      default_openrouter_model(),
      project_workspace(root, project_id),
    ),
  )
  let stale_run = store.start_run(project_id, "Build a todo app").unwrap()

  inspect(store.fail_stale_running_runs_on_startup(), content="1")
  let recovered_run = store.get_run(project_id, stale_run.run_id).unwrap()
  inspect(recovered_run.state == Failed, content="true")
  debug_inspect(
    recovered_run.summary,
    content="Some(\"The previous worker was interrupted before it could finish. Send another message to retry this project.\")",
  )
  debug_inspect(
    recovered_run.failure_debug.map(fn(debug) { debug.stage }),
    content="Some(\"Worker recovery\")",
  )
  let project = store.get_project_detail(project_id).unwrap()
  inspect(project.status == Failed, content="true")
  debug_inspect(project.current_run_id, content="None")
  let retry_run = store.start_run(project_id, "Retry the app")
  inspect(
    match retry_run {
      Ok(_) => true
      Err(_) => false
    },
    content="true",
  )
  cleanup_test_db(db_path)
}

///|
async test "workspace snapshot round-trips project files and excludes build outputs" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-roundtrip-db")
  let project_id = next_id("snapshot-roundtrip")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path + "/app")
  ensure_dir(workspace_path + "/_build/cache")
  safe_write_string(workspace_path + "/app/main.mbt", "first version\n")
  safe_write_string(workspace_path + "/_build/cache/output.txt", "generated\n")

  snapshot_workspace(store, root, project_id, workspace_path).unwrap()
  safe_write_string(workspace_path + "/app/main.mbt", "second version\n")
  restore_workspace_snapshot(store, root, project_id, workspace_path).unwrap()

  inspect(store.get_workspace_snapshot(project_id) is Some(_), content="true")
  inspect(
    safe_read_string_or(workspace_path + "/app/main.mbt", ""),
    content="first version\n",
  )
  inspect(
    @fs.path_exists(workspace_path + "/_build/cache/output.txt"),
    content="false",
  )
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
async test "restore without a database snapshot fails without legacy fallback" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-migration-db")
  let project_id = next_id("snapshot-migration")
  let workspace_path = project_workspace(root, project_id)
  let legacy_root = legacy_project_workspaces_root(root) + "/" + project_id
  safe_remove_tree(project_root(root, project_id))
  safe_remove_tree(legacy_root)
  ensure_dir(legacy_root)
  safe_write_string(legacy_root + "/README.md", "legacy\n")

  let result = restore_workspace_snapshot(
    store, root, project_id, workspace_path,
  )

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  inspect(@fs.path_exists(legacy_root), content="true")
  safe_remove_tree(legacy_root)
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
async test "restore project workspace for run uses the stable project workspace path" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-stable-workspace-db")
  let project_id = next_id("snapshot-stable-workspace")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path)
  safe_write_string(workspace_path + "/README.md", "from snapshot\n")
  snapshot_workspace(store, root, project_id, workspace_path).unwrap()
  safe_write_string(workspace_path + "/README.md", "changed cache\n")

  let restored_workspace_path = restore_project_workspace_for_run(
    store, root, project_id,
  ).unwrap()

  inspect(restored_workspace_path == workspace_path, content="true")
  inspect(
    safe_read_string_or(workspace_path + "/README.md", ""),
    content="from snapshot\n",
  )
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
async test "builder snapshot persistence saves invalid contract workspaces" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-contract-failure-db")
  let project_id = next_id("snapshot-contract-failure")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path + "/cmd/main")
  safe_write_string(
    workspace_path + "/moon.mod.json",
    "{\"name\":\"test/app\"}\n",
  )
  safe_write_string(
    workspace_path + "/cmd/main/main.mbt",
    "fn main { println(\"Hello\") }\n",
  )
  let artifacts = RunArtifacts::new(root, project_id, "run-contract-failure")

  let result = persist_builder_workspace_snapshot(
    store, root, project_id, workspace_path, "thread-contract-failure", artifacts,
  )
  safe_write_string(workspace_path + "/cmd/main/main.mbt", "changed\n")
  ignore(restore_project_workspace_for_run(store, root, project_id).unwrap())

  inspect(
    match result {
      Ok(_) => true
      Err(_) => false
    },
    content="true",
  )
  inspect(
    safe_read_string_or(workspace_path + "/cmd/main/main.mbt", ""),
    content="fn main { println(\"Hello\") }\n",
  )
  debug_inspect(
    workspace_contract_error(workspace_path).map(fn(message) {
      message.contains("/api/health")
    }),
    content="Some(true)",
  )
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
async test "restore project workspace for run fails without legacy fallback" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-run-legacy-db")
  let project_id = next_id("snapshot-run-legacy")
  let legacy_root = legacy_project_workspaces_root(root) + "/" + project_id
  safe_remove_tree(project_root(root, project_id))
  safe_remove_tree(legacy_root)
  ensure_dir(legacy_root)
  safe_write_string(legacy_root + "/README.md", "legacy\n")

  let result = restore_project_workspace_for_run(store, root, project_id)

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  inspect(@fs.path_exists(legacy_root), content="true")
  safe_remove_tree(legacy_root)
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}

///|
async test "restore project workspace for run requires a database snapshot" {
  let root = @env.current_dir().unwrap_or(".")
  let (store, db_path) = new_test_store(root, "snapshot-run-migration-db")
  let project_id = next_id("snapshot-run-migration")
  let workspace_path = project_workspace(root, project_id)
  safe_remove_tree(project_root(root, project_id))
  ensure_dir(workspace_path)
  safe_write_string(workspace_path + "/README.md", "local cache only\n")

  let result = restore_project_workspace_for_run(store, root, project_id)

  inspect(
    match result {
      Err(_) => true
      Ok(_) => false
    },
    content="true",
  )
  inspect(store.get_workspace_snapshot(project_id) is Some(_), content="false")
  safe_remove_tree(project_root(root, project_id))
  cleanup_test_db(db_path)
}
