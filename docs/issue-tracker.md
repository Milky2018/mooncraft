# MoonBit Cloud Issue Tracker

Last updated: 2026-04-22

## Status Legend

- `TODO`: not started
- `IN_PROGRESS`: partially implemented
- `DONE`: implemented and verified locally

## Epics

| ID | Source | Problem | Status | Notes |
| --- | --- | --- | --- | --- |
| EPIC-001 | Product | Define the MVP as an agent-first MoonBit app platform, not a full Replit clone. | DONE | Reflected in `README.md`, `docs/prd.md`, and `docs/architecture.md`. |
| EPIC-002 | SDK | Freeze the eventual app runtime contract for request/response handlers and tenant context. | TODO | `packages/sdk` currently holds platform DTOs, not the user app handler contract yet. |
| EPIC-003 | Runtime | Extract preview execution into a dedicated runner boundary. | IN_PROGRESS | Preview rebuild and restart are real, but they still live inside `services/control-plane`. |
| EPIC-004 | UI | Build the chat-first app-develop page with projects, chat, and live preview. | DONE | Implemented in `apps/web` and served by `services/control-plane`. |
| EPIC-005 | Persistence | Persist projects, messages, runs, and preview metadata in a dev-friendly store. | DONE | Implemented with SQLite plus generated workspaces on disk. |
| EPIC-006 | Agent | Replace the local `AgentGateway` adapter with real Codex-driven editing. | TODO | The seam exists and is ready for a real integration. |
| EPIC-007 | Templates | Build the first durable multi-tenant todo template and its recipe-backed validation flow. | TODO | Recipe docs exist; runnable template does not. |

## Tasks

| ID | Source | Problem | Status | Notes |
| --- | --- | --- | --- | --- |
| TASK-001 | Docs | Create the initial product, architecture, and docs plan. | DONE | Core repo docs exist. |
| TASK-002 | Repo | Decide the initial workspace layout before writing application code. | DONE | The repo now uses `moon.work` with `apps/web`, `services/control-plane`, and `packages/sdk`. |
| TASK-003 | Runtime | Verify the first executable generated MoonBit project path. | DONE | Local project creation, rebuild, preview restart, and health checks now work. |
| TASK-004 | UI | Build the first app-develop page with project rail, chat workspace, and preview panel. | DONE | Verified locally through the control-plane HTTP flow. |
| TASK-005 | Docs | Author the first working multi-tenant todo template and matching recipe. | TODO | The recipe exists; the runnable template still needs implementation. |
| TASK-006 | Docs | Write the formal PRD from clarified product decisions. | DONE | `docs/prd.md` is updated to the implemented slice. |
| TASK-007 | Docs | Rework architecture docs around a chat-first, hidden-code product. | DONE | `docs/architecture.md` now reflects the real local architecture. |
| TASK-008 | Docs | Define the knowledge-base contract for agents. | DONE | `docs/agent-docs.md` and `knowledge/` exist. |
| TASK-009 | Docs | Define the first twenty templates and the initial template strategy. | DONE | `docs/templates-roadmap.md` exists. |
| TASK-010 | Docs | Create the initial `knowledge/` source documents for app model, handler contract, and tenant model. | DONE | Starter docs exist under `knowledge/`. |
| TASK-011 | Docs | Draft the canonical recipe for the multi-tenant todo API template. | DONE | `knowledge/recipes/build-a-todo-api.md` exists. |
| TASK-012 | Docs | Define the first website prototype for the app-develop page. | DONE | `docs/website-prototype.md` now matches the implemented page. |
| TASK-013 | Agent | Integrate real Codex project editing behind `AgentGateway`. | TODO | Preserve the current project/run/preview interfaces. |
| TASK-014 | Runtime | Move preview execution out of `services/control-plane` into a dedicated runner service. | TODO | Keep stable ports and health checks. |

## Current Work Queue

- `TASK-013`: replace the local `AgentGateway` adapter with a real Codex-backed implementation
- `TASK-014`: extract preview execution into a dedicated runner service
- `TASK-005`: build the first durable multi-tenant todo template
