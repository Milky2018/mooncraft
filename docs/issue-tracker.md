# MoonBit Cloud Issue Tracker

Last updated: 2026-04-22

## Status Legend

- `TODO`: not started
- `IN_PROGRESS`: currently being fixed
- `BLOCKED`: blocked by dependency or unresolved design choice
- `DONE`: fixed and verified locally

## Issues

| ID | Source | Problem | Status | Notes |
| --- | --- | --- | --- | --- |
| EPIC-001 | Product | Define the MVP as a MoonBit backend platform, not a full Replit clone. | DONE | Refined into an agent-first backend platform in `README.md` and `docs/prd.md`. |
| EPIC-002 | Architecture | Freeze the user runtime contract for request/response handlers. | TODO | Define `Request`, `Response`, `Context`, and tenant handling in `packages/sdk`. |
| EPIC-003 | Runtime | Prototype MoonBit compile-and-run flow inside a dedicated runner service. | TODO | Start with a hello-world handler and verify cold-start/log behavior. |
| EPIC-004 | UI | Build a simple chat-first web shell for projects, logs, preview, and deploy actions. | TODO | The main interaction should be conversation, not code editing. |
| EPIC-005 | Persistence | Store projects, revisions, builds, and deployments in a dev-friendly metadata layer. | TODO | Use SQLite first. |
| EPIC-006 | Knowledge Base | Create an agent-readable docs system tied to working templates. | TODO | Follow `docs/agent-docs.md`. |
| EPIC-007 | Deployment | Support immutable builds and shareable deployment URLs. | TODO | Local or staging only in first iteration. |
| EPIC-008 | Security | Preserve sandbox, secrets, and artifact boundaries without full hardening yet. | TODO | Implement interfaces now, hardening later. |
| EPIC-009 | Templates | Define and prioritize twenty reusable HTTP API templates. | TODO | Follow `docs/templates-roadmap.md`. |
| TASK-001 | Docs | Create the initial product, architecture, and docs plan. | DONE | Added `README.md`, `docs/architecture.md`, and `docs/agent-docs.md`. |
| TASK-002 | Repo | Decide the initial workspace layout before writing application code. | DONE | Created top-level directories for `apps`, `services`, `packages`, `knowledge`, and `examples`. |
| TASK-006 | Docs | Write the formal PRD from clarified product decisions. | DONE | Added `docs/prd.md`. |
| TASK-007 | Docs | Rework architecture docs around a chat-first, hidden-code product. | DONE | Rewrote `docs/architecture.md` and aligned `README.md`. |
| TASK-008 | Docs | Define the knowledge-base contract for agents. | DONE | Rewrote `docs/agent-docs.md`. |
| TASK-009 | Docs | Define the first twenty templates and the initial template strategy. | DONE | Added `docs/templates-roadmap.md`. |
| TASK-010 | Docs | Create the initial `knowledge/` source documents for app model, handler contract, and tenant model. | DONE | Added starter docs under `knowledge/concepts`, `knowledge/contracts`, and `knowledge/policies`. |
| TASK-003 | Runtime | Verify the first executable MoonBit request handler path. | TODO | Prefer a tiny `handle(req, ctx)` example before any framework work. |
| TASK-004 | UI | Scaffold the first web app with chat workspace, preview, and logs area. | TODO | Use mock data until runner integration exists. |
| TASK-005 | Docs | Author the first working template and its matching recipe doc. | TODO | Use the multi-tenant todo API as the seed. |

## Current Work Queue

- `TASK-003`: prototype the runner with one hello-world handler
- `TASK-004`: scaffold the first chat-first web shell with mock data
- `TASK-005`: write the first runnable multi-tenant todo template and recipe
