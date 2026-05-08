# Control Plane

This module is the local backend for the current Mooncraft prototype.

Responsibilities:

- persist users, sessions, projects, messages, runs, and workspace source snapshots
- generate the initial MoonBit full-stack workspace under `data/runtime/projects/<id>/workspace`
- serve the app-develop HTTP API
- serve the main workspace page and platform bundle
- serve file-backed control-plane HTML/CSS assets from `services/control-plane/assets`
- authenticate users through GitHub OAuth and cookie sessions
- launch durable asynchronous Codex workers against generated workspaces
- fetch approved MoonBit registry modules before validation and preview builds
- rebuild and restart local previews
- store preview URLs and last-known run state

The platform no longer uses official app templates. Project rows do not carry template ids, and project creation writes only minimal workspace ignore rules. The first user prompt decides what the app becomes; Codex is instructed to use `moon new` and choose the project shape.

The current `AgentGateway` uses Docker-backed Codex CLI runs. Each project keeps one persistent `codex_thread_id` in the database and one platform-owned Codex home under `data/codex-sessions/<project-id>/.codex`. Each new chat message starts a detached worker process through `moonbitlang/async/process` that mounts that Codex home into the disposable container, resumes the session, validates the workspace with dependency fetches plus `moon fmt`, `moon check`, `moon build`, and `moon test`, then refreshes the preview. On startup, stale `Running` runs are marked failed so the project is retryable after a crash or restart.

Workspace directories are no longer durable state. The control plane saves the latest source archive in SQLite after initial workspace generation and after Codex edits. Each run hydrates that database snapshot into an isolated runtime workspace before starting Codex, then restores the local preview cache from the saved snapshot.

Codex session directories are durable app data, not host user state. Mooncraft does not mount a developer's local Codex home, and AI credentials are leased from the admin-managed OpenRouter key pool for one active run at a time. Deleting a project removes its workspace cache, artifacts, database rows, and `data/codex-sessions/<project-id>`.

The legacy `data/projects` workspace root is cleaned at startup. It is not used as a restore fallback, because generated files must come from the database snapshot or be treated as unavailable.

SQLite is a required dependency for the control plane. If the database cannot be opened or schema initialization fails, the service exits during startup. The health endpoint also checks database availability and returns unavailable when the probe fails.

## Dependency Fetches

Before Codex runs, validation, and preview builds, generated user projects run `moon fetch --no-update` for the pinned modules listed in `config/user_project_reference_modules.txt`. That file is the single source of truth for user-project reference packages and versions.

For real Docker-backed runs, the Codex runtime image initializes the MoonBit registry at image build time and seeds Codex skills from `https://github.com/moonbitlang/skills` into the container-local Codex home before every command. Runtime validation avoids `moon update` by default because MoonBit may fail while rotating its symbols directory across Docker mount boundaries.

If Mooncakes returns a transient network error such as a TLS handshake EOF during dependency fetch, the run fails cleanly, preserves the previous preview, records the artifact logs for operators, and returns a plain-English retry message to the user instead of exposing raw registry output as the main chat response.

## Control Plane Assets

Static control-plane shells live under `services/control-plane/assets` instead of MoonBit string literals. This includes:

- `platform/index.html` and `platform/style.css` for the root app shell
- `auth/github-callback/index.html` for the OAuth callback handoff page
- `preview-fallback/index.html` and `preview-fallback/styles.css` for generated previews that do not provide their own shell

These files are runtime assets. `moon build` builds both the Rabbita frontend bundle and the native control-plane executable through the workspace. The control plane does not run `moon` at startup; it serves the prebuilt frontend bundle from `_build/js/<profile>/build/mooncraft/web/web.js`. The supported local walkthrough runs from the repository root through `just serve`, which builds the workspace before starting the executable. The Docker image also builds the workspace at image build time before the entrypoint starts the prebuilt control-plane executable.

If you run a compiled `control-plane.exe` from another directory, keep `services/control-plane/assets` available under that working directory or the file-backed HTML pages will not render.

## Authentication

GitHub OAuth is the only supported sign-in provider. Set `MOONCRAFT_PUBLIC_BASE_URL`, `MOONCRAFT_GITHUB_CLIENT_ID`, and `MOONCRAFT_GITHUB_CLIENT_SECRET` before exposing the service. Users are created or linked from their verified GitHub email address, and sessions are stored in HTTP-only cookies.

Automated local tests can set `MOONCRAFT_ENABLE_DEV_AUTH=1` to enable `POST /api/dev/auth/session`. That endpoint creates a GitHub-shaped test session without external OAuth and must stay disabled outside local smoke runs.

## Preview Flow

Generated previews are executable-backed. The control plane builds the generated workspace, starts the built native executable with `<port>` as its first argument on a private local port, and exposes it through `/p/<preview_public_id>/`.

The generated app must keep `/api/health` available so the preview manager can verify readiness, and it must serve the user-facing app at `/`.

## Validation

Use these repository-level checks:

- `just check-user-project-deps` verifies required registry fetches locally and reports optional unpublished modules.
- `just check-user-project-deps-codex` runs the same fetch check inside the Codex runtime image and verifies that the image seeds Codex skills.
- `just smoke` covers the default project creation, fake Codex update, preview rebuild, deletion, and persistence flow.

Required Codex runtime configuration:

- `MOONCRAFT_CODEX_DOCKER_IMAGE`
- optional `MOONCRAFT_CODEX_CONTAINER_HOME` (defaults to `/root`)

The default runtime image is `docker.io/moonbitcloud/codex:codex-0.125.0-node24`. Override it through `MOONCRAFT_CODEX_DOCKER_IMAGE` when testing local images, PR images, rollbacks, or digest-pinned production deployments.

The runtime intentionally does not mount a host Codex home and users do not configure provider keys. Admins log in at `/admin/login` with `MOONCRAFT_ADMIN_TOKEN` and configure OpenRouter keys through `/admin`; the API stores the key value, returns only a masked hint, and the worker passes one leased key into the isolated Codex container only for the active run. OpenRouter is the only supported AI provider for generated-app runs. The admin model picker fetches the live OpenRouter text model catalog from `/api/admin/ai/models`, which proxies OpenRouter's `/api/v1/models` endpoint through an active saved key.

Use `just codex-config` to inspect the effective runtime configuration. Build the runtime image locally with `just build-codex-image` and publish the shared multi-arch runtime image with `just docker-codex-publish` after `docker login`.

Use `OPENROUTER_API_KEY=... just codex-smoke` from the repository root only when you intentionally want to spend real OpenRouter quota on an end-to-end Docker-backed build. The smoke script writes the key through the admin API after startup; it does not configure Mooncraft through service environment variables. Optional smoke overrides are `MOONCRAFT_CODEX_SMOKE_KEY_REF` and `MOONCRAFT_CODEX_SMOKE_MODEL`.
