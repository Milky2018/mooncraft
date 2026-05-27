# Control Plane

This module is the local backend for the current MoonCraft prototype.

Responsibilities:

- persist users, sessions, projects, messages, runs, workspace source snapshots, and Runtime Service state
- initialize an empty workspace under `data/runtime/projects/<id>/workspace`
- serve the app-develop HTTP API
- serve the main workspace page, frontend bundles, and web-owned static shells
- authenticate users through GitHub OAuth and cookie sessions
- launch durable asynchronous workers for project updates
- supervise one project-scoped Runtime Service container per active project
- keep Runtime Service APIs private on a MoonCraft-managed Docker network
- store preview URLs and last-known run state

The platform no longer owns generated-app setup. Project rows do not carry template ids, and there is no template picker. Project creation saves an empty workspace as the first snapshot. The selected Runtime decides how to turn that workspace into an app; Runtime Protocol v3 exposes that through a project-scoped Runtime Service.

The current `RuntimeGateway` ensures a project-scoped Runtime Service before real Runtime work begins. The supervisor starts the Runtime image through its default entrypoint, mounts Docker named volumes at `/workspace` and `/home/mooncraft`, attaches the container to the MoonCraft Runtime Docker network, checks `GET /health`, and records `stopped` or `ready` state with an idle TTL. `/exec` and Runtime-owned preview proxying are implemented by the next Runtime Protocol v3 slices.

Workspace directories are no longer durable state. The control plane saves the latest source archive in SQLite after initial workspace generation and after agent edits. Each run hydrates that database snapshot into an isolated runtime workspace before starting the selected agent, then restores the local preview cache from the saved snapshot.

Agent session directories are durable app data, not host user state. MoonCraft does not mount a developer's local agent home, and Runtime secrets are resolved only from sources declared in the project Runtime snapshot. Deleting a project removes its workspace cache, artifacts, database rows, legacy session data, and `data/agent-sessions/<project-id>`.

The legacy `data/projects` workspace root is cleaned at startup. It is not used as a restore fallback, because generated files must come from the database snapshot or be treated as unavailable.

SQLite is a required dependency for the control plane. If the database cannot be opened or schema initialization fails, the service exits during startup. The health endpoint also checks database availability and returns unavailable when the probe fails.

## Runtime Boundary

For real Docker-backed runs, the MoonCraft agent runtime image installs the supported agent CLIs and any knowledge or templates that Runtime wants to expose to the agent. Normal user prompts are not wrapped with the generated-app contract; that project-aware contract lives in the runtime system layer.

MoonCraft no longer runs generic app-framework validation gates after the builder returns. The generated app's runtime contract is `mooncraft-preview.sh <port>`: if that script can start a reachable preview and return a non-empty page from its private port, the workspace is accepted. Lightweight preview audit may still request repairs when the private preview returns an error or an empty response.

## Web Assets

Frontend-owned static files live under `apps/web/public`, which mirrors public URL paths. This includes:

- `control-plane-assets/platform/index.html` and `control-plane-assets/platform/style.css` for the root app shell
- `control-plane-assets/admin/index.html` for the admin app shell
- `control-plane-assets/admin-login/index.html` for the admin session form
- `control-plane-assets/auth/github-callback/index.html` for the OAuth callback handoff page
- `control-plane-assets/preview-fallback/index.html` and `control-plane-assets/preview-fallback/styles.css` for generated previews that do not provide their own shell
- `control-plane-assets/smoke-preview/index.html` for fake-runtime preview smoke runs
- `assets/logo.svg`, `assets/logo.png`, and `assets/factory.webp` for public web app imagery

These files are runtime assets owned by `apps/web`, not control-plane source. `moon build` builds both the Rabbita frontend bundle and the native control-plane executable through the workspace. The control plane does not run `moon` at startup; it serves the prebuilt frontend bundle from `_build/js/<profile>/build/mooncraft/web/web.js`. Project creation does not require generated-app language tooling; it creates an empty workspace snapshot. The supported local walkthrough runs from the repository root through `just serve`, which builds the workspace before starting the executable. The Docker app image installs build tooling for MoonCraft itself, but generated-app tooling belongs to the selected Runtime.

If you run a compiled `control-plane.exe` from another directory, keep `apps/web/public` available under that working directory or the file-backed HTML pages will not render.

## Authentication

