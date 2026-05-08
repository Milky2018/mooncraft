# Mooncraft Issue Tracker

Last updated: 2026-04-29

## Status Legend

- `TODO`: not started
- `IN_PROGRESS`: currently being fixed
- `BLOCKED`: blocked by platform/public API limitations or external dependency constraints
- `DONE`: fixed and verified locally

## Epics

| ID | Source | Problem | Status | Notes |
| --- | --- | --- | --- | --- |
| EPIC-001 | Product | Define the MVP as an agent-first MoonBit app platform, not a full Replit clone. | DONE | Reflected in `README.md`, `docs/prd.md`, and `docs/architecture.md`. |
| EPIC-002 | SDK | Freeze the eventual app runtime contract for request/response handlers and tenant context. | TODO | `packages/sdk` currently holds platform DTOs, not the user app handler contract yet. |
| EPIC-003 | Runtime | Extract preview execution into a dedicated runner boundary. | IN_PROGRESS | Preview rebuild and restart are real, but they still live inside `services/control-plane`. |
| EPIC-004 | UI | Build the chat-first app-develop page with projects, chat, and live preview. | DONE | Implemented in `apps/web` and served by `services/control-plane`. |
| EPIC-005 | Persistence | Persist users, sessions, projects, messages, runs, preview metadata, and workspace snapshots in a dev-friendly store. | DONE | Implemented with SQLite; generated workspaces are runtime scratch. |
| EPIC-006 | Agent | Replace the local `AgentGateway` adapter with real Codex-driven editing. | IN_PROGRESS | Docker-backed Codex CLI runs, database-backed workspace snapshots, and persistent `codex_thread_id` sessions are wired in; executor hardening still needs follow-up. |
| EPIC-007 | Generated Apps | Keep the generated workspace bootstrap small, validated, and dependency-ready. | IN_PROGRESS | Runtime templates were removed; dependency fetch validation now covers approved modules. |
| EPIC-008 | Auth | Add multi-user platform auth, user-owned projects, and public preview tokens. | DONE | GitHub OAuth and cookie sessions are the only supported sign-in path; live credential verification is still required before public launch. |

## Tasks

| ID | Source | Problem | Status | Notes |
| --- | --- | --- | --- | --- |
| TASK-001 | Docs | Create the initial product, architecture, and docs plan. | DONE | Core repo docs exist. |
| TASK-002 | Repo | Decide the initial workspace layout before writing application code. | DONE | The repo now uses `moon.work` with `apps/web`, `services/control-plane`, and `packages/sdk`. |
| TASK-003 | Runtime | Verify the first executable generated MoonBit project path. | DONE | Local project creation, rebuild, preview restart, and health checks now work. |
| TASK-004 | UI | Build the first app-develop page with project rail, chat workspace, and preview panel. | DONE | Verified locally through the control-plane HTTP flow. |
| TASK-005 | Docs | Author the first working multi-tenant todo generated-app recipe. | TODO | The recipe exists; it should be updated against the generated workspace flow. |
| TASK-006 | Docs | Write the formal PRD from clarified product decisions. | DONE | `docs/prd.md` is updated to the implemented slice. |
| TASK-007 | Docs | Rework architecture docs around a chat-first, hidden-code product. | DONE | `docs/architecture.md` now reflects the real local architecture. |
| TASK-008 | Docs | Define the knowledge-base contract for agents. | DONE | `docs/agent-docs.md` and `knowledge/` exist. |
| TASK-009 | Runtime | Remove the platform-owned template strategy from v1. | DONE | Runtime template manifests and template checks were removed. |
| TASK-010 | Docs | Create the initial `knowledge/` source documents for app model, handler contract, and tenant model. | DONE | Starter docs exist under `knowledge/`. |
| TASK-011 | Docs | Draft the canonical recipe for a multi-tenant todo API generated app. | DONE | `knowledge/recipes/build-a-todo-api.md` exists. |
| TASK-012 | Docs | Define the first website prototype for the app-develop page. | DONE | `docs/website-prototype.md` now matches the implemented page. |
| TASK-013 | Agent | Integrate real Codex project editing behind `AgentGateway`. | IN_PROGRESS | Background worker mode, persistent Codex sessions, and validation-before-preview are implemented; Docker/runtime hardening remains. |
| TASK-014 | Runtime | Move preview execution out of `services/control-plane` into a dedicated runner service. | TODO | Keep stable ports and health checks. |
| TASK-015 | Auth | Add logout, cookie sessions, and owner-scoped project APIs. | DONE | Email/password signup and login were removed from the product surface. |
| TASK-016 | Auth | Add GitHub OAuth support for platform sign-in. | IN_PROGRESS | GitHub is now the only sign-in provider; the flow still needs live credential verification. |
| TASK-017 | Runtime | Replace predictable preview paths with opaque public preview tokens. | DONE | Preview URLs now use `/p/<preview_public_id>/`. |
| TASK-018 | Playwright simple project story | Fake Codex smoke mode leaks the full internal agent prompt into the assistant summary and preview iframe instead of showing only the user's request. | DONE | Fixed by extracting the user request from wrapped Codex prompts before fake-mode preview generation; verified with `moon test services/control-plane` and `just playwright-story`. |
| TASK-019 | Playwright simple project story | Frontend-visible success copy is inconsistent between fake-mode summaries and the cleaner backend/store success message. | DONE | Fake-mode and fallback completion paths now share `The app is updated and the preview is ready.`; verified with `moon test services/control-plane` and `just playwright-story`. |
| TASK-020 | Playwright simple project story | The Playwright story is still a manual artifact run instead of an official `just` target that owns server startup, browser setup, screenshots, and cleanup. | DONE | Added `scripts/playwright_simple_project_story.sh` and `just playwright-story`; artifacts are saved under ignored `output/playwright/`. |
| TASK-021 | Playwright simple project story | The browser story does not yet assert persistence after a full page refresh for project rail, chat history, and preview URL recovery. | DONE | The committed Playwright story reloads after two runs and asserts project rail, chat history, and preview URL persistence. |
| TASK-022 | Playwright simple project story | There is no browser coverage for failed agent/build/fetch paths preserving the last successful preview with plain-English errors. | DONE | Added `MOONCRAFT_CODEX_FAKE_FAIL_CONTAINS` and extended `just playwright-story` to assert failed-run copy plus last-preview preservation. |
| TASK-023 | Playwright simple project story | There is no browser-level real provider-backed Codex E2E; existing `codex-smoke` covers the HTTP API path only. | IN_PROGRESS | Added `scripts/playwright_real_agent_story.sh` and `just playwright-real-agent-story`; still needs an explicit live-provider run with an admin OpenRouter key before marking done. |

## Current Work Queue

- `TASK-013`: harden the Docker-backed Codex executor and persistent session flow
- `TASK-014`: extract preview execution into a dedicated runner service
- `TASK-016`: verify the GitHub OAuth happy path with real client credentials
- `TASK-005`: update the todo recipe for the generated workspace flow
- `TASK-023`: run and verify the opt-in real-agent Playwright story with live provider credentials
