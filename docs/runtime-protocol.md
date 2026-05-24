# MoonCraft Runtime Protocol v2

Runtime Protocol v2 is the only supported Runtime protocol. It is intentionally
small: a Runtime is a Docker image plus a Runtime Manifest that tells MoonCraft
which supported Builder Agent to run and which admin-managed credential to
inject. The control plane owns CLI invocation, session tracking, streaming
progress, workspace mounts, preview startup, and preview audit.

Protocol v2 is breaking. MoonCraft does not infer or migrate v1 fields at run
time.

## Runtime Manifest

Admin-created Runtime JSON and built-in Runtime `spec` objects both use this
shape:

```json
{
  "protocol_version": 2,
  "image": "docker.io/moonbitcloud/mooncraft-agent-runtime:0.3.0",
  "agent": "codex",
  "model": "openai/gpt-5.4-mini",
  "auth": {
    "kind": "openrouter_api_key",
    "secret": {
      "source": "mooncraft_ai_api_key",
      "target": {
        "type": "env",
        "name": "MOONCRAFT_AI_API_KEY"
      }
    }
  }
}
```

Fields:

- `protocol_version`: must be `2`.
- `image`: Docker image tag. Production Runtime images must publish both
  `linux/amd64` and `linux/arm64`.
- `agent`: supported Builder Agent. Must be `codex` or `claude`.
- `model`: model name passed to that Builder Agent.
- `auth`: one structured credential binding.

Removed v1 fields:

- `provider`
- `send`
- `secrets`
- `container_home`
- `container_user`

The manifest schema is `schemas/runtime-manifest.v2.schema.json`.

## Runtime Auth

`auth.kind` declares how the Agent Adapter should use the secret:

- `openrouter_api_key`: a generic OpenRouter API key, usable by both Codex and
  Claude adapters.
- `codex_auth_json`: a Codex account file.
- `claude_auth_json`: a Claude account file.

`auth.secret.source` is the name of one admin-managed Secret. MoonCraft injects
only that secret for the Runtime Turn.

`auth.secret.target` is explicit so admins can inspect where the credential is
placed:

```json
{
  "type": "env",
  "name": "MOONCRAFT_AI_API_KEY"
}
```

```json
{
  "type": "file",
  "path": ".codex/auth.json"
}
```

File targets are relative to the fixed container home `/home/mooncraft` and must
not contain empty, `.`, or `..` path segments.

## Built-In Runtime Files

Built-in Runtime files live in `runtime/builtin/` and are named by user-facing
Runtime name:

```text
runtime/builtin/Codex.json
runtime/builtin/Claude.json
```

The file shape is:

```json
{
  "name": "Codex",
  "enabled": true,
  "is_default": true,
  "spec": {
    "protocol_version": 2,
    "image": "docker.io/moonbitcloud/mooncraft-agent-runtime:0.3.0",
    "agent": "codex",
    "model": "openai/gpt-5.4-mini",
    "auth": {
      "kind": "openrouter_api_key",
      "secret": {
        "source": "mooncraft_ai_api_key",
        "target": {
          "type": "env",
          "name": "MOONCRAFT_AI_API_KEY"
        }
      }
    }
  }
}
```

`name` must match the file name without `.json`. Runtime ids are assigned by
MoonCraft, for example `agent-runtime-001`; ids are not written into Runtime
manifest files.

The built-in wrapper schema is `schemas/builtin-runtime.v2.schema.json`.

## Runtime Image Contract

MoonCraft runs the Runtime image as its Dockerfile default user. It does not pass
`docker run --user`.

The image must provide:

- default non-root user
- `HOME=/home/mooncraft`
- writable `/home/mooncraft`
- supported Builder Agent CLI for the selected `agent`
- enough project build tools for generated apps, including MoonBit and a C
  toolchain
- Runtime knowledge and templates the image provider wants the agent to use

MoonCraft always mounts these fixed paths:

- `/workspace`: project workspace
- `/home/mooncraft`: durable agent session home
- `/artifacts`: control-plane-owned agent logs and helper artifacts

The Runtime image must keep those paths writable by the default user.

## Agent Adapters

Runtime Protocol v2 does not support arbitrary Runtime commands. MoonCraft owns
one Agent Adapter per supported `agent`.

The Agent Adapter is responsible for:

- translating the Runtime Manifest into Codex or Claude CLI arguments
- configuring OpenRouter or account-file auth for that CLI
- streaming CLI output into project activity events
- extracting the native agent session id
- preserving one project-bound agent session id across future turns
- applying the one-hour maximum Runtime Turn limit

Prompt transport, CLI flags, logs, and session-id extraction are adapter
implementation details, not Runtime protocol fields.

## Agent Artifacts

`/artifacts` is mounted for control-plane-owned artifacts. It is not a
request/response protocol directory.

MoonCraft may write files such as:

- `prompt.txt`
- `agent.log`
- `last_message.txt`
- `validation.log`
- preview audit logs

These files are debug and adapter implementation details. Runtime images must not
be required to read `runtime_context.json` or write `result.json`; both are v1
protocol concepts and are removed in v2.

## Project Preview Contract

The generated project, not the Runtime Manifest, owns preview startup.

Each generated project must provide this executable script in the project
workspace:

```text
./mooncraft-preview.sh <port>
```

The script must:

- listen on `0.0.0.0:<port>`
- serve the user-facing app at `/`
- keep running in the foreground
- prefer `/api/health` for readiness when practical

MoonCraft starts this script on a private local port, waits for HTTP readiness,
and then exposes the project through the deployment's Preview Origin Policy.

## Preview Origin Policy

Previews use one project-scoped origin. Historical run preview URLs are not part
of the product.

The public preview origin is deployment-owned platform configuration. MoonCraft
can be configured with an origin template such as
`https://{preview_public_id}.preview.example.com`, but this setting is outside
Runtime manifests. Runtime manifests, runtime images, admins, users, and agents
do not need to know the real deployment host name.

Because each generated app is root-mounted at its own origin, preview audit
should not reject root-relative browser URLs by scanning source text. The audit
checks reachability, non-empty app response, same-origin asset reachability, and
optional browser errors.

## Hard Failures

MoonCraft fails a Runtime Turn when:

- the Runtime Manifest is invalid
- the selected Runtime image cannot be started
- the Builder Agent CLI exits non-zero
- the Agent Adapter cannot determine the native agent session id
- the turn exceeds the platform runtime limit
- the project workspace cannot be snapshotted after a successful agent run
- `mooncraft-preview.sh` cannot start a reachable non-empty preview
