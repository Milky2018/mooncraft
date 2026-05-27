# MoonCraft Runtime Protocol v3

Runtime Protocol v3 defines the boundary between MoonCraft and a project-scoped Runtime Service. A Runtime is a Docker image plus optional semantics-free secret bindings. MoonCraft does not know whether the Runtime uses Codex, Claude, another agent, a remote queue, or a human workflow.

Runtime Protocol v3 replaces the v2 control-plane Agent Adapter model. The control plane no longer constructs agent CLI commands, passes model names, manages agent sessions, starts project preview scripts, or repairs previews through agent-specific prompts.

## Authoritative Files

- `README.md`: human-readable protocol specification.
- `openapi.v3.yaml`: Runtime Service HTTP API.
- `runtime-manifest.v3.schema.json`: Runtime Manifest schema.
- `builtin-runtime.v3.schema.json`: built-in Runtime wrapper schema.

## Runtime Manifest

Admin-created Runtime JSON and built-in Runtime `spec` objects use this shape:

```json
{
  "protocol_version": 3,
  "image": "docker.io/org/runtime:1.0.0",
  "secrets": [
    {
      "source": "codex_account",
      "target": {
        "type": "file",
        "path": ".codex/auth.json"
      }
    },
    {
      "source": "ai_api_key",
      "target": {
        "type": "env",
        "name": "OPENROUTER_API_KEY"
      }
    }
  ]
}
```

Fields:

- `protocol_version`: must be `3`.
- `image`: Docker image tag. Production Runtime images should publish both `linux/amd64` and `linux/arm64`.
- `secrets`: optional array of semantics-free secret injection bindings. Missing `secrets` is equivalent to an empty array.

No other fields are allowed. In particular, Runtime Protocol v3 does not define `agent`, `model`, `auth`, `provider`, `send`, `container_home`, `container_user`, or arbitrary command fields.

## Secrets

Runtime secrets only describe where MoonCraft injects admin-managed secret values. They do not describe what the secret means.

Environment target:

```json
{
  "source": "ai_api_key",
  "target": {
    "type": "env",
    "name": "OPENROUTER_API_KEY"
  }
}
```

File target:

```json
{
  "source": "codex_account",
  "target": {
    "type": "file",
    "path": ".codex/auth.json"
  }
}
```

File targets are relative to `/home/mooncraft`. File target paths must not be absolute and must not contain empty, `.`, or `..` path segments.

## Runtime Image Contract

A Runtime image starts its Runtime Service through the image default `ENTRYPOINT` and `CMD`. MoonCraft does not pass a custom command.

The Runtime Service must listen on `0.0.0.0:8080`.

The current project preview must listen on `0.0.0.0:4792` when it is ready.

MoonCraft provides these fixed container paths as Docker named volumes:

- `/workspace`: durable Project Workspace and authoritative project source storage.
- `/home/mooncraft`: durable Runtime Home for Runtime-private state and file secret targets.

Runtime Protocol v3 does not specify the container user, UID, GID, or privilege model. The Runtime image provider owns its image user policy and must ensure the Runtime Service can read and write the mounted volumes it needs.

`/artifacts` is not part of Runtime Protocol v3.

## Docker Network

MoonCraft starts Runtime containers on an internal Docker network and does not publish the Runtime Service port `8080` or preview port `4792` to the host.

Runtime Service APIs do not use HTTP authentication in v3. The network boundary is MoonCraft-managed internal Docker networking.

## Lifecycle

Each project may have one Runtime Service. The Runtime Service state is one of:

- `stopped`: no Runtime Service container is running for the project.
- `ready`: the Runtime Service is running and has no active Run.
- `running`: the Runtime Service is running and has one active Run.

State transitions:

```text
create project -> ready
stopped -- user prompt --> running
ready -- user prompt --> running
running -- run finished --> ready
ready -- idle TTL --> stopped
stopped -- preview request --> ready
ready -- successful preview request --> ready, with refreshed idle TTL
```

The Runtime idle TTL is configured by the MoonCraft admin UI and defaults to 10 minutes. The TTL starts when a Run finishes. A successful preview request refreshes the TTL. Failed preview readiness does not refresh the TTL.

MoonCraft uses lazy recovery. If a requested Runtime Service is missing or unhealthy, MoonCraft marks it stopped and restarts it only for requests that need it, such as a user prompt or preview request. MoonCraft does not use browser unload, project switching, or a global container scan as the Runtime lifecycle driver.

## Runs

`POST /exec` creates an asynchronous Run. MoonCraft provides the `run_id`; the Runtime Service accepts that id and must use it for all subsequent status and event APIs.

Only one active Run is allowed per Runtime Service. If another Run is active, a different `run_id` must be rejected with `409 Conflict`.

`POST /exec` is idempotent for the same `run_id`. Repeating the same request returns the existing Run instead of creating a duplicate. Repeating a `run_id` with a different prompt returns `409 Conflict`.

`202 Accepted` means the Run is registered and immediately readable through `GET /runs/{run_id}`.

Run status values:

- `running`
- `succeeded`
- `failed`

Every Run response has a required human-readable `message`. The Runtime provides this string; Runtime Protocol v3 does not define localization or UI interpretation.

The Run Result returned by `GET /runs/{run_id}` is the authoritative terminal outcome. Run Events are process output, not the authoritative result.

## Events

MoonCraft reads Run Events with JSON polling:

```http
GET /runs/{run_id}/events?after=12
```

The `after` cursor means "return events with `id > after`". If `after` is omitted, events are returned from the beginning of the Runtime Service's currently available event buffer. No new events is a successful empty response.

MoonCraft currently polls every 1 second, but the polling interval is not part of the Runtime Protocol.

Each event id is monotonically increasing within one Run. Runtime Protocol v3 does not require the Runtime to retain historical events after MoonCraft has read them or after the Runtime Service is stopped. MoonCraft persists user-visible event history.

SSE streaming is intentionally out of scope for v3. TODO: consider an event stream endpoint after the polling contract has been stable in production.

## Preview

`GET /preview` is a readiness check for the fixed preview port `4792`.

- `200 OK`: MoonCraft may proxy the project's Preview Origin to `http://<runtime-container>:4792/`.
- Non-2xx: preview is not available; the response body is a Runtime Error.

MoonCraft no longer starts `./mooncraft-preview.sh` itself in Runtime Protocol v3. The Runtime Service owns preview startup inside the Runtime container.

MoonCraft does not automatically repair preview failures. If `/preview` returns an error, MoonCraft reports that error to the user. The user can send another prompt to create a new Run.

## HTTP API

The Runtime Service HTTP API is defined in `openapi.v3.yaml`.

Required endpoints:

- `GET /health`
- `POST /exec`
- `GET /runs/{run_id}`
- `GET /runs/{run_id}/events`
- `GET /preview`

Successful readiness endpoints do not require response bodies. Runtime errors use this shape:

```json
{
  "message": "Preview is not ready."
}
```

Runtime Protocol v3 does not define `/init`, prompt files, result files, resume, kill, or plan mode. TODO: consider resume, kill, and plan mode after the v3 execution and preview boundary is stable.
