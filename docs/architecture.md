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

That directory is runtime scratch, not durable storage. The control plane keeps the authoritative workspace source snapshot in SQLite and hydrates it into scratch paths for Codex runs and preview rebuilds.
The old `data/projects` location is not a fallback source; startup removes that legacy scratch root instead of migrating or restoring from it.

Each generated project chooses its own MoonBit structure. The control plane does not create or require `frontend/`, `backend/`, or `shared/` directories; it only requires a root preview script and valid root-level MoonBit commands.

This keeps the live preview tied to a real generated app instead of a fake demo panel without forcing every app into one scaffold.

## Current Runtime Flow

1. `POST /api/projects` creates project metadata and writes only Mooncraft workspace metadata.
2. `POST /api/projects/:id/runs` stores the user message, opens a run, and locks the project.
3. `AgentGateway` runs Codex in the project workspace. For the first app turn, Codex is instructed to create the real MoonBit project with `moon new`.
4. `PreviewManager` fetches approved MoonBit modules, rebuilds the generated app, and starts the root preview script on a stable local port.
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
- thread id placeholder

## Generated Workspace Boundary

The control plane owns only the runtime boundary, not the app's source layout:

- new projects start without a platform-owned app scaffold
- Codex creates the real MoonBit project with `moon new`
- root-level `moon fmt`, `moon check`, `moon test`, and `moon build` must remain valid
- `mooncraft-preview.sh` must exist at the workspace root
- the preview script receives `<port> <build-profile>`, starts the app server, serves `/`, and returns success from `/api/health`
- source snapshots are persisted after creation and after successful Codex edits

There are no official app templates, no template ids, and no template picker in this slice. Reusable examples should live in documentation or external MoonBit projects, not as platform-owned scaffold variants.

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
- the implementation uses Docker-backed Codex CLI workers

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

Generated projects run their preview script on a private local port. The control plane builds the workspace, runs `./mooncraft-preview.sh <port> <build-profile>`, proxies browser traffic through `/p/<preview_public_id>/`, and health-checks `/api/health`.

## Why This Shape

This architecture is deliberately narrower than a Replit-style platform.

It is designed to validate:

- the app-develop page
- project persistence
- generated MoonBit workspaces
- repeatable live preview refresh
- a clean seam for real agent integration

The next structural change should be extracting preview execution into a dedicated runner service, not adding more frontend surface area.
