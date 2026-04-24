# Architecture

## Goal

MoonBit Cloud v1 is a local app-develop system with three visible ideas:

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

`data/projects/<project-id>/workspace`

Each generated project uses a simple full-stack MoonBit shape:

- `frontend/`
- `backend/`
- `shared/`

This keeps the live preview tied to a real generated app instead of a fake demo panel.

## Current Runtime Flow

1. `POST /api/projects` creates project metadata, resolves a template manifest, and materializes the generated workspace from `templates/<id>/workspace`.
2. `POST /api/projects/:id/runs` stores the user message, opens a run, and locks the project.
3. `AgentGateway` updates the generated project.
4. `PreviewManager` rebuilds the generated app, copies preview assets, and restarts the configured preview runner on a stable local port.
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

The database is the metadata layer. Source code remains on disk in generated project workspaces.

Important persisted fields include:

- user id
- session token hash
- project id
- project owner id
- preview public id
- display name
- workspace path
- template id and version
- current status
- current run id
- preview URL and port
- last error
- thread id placeholder

## Template Boundary

Official templates live under `templates/<id>` as runnable MoonBit workspaces plus a `template.json` manifest. The control plane owns template selection, validation, and materialization. It should not define app source code as inline strings.

Each template manifest declares:

- id and version
- preview kind, package, and health-check contract
- required entrypoints
- editable files
- matching knowledge document

## Web Surface

The frontend is one desktop-first page:

- left rail: projects
- center panel: chat workspace
- right panel: preview iframe

Default UX constraints:

- code hidden
- no deploy
- no UI template picker yet
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

Backend templates run their generated native executable on a private local port. Static frontend templates use the control-plane `run-static-preview <port> <preview-dist-dir>` mode to serve staged files from `preview-dist/`, including assets such as `index.html`, `loader.js`, `app.js`, `styles.css`, `app.wasm.txt`, and health endpoints. In both cases, the browser only talks to the control plane.

## Why This Shape

This architecture is deliberately narrower than a Replit-style platform.

It is designed to validate:

- the app-develop page
- project persistence
- generated MoonBit workspaces
- repeatable live preview refresh
- a clean seam for real agent integration

The next structural change should be extracting preview execution into a dedicated runner service, not adding more frontend surface area.
