# Control Plane

This module is the local backend for the current MoonCraft prototype.

Responsibilities:

- persist users, sessions, projects, messages, runs, and workspace source snapshots
- initialize the MoonBit workspace under `data/runtime/projects/<id>/workspace`
- serve the app-develop HTTP API
- serve the main workspace page, frontend bundles, and web-owned static shells
- authenticate users through GitHub OAuth and cookie sessions
- launch durable asynchronous agent workers against generated workspaces
- fetch approved MoonBit registry modules before validation and preview startup
- rebuild and restart local previews
- store preview URLs and last-known run state

The platform no longer uses official app templates. Project rows do not carry template ids, and there is no template picker. Project creation runs `moon new` deterministically and saves that plain MoonBit module as the first workspace snapshot. The first user prompt decides what the app becomes; the selected agent must set `preferred-target` in `moon.mod.json` and create `mooncraft-preview.sh` as part of the requested app rather than preserve any platform-owned starter app.

The current `AgentGateway` uses Docker-backed agent CLI runs. Projects are bound to one agent CLI at creation time: Codex, Claude Code, or Kimi Code. Codex projects keep one persistent `codex_thread_id` in the database and one platform-owned Codex home under `data/codex-sessions/<project-id>/.codex`; Claude Code and Kimi Code are stateless per turn and rely on the persisted workspace snapshot. Each new chat message starts a detached worker process through `moonbitlang/async/process`, runs the selected agent in the disposable container, validates the workspace with dependency fetches plus hard `moon fmt`, `moon check`, `moon build`, and release-run probing, records `moon test` as a soft signal, refreshes the preview, then runs a browser preview audit when Playwright is available. On startup, stale `Running` runs are marked failed so the project is retryable after a crash or restart.

Workspace directories are no longer durable state. The control plane saves the latest source archive in SQLite after initial workspace generation and after agent edits. Each run hydrates that database snapshot into an isolated runtime workspace before starting the selected agent, then restores the local preview cache from the saved snapshot.

Codex session directories are durable app data, not host user state. MoonCraft does not mount a developer's local Codex home, and AI credentials are leased from the admin-managed OpenRouter key pool for one active run at a time. Deleting a project removes its workspace cache, artifacts, database rows, and `data/codex-sessions/<project-id>`.

The legacy `data/projects` workspace root is cleaned at startup. It is not used as a restore fallback, because generated files must come from the database snapshot or be treated as unavailable.

SQLite is a required dependency for the control plane. If the database cannot be opened or schema initialization fails, the service exits during startup. The health endpoint also checks database availability and returns unavailable when the probe fails.

## Dependency Fetches

Before agent runs, validation, and preview startup, generated user projects run `moon fetch --no-update` for the unpinned modules listed in `config/user_project_reference_modules.txt`. The MoonBit registry resolves the concrete versions at fetch time.

For real Docker-backed runs, the MoonCraft agent runtime image initializes the MoonBit registry at image build time, installs the supported agent CLIs, seeds MoonBit skills from `https://github.com/moonbitlang/skills`, installs MoonCraft project templates from `https://github.com/moonbitlang/mooncraft-templates.git` under `/opt/mooncraft/templates`, and installs compact MoonCraft runtime system instructions before every command. Normal user prompts are not wrapped with the generated-app contract; that project-aware contract lives in the runtime system layer. Runtime validation avoids `moon update` by default because MoonBit may fail while rotating its symbols directory across Docker mount boundaries.

Validation does not special-case browser-only JavaScript tests. `moon test` is executed and logged, but failures do not block preview refresh. The hard validation path is `moon fmt`, `moon check`, `moon build`, and a bounded `moon run --release <main-package>` probe; if a long-running server stays alive during the probe window, MoonCraft treats that as a valid release process.

If Mooncakes returns a transient network error such as a TLS handshake EOF during dependency fetch, the run fails cleanly, preserves the previous preview, records the artifact logs for operators, and returns a plain-English retry message to the user instead of exposing raw registry output as the main chat response.

## Web Assets

Frontend-owned static files live under `apps/web/public`, which mirrors public URL paths. This includes:

- `control-plane-assets/platform/index.html` and `control-plane-assets/platform/style.css` for the root app shell
- `control-plane-assets/admin/index.html` for the admin app shell
- `control-plane-assets/admin-login/index.html` for the admin session form
- `control-plane-assets/auth/github-callback/index.html` for the OAuth callback handoff page
- `control-plane-assets/preview-fallback/index.html` and `control-plane-assets/preview-fallback/styles.css` for generated previews that do not provide their own shell
- `control-plane-assets/smoke-preview/index.html` for fake-agent preview smoke runs
- `assets/logo.svg`, `assets/logo.png`, and `assets/factory.webp` for public web app imagery

