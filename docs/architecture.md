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

Each user project is bound to a user-owned Project Source Repository. The repository is the authoritative persistent source store. GitHub is the current Project Source Host implementation; the domain model is intentionally source-host-neutral so MoonHub can replace it later.

MoonCraft does not create starter source files, require a fixed app layout, or persist generated source in Docker volumes. The selected Runtime provider owns all app setup, dependencies, code generation, commit/push behavior, and preview serving as part of satisfying user requests.

Runtime Protocol v3 is the HTTP contract between MoonCraft and a Runtime Service:

- `POST /init` gives the Runtime Service the Project Source Repository, a short-lived Project Source Credential, and Runtime Secrets.
- `POST /exec` starts a Run.
- `GET /runs/{run_id}` returns the authoritative Run Result.
- `GET /runs/{run_id}/events` returns progress events.
- `/preview/` serves the current project preview.

## Current Runtime Flow

1. `POST /api/projects` creates project metadata and an empty Project Source Repository.
2. `POST /api/projects/:id/runs` stores the user message, opens a run, and locks the project.
3. `RuntimeExecutor` ensures the project's Runtime Service is available through the configured Runtime Launcher.
4. The control plane calls Runtime Protocol v3 `POST /init` with source repository access and Runtime Secrets.
5. The control plane calls Runtime Protocol v3 `POST /exec`; the Runtime updates its workspace, commits and pushes source changes, and serves preview traffic from `/preview/`.
6. The control plane marks the run as succeeded only after the Runtime returns the final pushed Ready Source Commit.
7. `apps/web` polls run status and refreshes project state.

## Persistence Model

SQLite stores:

- `users`
- `sessions`
- `oauth_accounts`
- `projects`
- `messages`
- `runs`
- `project_runtime_services`
- `project_workspace_snapshots` for legacy data only

The database is the durable product metadata layer. Generated project source code is stored in the Project Source Repository, not in SQLite and not in Docker volumes. `project_workspace_snapshots` records legacy archive metadata and smoke-test snapshots only. If the control plane cannot open or initialize SQLite, startup fails. After startup, the health endpoint returns unavailable if a basic database probe fails.

Important persisted fields include:

- user id
- session token hash
- project id
- project owner id
- preview public id
- display name
- source repository identity and default branch
- current Ready Source Commit
- current status
- current run id
- preview URL
- last error
- selected Runtime snapshot
- Runtime Service launcher metadata

## Generated Workspace Boundary

The control plane owns only the Runtime boundary, not the app's source layout. Each project is bound to one Runtime snapshot at creation time. Runtime continuity is represented by the project-scoped Runtime Service plus the Project Source Repository. The control plane does not special-case official Runtime names, infer CLI-specific filesystem layout, or install agent account files into Runtime Home.

- new projects start from an empty Project Source Repository
- normal user prompts are passed as task intent; MoonCraft app contract knowledge lives in the Runtime system layer
- the selected Runtime creates the requested real app and owns preview startup
- Runtime Protocol v3 serves preview content from `/preview/`
- source changes are persisted by Runtime commit/push to the Project Source Repository
- existing legacy snapshots are migration data, not the current source persistence model

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

The boundary is Runtime Protocol v3 HTTP service. Runtime Config tells MoonCraft how to launch or locate that service; the first implementation supports a Docker Runtime Launcher. The control plane does not know whether a Runtime uses an agent CLI, a hosted service, or a human handoff behind that HTTP API.

This separation matters because the frontend, persistence model, and preview lifecycle should not need to change when the real agent runtime lands.

## Preview Boundary

The Runtime Service owns preview process state and serves preview content under `/preview/`. The control plane proxies browser traffic through the project preview origin to the Runtime Service `/preview/` subtree.

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
