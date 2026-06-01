# MoonCraft Runtime Protocol v3

Runtime Protocol v3 is the HTTP contract between MoonCraft and a project-scoped Runtime Service. It does not define Docker images, container users, mounted volumes, workspace paths, file secret paths, preview ports, agent CLIs, models, or provider accounts.

MoonCraft's current implementation starts Runtime Services with Docker, but Docker is a Runtime launcher detail. A future launcher may connect to any HTTP service that implements this protocol.

## Authoritative Files

- `README.md`: human-readable protocol specification.
- `openapi.v3.yaml`: Runtime Service HTTP API.
- `runtime-config.v3.schema.json`: MoonCraft's first Runtime Config schema for the Docker Runtime Launcher.

Runtime Config is MoonCraft admin configuration, not Runtime Protocol. The current Runtime Config implementation may use Docker images, environment variables, and named Secrets to start or configure a Runtime Service, but those launcher details are outside this protocol.

The first Runtime Config implementation only supports the Docker Runtime Launcher:

```json
{
  "config_version": 3,
  "launcher": {
    "kind": "docker",
    "image": "docker.io/org/runtime:1.0.0"
  },
  "env": {
    "MODEL": "gpt-5.4-mini"
  },
  "secrets": {
    "codex_auth": "codex_account"
  }
}
```

## Runtime Service

A Runtime Service is a project-scoped HTTP service. MoonCraft must be able to reach its HTTP base URL through the active Runtime launcher.

Required endpoints:

- `GET /health`
- `POST /init`
- `POST /exec`
- `GET /runs/{run_id}`
- `GET /runs/{run_id}/events`
- `GET /preview/`

The Runtime Service does not expose HTTP authentication in v3. MoonCraft protects the service through the launcher/network boundary.

## Source Repository

Each MoonCraft project is bound to a user-owned Project Source Repository. The Project Source Repository is the authoritative persistent source store for the project.

GitHub is the current Project Source Host implementation. The protocol uses source-host-neutral names so MoonHub can replace GitHub later.

MoonCraft is responsible for:

- creating an empty Project Source Repository when a project is created;
- storing the repository identity, default branch, and current Ready Source Commit;
- issuing a short-lived repository-scoped Project Source Credential for Runtime initialization;
- detecting unavailable or unauthorized repositories and surfacing Source Disconnected state;
- not deleting the repository when a MoonCraft project is deleted.

The Runtime Service is responsible for:

- cloning or updating the Project Workspace from the Project Source Repository during initialization;
- committing and pushing source changes to the repository default branch before reporting source-modifying work as successful;
- never force-pushing;
- returning the final pushed Ready Source Commit in the terminal Run Result.

## Initialization

MoonCraft must call `POST /init` before any business operation. Until initialization succeeds, all business endpoints return a Runtime Error with HTTP `409 Conflict`.

`POST /init` provides:

- project identity;
- Project Source Repository URL, default branch, and current commit known to MoonCraft;
- Project Source Credential;
- resolved Runtime Secrets.

The Project Source Credential is a first-class protocol field, not a Runtime Secret. It is short-lived, scoped to one Project Source Repository, and intended only for the current Runtime Service initialization.

Runtime Secrets are opaque name/value payloads. MoonCraft does not interpret their names or values. The Runtime Service decides whether a secret is used as an environment value, file content, agent account, API key, or something else.

`POST /init` is retryable while no Run is active. Reinitializing while a Run is active returns `409 Conflict`.

## Runs

`POST /exec` creates an asynchronous Run. MoonCraft provides the `run_id`; the Runtime Service accepts that id and must use it for all subsequent status and event APIs.

Only one active Run is allowed per Runtime Service. If another Run is active, a different `run_id` returns `409 Conflict`.

`POST /exec` is idempotent for the same `run_id`. Repeating the same request returns the existing Run instead of creating a duplicate. Repeating a `run_id` with a different prompt returns `409 Conflict`.

`202 Accepted` means the Run is registered and immediately readable through `GET /runs/{run_id}`.

Run status values:

- `running`
- `succeeded`
- `failed`

Every Run response has a required human-readable `message`. The Runtime provides this string; Runtime Protocol v3 does not define localization or UI interpretation.

The Run Result returned by `GET /runs/{run_id}` is the authoritative terminal outcome. Run Events are progress output, not the authoritative result.

A source-modifying Run may report `succeeded` only after all source changes are committed and pushed to the Project Source Repository default branch. The succeeded Run Result must include the final pushed `ready_commit_sha`. A Run may create multiple commits, but only the final Ready Source Commit is recorded by MoonCraft.

If the remote default branch changed, the Runtime Service may merge or rebase before pushing. If it cannot resolve a conflict automatically, the Run must fail. Runtime Services must not force push.

Runtime-created commits use the MoonCraft Source Identity, not the user's personal Git identity.

## Events

MoonCraft reads Run Events with JSON polling:

```http
GET /runs/{run_id}/events?after=12
```

The `after` cursor means "return events with id > after". If `after` is omitted, events are returned from the beginning of the Runtime Service's currently available event buffer. No new events is a successful empty response.

MoonCraft currently polls every 1 second, but the polling interval is not part of the Runtime Protocol.

Each event id is monotonically increasing within one Run. Runtime Protocol v3 does not require the Runtime to retain historical events after MoonCraft has read them or after the Runtime Service is stopped. MoonCraft persists user-visible event history.

SSE streaming is intentionally out of scope for v3. TODO: consider an event stream endpoint after the polling contract has been stable in production.

## Preview

The Runtime Service exposes the current project preview under the fixed `/preview/` subtree on the same HTTP service as the protocol API.

MoonCraft proxies the project's Preview Origin to the Runtime Service `/preview/` subtree. The browser never talks to the Runtime Service base URL directly.

Runtime Protocol v3 does not define a preview port, preview script, or preview repair flow. If the Runtime Service cannot serve preview content, it returns a Runtime Error and MoonCraft reports that error to the user.

## Lifecycle

Each project may have one Runtime Service. Runtime Service state is driven by MoonCraft lifecycle policy and observed Runtime Service health:

- `stopped`: no Runtime Service is available for the project.
- `ready`: the Runtime Service is initialized and has no active Run.
- `running`: the Runtime Service is initialized and has one active Run.
- `source_disconnected`: the Project Source Repository is unavailable or unauthorized.

The Runtime idle TTL is configured by the MoonCraft admin UI and defaults to 10 minutes. The TTL starts when a Run finishes. A successful preview request refreshes the TTL.

MoonCraft uses lazy recovery. If a requested Runtime Service is missing or unhealthy, MoonCraft starts or reconnects it through the Runtime launcher, calls `POST /init`, and then performs the requested operation. MoonCraft does not use browser unload, project switching, or a global container scan as the Runtime lifecycle driver.

## Out of Scope

Runtime Protocol v3 does not define:

- Docker image layout;
- container user or UID/GID;
- container paths such as `/workspace` or `/home/mooncraft`;
- Docker volumes;
- file secret targets;
- workspace archive import/export;
- preview ports;
- prompt files;
- result files;
- resume, kill, or plan mode.

TODO: consider resume, kill, plan mode, and event streaming after the source-host-backed execution boundary is stable in production.
