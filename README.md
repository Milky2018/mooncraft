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
- [EC2 Deployment Notes](/Users/zhengyu/Documents/projects/moonbitcloud/docs/deploy-ec2.md)
- [Agent Docs Plan](/Users/zhengyu/Documents/projects/moonbitcloud/docs/agent-docs.md)
- [Issue Tracker](/Users/zhengyu/Documents/projects/moonbitcloud/docs/issue-tracker.md)

## Docker

You can run the current single-instance control plane in Docker:

```bash
docker build -t moonbitcloud .
docker run --rm \
  -p 8080:8080 \
  -e MOONBITCLOUD_ADMIN_PASSWORD=change-me \
  -v moonbitcloud-data:/app/data \
  moonbitcloud
```

Then open `http://localhost:8080`.

Notes:

- the image includes the MoonBit toolchain because the control plane still rebuilds generated previews at runtime
- `MOONBITCLOUD_ADMIN_USERNAME` is optional and defaults to `admin`
- set `MOONBITCLOUD_BUILD_PROFILE=release` if you want the control plane to stage and run release artifacts inside the container

## Build Profiles

The local workflow supports both debug and release profiles:

```bash
just build
just build release
just serve
just serve release
```

`just serve release` sets `MOONBITCLOUD_BUILD_PROFILE=release`, so the control plane stages the platform bundle and generated preview bundles from the release build output directories.

## Next Major Steps

1. replace the local `AgentGateway` adapter with real Codex-driven project editing
2. extract preview execution into a dedicated runner boundary
3. build the first durable multi-tenant todo template
4. connect the knowledge base to real template validation