GitHub OAuth is the only supported sign-in provider. Set `MOONCRAFT_PUBLIC_BASE_URL`, `MOONCRAFT_GITHUB_CLIENT_ID`, and `MOONCRAFT_GITHUB_CLIENT_SECRET` before exposing the service. Users are created or linked from their verified GitHub email address, and sessions are stored in HTTP-only cookies.

Automated local tests can set `MOONCRAFT_ENABLE_DEV_AUTH=1` to enable `POST /api/dev/auth/session`. That endpoint creates a GitHub-shaped test session without external OAuth and must stay disabled outside local smoke runs.

## Preview Flow

Generated previews are script-backed. The control plane starts the root `mooncraft-preview.sh` script with `<port>` as its first argument on a private local port and exposes the result through the deployment-owned preview origin policy. Set `MOONCRAFT_PREVIEW_ORIGIN_TEMPLATE` to an origin template such as `https://{preview_public_id}.preview.example.com`; if it is not set, local development falls back to `/p/<preview_public_id>/`.

The generated app must serve the user-facing app at `/`. `/api/health` is the preferred readiness endpoint, and `/` is accepted as a fallback for static or browser-only previews. If the preview script is missing, exits too early, or does not become reachable, MoonCraft asks the agent to repair the preview setup.

Preview process state is not durable. Opening an existing project is a read-only operation and must not restore snapshots, restart `mooncraft-preview.sh`, or wait for preview health. If a stored preview URL is requested after its process has gone away, MoonCraft marks that preview unhealthy and returns a fast error; the user can rerun the project to start a fresh preview.

After HTTP readiness succeeds, MoonCraft optionally runs `scripts/preview_audit.sh` directly against the private preview port. The audit is intentionally dependency-light and fails on non-success HTTP status, empty response bodies, or known platform preview error pages. It must not call the public preview proxy because that proxy is a user-facing read path with stale-preview error handling. When it fails, MoonCraft sends the audit output back to the selected agent for a bounded repair loop before marking the run successful. Set `MOONCRAFT_PREVIEW_AUDIT=0` to disable it, `MOONCRAFT_PREVIEW_AUDIT_TIMEOUT_SECONDS` to tune the curl timeout, or `MOONCRAFT_PREVIEW_AUDIT_REPAIR_ATTEMPTS` to tune the repair bound.

## Validation

Use these repository-level checks:

- `just check-agent-runtime-image` verifies required tools and knowledge assets inside the agent runtime image.
- `just smoke` covers the default project creation, fake builder update, preview rebuild, deletion, and persistence flow.

Runtime configuration is stored in admin-managed Runtime manifests, not process-wide service environment variables or repository-seeded built-ins. Runtime rows should follow the Runtime Protocol documented in `docs/runtime-protocol/`. Runtime Protocol v3 narrows the manifest to `protocol_version`, `image`, semantics-free `env`, and semantics-free `secrets`; the Runtime image owns its service implementation behind the Runtime Service HTTP API.

The runtime intentionally does not mount a host AI tool home and users do not configure provider keys. Admins log in at `/admin/login` with `MOONCRAFT_ADMIN_TOKEN` and use `/admin` to inspect users, manage projects, inspect recent runs, configure named secrets, and configure Runtime manifests. Secret APIs store secret values, return only hints, and the worker injects only the sources declared by the project's fixed Runtime snapshot.

Use `just agent-runtime-config` to inspect the effective runtime configuration. Build the runtime image for the Docker host architecture with `just build-agent-runtime-image <repository> <version>`; pass `linux/amd64` or `linux/arm64` only when you intentionally need a specific platform. Use `just build-agent-runtime-images <repository> <version>` to build both local architecture-suffixed tags. Publish the shared multi-architecture runtime image with `just docker-agent-runtime-publish <repository> <version> linux/amd64,linux/arm64` after `docker login`.

Use `OPENROUTER_API_KEY=... just agent-smoke` from the repository root only when you intentionally want to spend real provider quota on an end-to-end Docker-backed build. The smoke script writes the key as an admin Secret after startup; it does not configure MoonCraft through service environment variables. Optional smoke overrides are `MOONCRAFT_AGENT_SMOKE_KEY_REF` and `MOONCRAFT_AGENT_SMOKE_MODEL`. The old `just codex-smoke` recipe remains as a compatibility alias.
