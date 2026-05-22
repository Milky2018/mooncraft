# MoonCraft Runtime Standard

MoonCraft treats a Runtime as a pluggable builder contract. The control plane owns project state, workspace/artifact mounts, secret resolution, and process execution. A Runtime owns the image contents and the command that turns a prompt into project code.

The control plane must not contain official Runtime definitions. Official Runtimes are data files under `runtime/builtin/`; admin-created Runtimes are database rows with the same manifest shape. Runtime ids are assigned by MoonCraft and are not written in manifest files.

## Built-in Manifest

Built-in Runtime files are named after the Runtime name:

```text
runtime/builtin/Codex.json
runtime/builtin/Claude.json
runtime/builtin/Kimi.json
```

Each file has this shape:

```json
{
  "name": "Codex",
  "enabled": true,
  "is_default": true,
  "spec": {
    "protocol_version": 1,
    "image": "docker.io/moonbitcloud/mooncraft-agent-runtime:0.1.1",
    "agent": "codex",
    "model": "openai/gpt-5.4-mini",
    "provider": "openrouter",
    "send": ["mooncraft-runtime-send"],
    "container_home": "/root",
    "secrets": [
      {
        "source": "mooncraft_ai_api_key",
        "env": "MOONCRAFT_AI_API_KEY"
      }
    ]
  }
}
```

`name` must match the file name without `.json`. `id` is deliberately absent; MoonCraft assigns ids such as `agent-runtime-001` while seeding. On startup, MoonCraft updates those platform-assigned built-in rows from the manifest files so the official Runtime protocol remains image-owned data, not service code.

Runtime manifests are strict. MoonCraft does not infer missing fields from the Runtime name, `agent`, historical defaults, service environment variables, or older rows. Invalid Runtime JSON, missing required fields, unsupported protocol versions, missing secret declarations, and missing default Runtime rows are configuration errors.

## Runtime Spec

`protocol_version` is the MoonCraft runtime protocol version. The only supported value is `1`.

`image` is the Docker image used for builder runs. Production images must publish both `linux/amd64` and `linux/arm64`.

`agent`, `model`, and `provider` are Runtime-owned metadata. The control plane passes them through to `/artifacts/runtime_context.json` and selected environment variables; it does not branch on official Runtime names.

`send` is an argv array executed inside the Runtime container. MoonCraft does not support shell strings. If shell behavior is needed, make it explicit, for example:

```json
["sh", "-lc", "custom-command \"$MOONCRAFT_RUNTIME_CONTEXT\""]
```

`container_home` is the home directory mounted for this Runtime. Runtime-specific filesystem policy belongs here, not in control-plane agent-type branches.

`secrets` declares environment variables or files that must be resolved before the Runtime command starts. The `source` value is the name of an admin-managed Secret:

```json
{
  "source": "mooncraft_ai_api_key",
  "env": "MOONCRAFT_AI_API_KEY"
}
```

The control plane only resolves declared secret sources. If a Runtime does not declare a secret, no provider key or account file is injected.

## Execution Protocol

Before running `send`, MoonCraft writes:

```text
/artifacts/prompt.txt
/artifacts/runtime_context.json
```

`runtime_context.json` contains:

```json
{
  "protocol_version": 1,
  "project_id": "project-...",
  "run_id": "run-...",
  "agent_session_id": "agent-session-...",
  "runtime_session_id": "native-session-id-or-null",
  "prompt_file": "/artifacts/prompt.txt",
  "workspace": "/workspace",
  "artifacts": "/artifacts",
  "runtime_id": "agent-runtime-001",
  "runtime_name": "Codex",
  "agent": "codex",
  "model": "openai/gpt-5.4-mini",
  "provider": "openrouter"
}
```

The Runtime must read the prompt from `prompt_file`; `$prompt` is not part of the protocol.

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

## Control Plane Boundary

The control plane may:

- load manifest files from `runtime/builtin/`
- assign stable platform ids
- persist Runtime snapshots on project creation
- resolve declared secret sources
- mount `/workspace`, `/artifacts`, and `container_home`
- execute `send`
- stop Runtime containers that exceed the platform run limit, which is capped at one hour
- read `result.json`

The control plane must not:

- hardcode official Runtime names
- hardcode official Runtime models
- infer filesystem policy from `agent`
- inject provider secrets unless the Runtime declares them
- parse Runtime logs to infer session state
- recover from invalid Runtime rows by guessing a legacy image, model, command, container home, provider, or secret binding

## Image Build

Local image check:

```bash
just build-agent-runtime-image docker.io/<org>/<image> <version>
./scripts/check_agent_runtime_image.sh docker.io/<org>/<image>:<version>
```

Multi-platform publish:

```bash
just docker-agent-runtime-publish docker.io/<org>/<image> <version> linux/amd64,linux/arm64
```
