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

Each user project receives two Docker named volumes:

- `mooncraft-workspace-<project-id>` mounted at `/workspace`
- `mooncraft-home-<project-id>` mounted at `/home/mooncraft`

The `/workspace` volume is the authoritative generated source store. The `/home/mooncraft` volume is Runtime-private durable state. The old `data/projects` location is not a fallback source; startup removes that legacy scratch root instead of migrating or restoring from it.

Each generated project chooses its own structure. The control plane does not create or require `frontend/`, `backend/`, `shared/`, a MoonBit module, or any starter app files. Runtime Protocol v3 is the runtime contract: MoonCraft calls the Runtime Service for `POST /exec` and `GET /preview`.

New projects start from an empty `/workspace` volume. The selected Runtime provider owns all app setup, dependencies, code generation, and preview serving as part of satisfying the first user request.

## Current Runtime Flow

1. `POST /api/projects` creates project metadata and project-scoped Runtime Docker volumes.
2. `POST /api/projects/:id/runs` stores the user message, opens a run, and locks the project.
3. `RuntimeExecutor` ensures the project's Runtime Service container is running with the project volumes mounted.
4. The control plane calls Runtime Protocol v3 `POST /exec`; the Runtime updates `/workspace` and serves preview traffic from its fixed preview port.
5. The control plane marks the run as succeeded or failed and stores the latest preview target after Runtime `GET /preview` succeeds.
6. `apps/web` polls run status and refreshes project state.

## Persistence Model

SQLite stores:

- `users`
- `sessions`
- `oauth_accounts`
- `projects`
- `messages`
- `runs`
- `project_runtime_services`
- `project_workspace_snapshots`

The database is the durable product metadata layer. Generated project source code is stored in the project `/workspace` Docker volume, not in SQLite. `project_workspace_snapshots` records legacy archive metadata and smoke-test snapshots; it is not the authoritative source store for Runtime Protocol v3 projects. If the control plane cannot open or initialize SQLite, startup fails. After startup, the health endpoint returns unavailable if a basic database probe fails.

Important persisted fields include:

- user id
- session token hash
- project id
- project owner id
- preview public id
- display name
- workspace path for compatibility only
- current status
- current run id
- preview URL and port
- last error
- selected Runtime snapshot
- Runtime Service container and volume metadata

## Generated Workspace Boundary

The control plane owns only the Runtime boundary, not the app's source layout. Each project is bound to one Runtime snapshot at creation time. Runtime continuity is represented by the project-scoped Runtime Service container plus its `/workspace` and `/home/mooncraft` volumes. The control plane does not special-case official Runtime names or infer CLI-specific filesystem layout.

- new projects start from an empty `/workspace` volume
- normal user prompts are passed as task intent; MoonCraft app contract knowledge lives in the Runtime system layer
- the selected Runtime creates the requested real app and owns preview startup
- Runtime Protocol v3 `GET /preview` reports whether preview is ready
- source snapshots are not persisted after normal Runtime Protocol v3 runs
- existing legacy snapshots are imported into the `/workspace` volume on first Runtime Service creation

There are no official app templates, no template ids, and no template picker in this slice. Reusable examples should live in Runtime images, Runtime documentation, or external projects, not as platform-owned starter variants.

## Web Surface

The frontend is one desktop-first page:

- left rail: projects
- center panel: chat workspace
- header action: Preview button opens the generated app in a new tab when a healthy preview exists

Default UX constraints:

- code hidden
- no deploy
- no UI template picker
- plain-English errors only

## Agent Boundary

The agent layer is intentionally isolated behind the Runtime protocol and implemented by `RuntimeExecutor`.

The boundary is a Docker-backed Runtime Protocol v3 HTTP service. Runtime manifests contain only the image plus semantics-free env and secret bindings. The control plane does not know whether a Runtime uses an agent CLI, a hosted service, or a human handoff behind that HTTP API.

This separation matters because the frontend, persistence model, and preview lifecycle should not need to change when the real agent runtime lands.

## Preview Boundary

The Runtime Service owns preview process state. MoonCraft calls `GET /preview`; a successful response means preview is ready on the Runtime container's fixed preview port. The control plane proxies browser traffic through the project preview origin to that private Runtime port.

Production deployments should configure project-scoped preview origins through the deployment preview origin policy. Local development can still use the `/p/<preview_public_id>/` fallback when no preview origin template is configured.

## Why This Shape

This architecture is deliberately narrower than a Replit-style platform.

It is designed to validate:

- the app-develop page
- project persistence
- generated MoonBit workspaces
- repeatable live preview refresh
- a clean seam for real agent integration

The next structural change should be extracting preview execution into a dedicated runner service, not adding more frontend surface area.
