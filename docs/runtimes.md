# MoonCraft Runtimes

MoonCraft exposes **Runtime** as the user-facing app builder choice. A Runtime is the complete agent execution environment selected when a project is created. Users do not choose an agent and model separately.

## Product Model

- Admins configure the Runtime list.
- Users select one enabled Runtime when creating a project.
- A project is permanently bound to the selected Runtime.
- The project stores a creation-time Runtime snapshot. Later admin edits to the Runtime do not affect existing projects.
- Project info displays the Runtime name and ids, not a live editable agent/model picker.

Runtime ids are stable and shareable. Built-in ids should use names such as `agent-runtime-001`.

## Runtime Spec

Runtime specs are JSON edited by admins. The first supported command shape is a single `send` argv array:

```json
{
  "image": "docker.io/moonbitcloud/mooncraft-agent-runtime:0.1.0",
  "agent": "codex",
  "model": "openai/gpt-5.4-mini",
  "send": ["mooncraft-runtime-send"]
}
```

`send` must be an argv array. MoonCraft does not support shell command strings. If a Runtime needs shell behavior, the admin must make that explicit in argv, for example `["sh", "-lc", "..."]`.

Runtime specs do not inline secrets. Secrets are managed separately by admins and may be injected into Runtime env or files by explicit references in a later spec revision.

## Image Platforms

Runtime images must be built and published for both supported platforms:

- `linux/amd64`
- `linux/arm64`

MoonCraft detects the Docker host architecture before every builder run and passes the matching `--platform` to `docker run`. Local smoke tests should build the host platform with `just build-agent-runtime-image <repository> <version>`. Release publishing should use `just docker-agent-runtime-publish <repository> <version> linux/amd64,linux/arm64` so one image tag resolves correctly on either host architecture.

## Session Model

MoonCraft follows the craft-agents session model:

- `agent_session_id` is generated and owned by MoonCraft.
- `runtime_session_id` is the Runtime/native agent resume token.
- A project owns exactly one `agent_session_id`.
- A project cannot switch Runtime after creation.
- `runtime_session_id` is persisted after every successful Runtime turn.

MoonCraft writes:

```text
/artifacts/prompt.txt
/artifacts/runtime_context.json
```

`runtime_context.json` contains:

```json
{
  "project_id": "project-...",
  "run_id": "run-...",
  "agent_session_id": "agent-session-...",
  "runtime_session_id": "native-session-id-or-null",
  "prompt_file": "/artifacts/prompt.txt",
  "workspace": "/workspace",
  "artifacts": "/artifacts",
  "runtime_id": "agent-runtime-001",
  "runtime_name": "Agent001",
  "agent": "codex",
  "model": "openai/gpt-5.4-mini"
}
```

The Runtime reads the prompt only from `prompt_file`; `$prompt` is not part of the protocol.

After execution, the Runtime must write:

```json
{
  "runtime_session_id": "native-session-id",
  "last_message": "optional assistant summary"
}
```

MoonCraft treats these as hard failures:

- Runtime process exits non-zero.
- `/artifacts/result.json` is missing.
- `/artifacts/result.json` is invalid JSON.
- `runtime_session_id` is missing or empty.

Stdout/stderr are captured into `agent.log` for debugging only. MoonCraft never parses logs to recover session ids.
