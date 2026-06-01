# Control Plane

This module is the local backend for the current MoonCraft prototype.

Responsibilities:

- persist users, sessions, projects, messages, runs, source repository metadata, legacy workspace snapshot metadata, and Runtime Service state
- create and track user-owned Project Source Repositories
- serve the app-develop HTTP API
- serve the main workspace page, frontend bundles, and web-owned static shells
- authenticate users through GitHub OAuth and cookie sessions
- launch durable asynchronous workers for project updates
- supervise one project-scoped Runtime Service container per active project
- keep Runtime Service APIs private on a MoonCraft-managed Docker network
- store preview URLs and last-known run state

The platform no longer owns generated-app setup. Project rows do not carry template ids, and there is no template picker. Project creation creates an empty Project Source Repository, but does not write starter source files. The selected Runtime decides how to turn that repository into an app; Runtime Protocol v3 exposes that through a project-scoped Runtime Service.

The current `RuntimeGateway` ensures a project-scoped Runtime Service before real Runtime work begins. The first implementation starts that service with the Docker Runtime Launcher, attaches it to the MoonCraft Runtime network, checks `GET /health`, calls `POST /init` with repository access and Runtime Secrets, and records `stopped`, `ready`, or `running` state with an idle TTL. Runs go through Runtime Protocol v3 `POST /exec`, and previews are proxied through Runtime-owned `/preview/`.

Project Source Repositories are the durable generated-project storage. The control plane stores repository metadata and the current Ready Source Commit, but it does not persist generated source in Docker volumes or workspace archives. Workspace snapshots are legacy import artifacts and smoke-test fixtures only.

MoonCraft does not mount a developer's local agent home, and Runtime secrets are resolved only from sources declared in the project Runtime snapshot. Resolved Runtime Secrets are passed to `POST /init` as opaque name/value payloads; the Runtime Service decides how to consume them. Deleting a project removes MoonCraft metadata and Runtime Service state, but it does not delete the user-owned Project Source Repository.

The legacy `data/projects` workspace root is cleaned at startup. Existing workspace snapshots are migration data, not the Runtime Protocol v3 source persistence model.

SQLite is a required dependency for the control plane. If the database cannot be opened or schema initialization fails, the service exits during startup. The health endpoint also checks database availability and returns unavailable when the probe fails.

## Runtime Boundary

For real Docker-backed runs, the selected Runtime image exposes a Runtime Protocol v3 HTTP service. Docker is the current Runtime Launcher implementation, not the protocol. The Runtime may install agent CLIs, knowledge, templates, queues, git tooling, or any other implementation detail it needs. Normal user prompts are not wrapped with the generated-app contract by the control plane; that project-aware contract lives behind the Runtime Service boundary.

MoonCraft no longer runs generic app-framework validation gates after the builder returns, and it does not know any generated-app preview script contract. Runtime Protocol v3 makes preview startup the Runtime Service's responsibility. MoonCraft proxies preview traffic to the Runtime Service `/preview/` subtree.

## Web Assets

Frontend-owned static files live under `apps/web/public`, which mirrors public URL paths. This includes:

- `control-plane-assets/platform/index.html` and `control-plane-assets/platform/style.css` for the root app shell
- `control-plane-assets/admin/index.html` for the admin app shell
- `control-plane-assets/admin-login/index.html` for the admin session form
- `control-plane-assets/auth/github-callback/index.html` for the OAuth callback handoff page
- `control-plane-assets/preview-fallback/index.html` and `control-plane-assets/preview-fallback/styles.css` for generated previews that do not provide their own shell
- `control-plane-assets/smoke-preview/index.html` for fake-runtime preview smoke runs
- `assets/logo.svg`, `assets/logo.png`, and `assets/factory.webp` for public web app imagery

These files are runtime assets owned by `apps/web`, not control-plane source. `moon build` builds both the Rabbita frontend bundle and the native control-plane executable through the workspace. The control plane does not run `moon` at startup; it serves the prebuilt frontend bundle from `_build/js/<profile>/build/mooncraft/web/web.js`. Project creation does not require generated-app language tooling; it creates Runtime storage only. The supported local walkthrough runs from the repository root through `just serve`, which builds the workspace before starting the executable. The Docker app image installs build tooling for MoonCraft itself, but generated-app tooling belongs to the selected Runtime.

