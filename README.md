# MoonBit Cloud

MoonBit Cloud is a chat-first local prototype for building MoonBit apps through conversation. The user works in one browser page, talks to the agent, and sees a live preview. Source code exists in the workspace, but it stays hidden in the default flow.

## Current V1 Slice

The repo now implements the first real app-develop loop:

1. create a project
2. send a request in chat
3. update a generated MoonBit workspace
4. rebuild and restart the local preview
5. show plain-English feedback plus a live preview URL

This slice is intentionally narrow:

- desktop-first
- local single-user only
- no auth
- no deploy
- no code viewer
- one project rail, one chat workspace, one live preview panel

## Workspace Layout

```text
moonbitcloud/
├── moon.work
├── apps/
│   └── web/                  # Rabbita frontend
├── services/
│   └── control-plane/        # Mocket backend, SQLite, preview orchestration
├── packages/
│   └── sdk/                  # shared DTOs
├── docs/
├── knowledge/
└── data/                     # local runtime state, generated projects, SQLite
```

Generated user projects live under `data/projects/<project-id>/workspace/` and use a simple MoonBit full-stack shape:

- `frontend/`
- `backend/`
- `shared/`

## Implementation Notes

- `apps/web` renders the app-develop page with a left project rail, center chat workspace, and right preview panel.
- `services/control-plane` persists `projects`, `messages`, and `runs` in SQLite.
- Each successful run rebuilds the generated project and restarts a local preview server on a stable port.
- `packages/sdk` defines the shared request and response payloads used by the frontend and control plane.

The current `AgentGateway` is a local deterministic adapter that keeps the system runnable while preserving a clean seam for future Codex integration.

## Core Docs

- [Product PRD](/Users/zhengyu/Documents/projects/moonbitcloud/docs/prd.md)
- [Architecture](/Users/zhengyu/Documents/projects/moonbitcloud/docs/architecture.md)
- [Website Prototype](/Users/zhengyu/Documents/projects/moonbitcloud/docs/website-prototype.md)
- [Agent Docs Plan](/Users/zhengyu/Documents/projects/moonbitcloud/docs/agent-docs.md)
- [Issue Tracker](/Users/zhengyu/Documents/projects/moonbitcloud/docs/issue-tracker.md)

## Next Major Steps

1. replace the local `AgentGateway` adapter with real Codex-driven project editing
2. extract preview execution into a dedicated runner boundary
3. build the first durable multi-tenant todo template
4. connect the knowledge base to real template validation
