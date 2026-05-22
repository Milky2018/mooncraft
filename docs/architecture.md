# Architecture

## Goal

MoonCraft v1 is a local app-develop system with three visible ideas:

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

Each generated project chooses its own structure. The control plane does not create or require `frontend/`, `backend/`, `shared/`, a MoonBit module, or any starter app files. The project-owned `mooncraft-preview.sh` script is the runtime contract: MoonCraft starts it with a private preview port and requires the resulting preview to become reachable.

New projects start from an empty workspace snapshot. The selected Runtime provider owns all app setup, dependencies, code generation, and preview script creation as part of satisfying the first user request.

## Current Runtime Flow

1. `POST /api/projects` creates project metadata and saves an empty workspace as the first workspace snapshot.
2. `POST /api/projects/:id/runs` stores the user message, opens a run, and locks the project.
3. `RuntimeExecutor` runs the project's selected Runtime in the project workspace. For the first app turn, the Runtime receives an empty workspace and creates the requested previewable app.
4. `PreviewManager` runs the project-owned `mooncraft-preview.sh` on a stable local port and verifies the HTTP preview.
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
- selected Runtime snapshot
- Runtime session id

## Generated Workspace Boundary

The control plane owns only the Runtime boundary, not the app's source layout. Each project is bound to one Runtime snapshot at creation time. Runtime continuity is represented by the platform-owned `agent_session_id`, the Runtime-owned `runtime_session_id`, and the mounted agent session directory under `data/agent-sessions/<project-id>/<agent-session-id>`. The control plane does not special-case official Runtime names or infer CLI-specific filesystem layout.

- new projects start from an empty workspace snapshot
- normal user prompts are passed as task intent; MoonCraft app contract knowledge lives in the Runtime system layer
- the selected Runtime creates the requested real app and its preview startup script
- `mooncraft-preview.sh <port>` must start the live preview
- `mooncraft-preview.sh` receives the preview port as its first CLI argument, starts the app server, keeps the preview process in the foreground, and serves `/`
- `/api/health` is preferred for readiness, while `/` is accepted as a fallback for browser-only/static previews
- source snapshots are persisted after creation and after successful agent edits

There are no official app templates, no template ids, and no template picker in this slice. Reusable examples should live in Runtime images, Runtime documentation, or external projects, not as platform-owned starter variants.

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

The agent layer is intentionally isolated behind the Runtime protocol and implemented by `RuntimeExecutor`.

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
- preview script startup
- health checks

The current preview path is same-origin and exposed through:

- stored `preview.url` values like `/p/<preview_public_id>/`
- `ALL /p/:preview_public_id/*` reverse proxy handling in the control plane

Generated projects run their own `mooncraft-preview.sh` on a private local port. The control plane passes `<port>` as the first argument, proxies browser traffic through `/p/<preview_public_id>/`, and health-checks `/api/health` with `/` as a fallback.

Because the public preview is mounted under a path prefix, generated browser apps must be path-prefix compatible. HTML assets, module imports, CSS URLs, and frontend API calls should use document-relative URLs such as `./frontend.js` and `./api/metrics`, not root-absolute URLs such as `/frontend.js` or `/api/metrics`.

## Why This Shape

This architecture is deliberately narrower than a Replit-style platform.

It is designed to validate:

- the app-develop page
- project persistence
- generated MoonBit workspaces
- repeatable live preview refresh
- a clean seam for real agent integration

The next structural change should be extracting preview execution into a dedicated runner service, not adding more frontend surface area.