If you run a compiled `control-plane.exe` from another directory, keep `apps/web/public` available under that working directory or the file-backed HTML pages will not render.

## Authentication

GitHub OAuth is the only supported sign-in provider. Set `MOONCRAFT_PUBLIC_BASE_URL`, `MOONCRAFT_GITHUB_CLIENT_ID`, and `MOONCRAFT_GITHUB_CLIENT_SECRET` before exposing the service. Users are created or linked from their verified GitHub email address, and sessions are stored in HTTP-only cookies.

Automated local tests can set `MOONCRAFT_ENABLE_DEV_AUTH=1` to enable `POST /api/dev/auth/session`. That endpoint creates a GitHub-shaped test session without external OAuth and must stay disabled outside local smoke runs.

## Preview Flow

Generated previews are Runtime-backed. The control plane never starts `mooncraft-preview.sh` as a child process in the Runtime Protocol v3 path. Set `MOONCRAFT_PREVIEW_ORIGIN_TEMPLATE` to an origin template such as `https://{preview_public_id}.preview.example.com`; if it is not set, local development falls back to `/p/<preview_public_id>/`.

The Runtime Service owns preview readiness and preview content. On every public preview request, MoonCraft ensures the project Runtime Service is healthy and initialized, then proxies the request to the Runtime Service `/preview/` subtree. Successful preview requests refresh the Runtime idle TTL. Runtime preview errors are returned to the user and do not refresh the TTL.

Preview process state belongs to the Runtime container, not the control plane. Opening an existing project is a read-only operation; preview requests are the explicit trigger that may restart a stopped Runtime Service. MoonCraft does not run preview audit repair prompts or bounded repair loops in the Runtime Protocol v3 flow.

## Validation

Use these repository-level checks:

- `just check-agent-runtime-image` verifies required tools, knowledge assets, and the Runtime Protocol v3 HTTP service inside the runtime image.
- `just smoke` covers the default project creation, fake builder update, preview rebuild, deletion, and persistence flow.

Runtime configuration is stored in admin-managed Runtime Config rows, not process-wide service environment variables or repository-seeded built-ins. Runtime Protocol v3 is the HTTP service contract documented in `docs/runtime-protocol/`; Runtime Config is MoonCraft launcher configuration. The first Runtime Config implementation supports the Docker Runtime Launcher plus semantics-free `env` and named Secret bindings.

The runtime intentionally does not mount a host AI tool home and users do not configure provider keys. Admins log in at `/admin/login` with `MOONCRAFT_ADMIN_TOKEN` and use `/admin` to inspect users, manage projects, inspect recent runs, configure named secrets, and configure Runtime Configs. `GET /api/admin/logs/recent/:limit` returns recent operation logs for platform-level failures that may happen before a project or run exists. Secret APIs store secret values, return only hints, and the worker sends only the sources declared by the project's fixed Runtime snapshot to `POST /init`.

Use `just agent-runtime-config` to inspect the effective runtime configuration. Build the runtime image for the Docker host architecture with `just build-agent-runtime-image <repository> <version>`; pass `linux/amd64` or `linux/arm64` only when you intentionally need a specific platform. Use `just build-agent-runtime-images <repository> <version>` to build both local architecture-suffixed tags. Publish the shared multi-architecture runtime image with `just docker-agent-runtime-publish <repository> <version> linux/amd64,linux/arm64` after `docker login`.

Use `OPENROUTER_API_KEY=... GITHUB_TOKEN=... just agent-smoke` from the repository root only when you intentionally want to spend real provider quota on an end-to-end Docker-backed build. The GitHub token must be allowed to create, read, push to, and delete a disposable repository. The smoke script writes the provider key as an admin Secret, injects the GitHub token only into the dev-auth smoke user, registers a Runtime Config after startup, verifies the pushed Ready Source Commit, and then deletes the disposable repository. Optional smoke overrides are `MOONCRAFT_AGENT_SMOKE_KEY_REF`, `MOONCRAFT_AGENT_SMOKE_GITHUB_TOKEN_REF`, and `MOONCRAFT_AGENT_SMOKE_MODEL`. The old `just codex-smoke` recipe remains as a compatibility alias.
