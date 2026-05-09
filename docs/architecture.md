# Architecture

## Goal

Mooncraft v1 is a local app-develop system with three visible ideas:

- projects
- chat
- live preview

The user should not need to read code. The platform should persist state, update a generated MoonBit workspace, and keep a preview running.

## Top-Level Workspace

The repo is one MoonBit workspace with three modules:

- `apps/web`: Rabbita frontend for the app-develop page
- `services/control-plane`: Mocket backend, SQLite persistence, preview orchestration
- `packages/sdk`: shared DTOs for frontend and backend

## Generated Project Shape

Each user project is created under:

`data/runtime/projects/<project-id>/workspace`

That directory is runtime scratch, not durable storage. The control plane keeps the authoritative workspace source snapshot in SQLite and hydrates it into scratch paths for agent runs and preview rebuilds.
The old `data/projects` location is not a fallback source; startup removes that legacy scratch root instead of migrating or restoring from it.

Each generated project chooses its own MoonBit structure. The control plane does not create or require `frontend/`, `backend/`, or `shared/` directories; it only requires valid root-level MoonBit commands and one native runnable app that accepts the preview port as its first CLI argument.

New projects start from the minimal native Mocket seed in `examples/project-seeds/native-mocket`. That seed is not a user-facing template; it is a valid preview substrate that the selected agent must replace with the requested app.

This keeps the live preview tied to a real generated app instead of a fake demo panel without forcing every app into one final scaffold.

## Current Runtime Flow

1. `POST /api/projects` creates project metadata and materializes the minimal native MoonBit seed workspace.
2. `POST /api/projects/:id/runs` stores the user message, opens a run, and locks the project.
3. `AgentGateway` runs the project's selected agent in the project workspace. For the first app turn, the agent is instructed to replace the starter substrate with the requested real app.
4. `PreviewManager` fetches approved MoonBit modules, rebuilds the generated app, and starts the built native executable on a stable local port.
5. The control plane marks the run as succeeded or failed and stores the latest preview target.
6. `apps/web` polls run status and refreshes project state.

## Persistence Model

SQLite stores:

- `users`
- `sessions`
- `oauth_accounts`
- `projects`
- `messages`
- `runs`
- `project_workspace_snapshots`

The database is the durable state layer. Generated project source code is stored as a workspace snapshot archive in SQLite; filesystem workspaces under `data/runtime/` are disposable caches and execution directories. If the control plane cannot open or initialize SQLite, startup fails. After startup, the health endpoint returns unavailable if a basic database probe fails.

Important persisted fields include:

- user id
- session token hash
- project id
- project owner id
- preview public id
- display name
- workspace path for compatibility only; runtime code derives scratch paths from project id
- current status
- current run id
- preview URL and port
- last error
- selected agent CLI
- Codex thread id, for Codex projects only

## Generated Workspace Boundary

The control plane owns only the runtime boundary, not the app's source layout. Each project is bound to one agent CLI at creation time. Codex continuity is split deliberately: the database stores the project's `codex_thread_id`, while the matching Codex CLI state lives in the app data volume under `data/codex-sessions/<project-id>/.codex` and is mounted into the disposable Docker container as `CODEX_HOME`. Claude Code and Kimi Code do not persist CLI session state; each turn receives the hydrated workspace snapshot and the current prompt.

- new projects start from the minimal native Mocket seed, not an official app template
- the selected agent replaces the starter app with the requested real app
- root-level `moon fmt`, `moon check`, `moon test`, and `moon build` must remain valid
- the generated app must build one native runnable executable
- the executable receives the preview port as its first CLI argument, starts the app server, serves `/`, and returns success from `/api/health`
- source snapshots are persisted after creation and after successful agent edits

There are no official app templates, no template ids, and no template picker in this slice. The seed exists only to make the workspace immediately buildable and previewable. Reusable examples should live in documentation or external MoonBit projects, not as platform-owned scaffold variants.

## Web Surface

The frontend is one desktop-first page:

- left rail: projects
- center panel: chat workspace
- right panel: preview iframe

Default UX constraints:

- code hidden
- no deploy
- no UI template picker
- plain-English errors only

## Agent Boundary

The agent layer is intentionally isolated behind `AgentGateway`.

Current state:

- the boundary is real
- the implementation uses Docker-backed agent CLI workers
- supported agent CLIs are Codex, Claude Code, and Kimi Code
- all agent CLIs receive OpenRouter credentials from the admin-managed key pool

Future state:

- harden the Docker executor while keeping the same product boundary

This separation matters because the frontend, persistence model, and preview lifecycle should not need to change when the real agent runtime lands.

## Preview Boundary

`PreviewManager` owns:

- stable port allocation
- old preview shutdown
- rebuild and restart
- health checks

The current preview path is same-origin and exposed through:

- stored `preview.url` values like `/p/<preview_public_id>/`
- `ALL /p/:preview_public_id/*` reverse proxy handling in the control plane

Generated projects run their built native executable on a private local port. The control plane builds the workspace, finds the native executable under `_build/native/<profile>/build`, runs it with `<port>` as the first argument, proxies browser traffic through `/p/<preview_public_id>/`, and health-checks `/api/health`.

## Why This Shape

This architecture is deliberately narrower than a Replit-style platform.

It is designed to validate:

- the app-develop page
- project persistence
- generated MoonBit workspaces
- repeatable live preview refresh
- a clean seam for real agent integration

The next structural change should be extracting preview execution into a dedicated runner service, not adding more frontend surface area.