These files are runtime assets owned by `apps/web`, not control-plane source. `moon build` builds both the Rabbita frontend bundle and the native control-plane executable through the workspace. The control plane does not run `moon` at startup; it serves the prebuilt frontend bundle from `_build/js/<profile>/build/mooncraft/web/web.js`. Project creation does require the MoonBit CLI because MoonCraft initializes each generated workspace with `moon new` before saving the first workspace snapshot. The supported local walkthrough runs from the repository root through `just serve`, which builds the workspace before starting the executable. The Docker app image installs the MoonBit CLI, builds the workspace at image build time, and keeps `moon` available for project initialization after startup.

If you run a compiled `control-plane.exe` from another directory, keep `apps/web/public` available under that working directory or the file-backed HTML pages will not render.

## Authentication

GitHub OAuth is the only supported sign-in provider. Set `MOONCRAFT_PUBLIC_BASE_URL`, `MOONCRAFT_GITHUB_CLIENT_ID`, and `MOONCRAFT_GITHUB_CLIENT_SECRET` before exposing the service. Users are created or linked from their verified GitHub email address, and sessions are stored in HTTP-only cookies.

Automated local tests can set `MOONCRAFT_ENABLE_DEV_AUTH=1` to enable `POST /api/dev/auth/session`. That endpoint creates a GitHub-shaped test session without external OAuth and must stay disabled outside local smoke runs.

## Preview Flow

Generated previews are script-backed. The control plane starts the root `mooncraft-preview.sh` script with `<port>` as its first argument on a private local port and exposes the result through `/p/<preview_public_id>/`.

The generated app must serve the user-facing app at `/`. `/api/health` is the preferred readiness endpoint, and `/` is accepted as a fallback for static or browser-only previews. If the preview script is missing, exits too early, or does not become reachable, MoonCraft asks the agent to repair the preview setup.

Preview process state is not durable. When an existing project is opened or a stored preview URL is requested, MoonCraft verifies the private preview port. If the process is gone, it restores the saved workspace snapshot and restarts `mooncraft-preview.sh` without running the AI agent or changing project code. If the saved snapshot cannot restart, the project preview is marked unhealthy so the UI does not keep showing a stale healthy iframe.

After HTTP readiness succeeds, MoonCraft optionally runs `scripts/preview_audit.mjs` with Playwright against the private local preview URL. The audit fails on browser page errors, console errors, or non-favicon HTTP errors. When it fails, MoonCraft sends the audit output back to the selected agent for a bounded repair loop before marking the run successful. Set `MOONCRAFT_PREVIEW_AUDIT=0` to disable it, or set `MOONCRAFT_PREVIEW_AUDIT_REPAIR_ATTEMPTS` to tune the repair bound.

## Validation

Use these repository-level checks:

- `just check-user-project-deps` verifies required registry fetches locally and reports optional unpublished modules.
- `just check-user-project-deps-agent-runtime` runs the same fetch check inside the agent runtime image and verifies that the image seeds MoonBit skills.
- `just smoke` covers the default project creation, fake Codex update, preview rebuild, deletion, and persistence flow.

Required agent runtime configuration:

- `MOONCRAFT_AGENT_RUNTIME_IMAGE`
- optional `MOONCRAFT_CODEX_CONTAINER_HOME` (defaults to `/root`)

The default runtime image is stored in `config/agent_runtime_image.txt` and is currently `docker.io/moonbitcloud/mooncraft-agent-runtime:0.1.0`. Override it through `MOONCRAFT_AGENT_RUNTIME_IMAGE` when testing local images, PR images, rollbacks, or digest-pinned production deployments. `MOONCRAFT_CODEX_DOCKER_IMAGE` remains a temporary compatibility fallback for older deployments.

The runtime intentionally does not mount a host AI tool home and users do not configure provider keys. Admins log in at `/admin/login` with `MOONCRAFT_ADMIN_TOKEN` and use `/admin` to inspect users, manage projects, inspect recent runs, and configure OpenRouter keys. The key API stores the key value, returns only a masked hint, and the worker passes one leased key into the isolated agent runtime container only for the active run. OpenRouter is the only supported AI provider for generated-app runs.

Use `just agent-runtime-config` to inspect the effective runtime configuration. Build the runtime image locally with `just build-agent-runtime-image <repository> <version> <platform>` and publish the shared multi-arch runtime image with `just docker-agent-runtime-publish <repository> <version> <platforms>` after `docker login`.

Use `OPENROUTER_API_KEY=... just agent-smoke` from the repository root only when you intentionally want to spend real OpenRouter quota on an end-to-end Docker-backed build. The smoke script writes the key through the admin API after startup; it does not configure MoonCraft through service environment variables. Optional smoke overrides are `MOONCRAFT_AGENT_SMOKE_KEY_REF` and `MOONCRAFT_AGENT_SMOKE_MODEL`. The old `just codex-smoke` recipe remains as a compatibility alias.
