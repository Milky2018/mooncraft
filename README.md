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
- local single-instance only
- email/password auth
- optional GitHub OAuth
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
└── data/                     # local SQLite state and disposable runtime scratch
```

Generated user projects are materialized as disposable scratch workspaces under `data/runtime/projects/<project-id>/workspace/`. The authoritative project source snapshot is stored in SQLite, not in that directory. Full-stack templates use a MoonBit workspace shape:

- `moon.work` at the workspace root
- `frontend/`
- `backend/`
- `shared/`

Each generated module owns its own `moon.mod.json`; generated workspace roots intentionally do not contain a root `moon.mod.json`.

Frontend-only templates can instead use a single MoonBit module with a root `moon.mod.json` and no `moon.work`.

## Implementation Notes

- `apps/web` renders the app-develop page with a left project rail, center chat workspace, and right preview panel.
- `services/control-plane` persists `users`, `sessions`, `oauth_accounts`, `projects`, `messages`, `runs`, and workspace snapshots in SQLite.
- Each successful run rebuilds the generated project and restarts a local preview server on a stable port.
- Static frontend previews run through `services/control-plane -- run-static-preview <port> <preview-dist-dir>` and can stage arbitrary assets, including wasm host files.
- Preview URLs are public opaque paths like `/p/<preview_public_id>/` and stay same-origin through the control plane.
- `packages/sdk` defines the shared request and response payloads used by the frontend and control plane.
- `AgentGateway` now launches Docker-backed Codex CLI runs asynchronously and persists one `codex_thread_id` per project so later messages can resume the same Codex session.

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
  -v moonbitcloud-data:/app/data \
  moonbitcloud
```

Then open `http://localhost:8080`.

Notes:

- the image includes the MoonBit toolchain because the control plane still rebuilds generated previews at runtime
- the image copies the full repo into `/app`, including `services/control-plane/assets`, which the control plane reads at runtime for file-backed HTML/CSS shells
- set `MOONBITCLOUD_BUILD_PROFILE=release` if you want the control plane to stage and run release artifacts inside the container
- Codex-backed editing also needs a separate Docker image that contains both `codex` and the MoonBit toolchain, exposed through:
  - `MOONBITCLOUD_CODEX_DOCKER_IMAGE`
  - optional `MOONBITCLOUD_CODEX_HOME_HOST` (defaults to `$HOME/.codex`)
  - optional `MOONBITCLOUD_CODEX_CONTAINER_HOME` (defaults to `/root`)
- the default Codex runtime image is `docker.io/moonbitcloud/codex:codex-0.123.0-node24`; override it through `.env` or `MOONBITCLOUD_CODEX_DOCKER_IMAGE`
- inspect the effective Codex runtime config with `just codex-config`
- build the Codex runtime image locally with `just build-codex-image` (defaults to the official tag for `linux/amd64`)
- the Codex runtime image must have an initialized MoonBit registry; the bundled Dockerfile runs `moon update`, and the control plane also runs `moon update` before Docker-backed validation
- publish the multi-arch Codex runtime image with `just docker-codex-publish` after `docker login` (defaults to `docker.io/moonbitcloud/codex:codex-0.123.0-node24` and `docker.io/moonbitcloud/codex:latest` for `linux/amd64,linux/arm64`)
- publish to another Docker Hub namespace with `just docker-codex-publish docker.io/<namespace>/codex`
- for shared environments, prefer `MOONBITCLOUD_CODEX_DOCKER_IMAGE=docker.io/moonbitcloud/codex:codex-0.123.0-node24` over `latest`
- run `just codex-smoke` to verify the real Docker-backed Codex CLI path by building a Todo List App end to end
- GitHub OAuth is optional and uses:
  - `MOONBITCLOUD_GITHUB_CLIENT_ID`
  - `MOONBITCLOUD_GITHUB_CLIENT_SECRET`
  - `MOONBITCLOUD_PUBLIC_BASE_URL`

## Build Profiles

The local workflow supports both debug and release profiles:

```bash
just build
just check-templates
just build release
just serve
just serve release
```

`just serve release` sets `MOONBITCLOUD_BUILD_PROFILE=release`, so the control plane stages the platform bundle and generated preview bundles from the release build output directories.

`just check-templates` validates every official template in a temporary sandbox by running target-less `moon check` and `moon build`. Use `just check-template <template_id>` for one template.

`just check-templates-codex` runs the same template workspaces inside the Codex runtime image with `moon update`, `moon check`, and `moon build`. Use it after changing the Codex image, template dependencies, or validation flow.

Control-plane HTML/CSS shells are runtime files under `services/control-plane/assets`. They are available in the documented local workflow because `just serve` and `moon run --manifest-path moon.work --target native services/control-plane` run from the repository root. `moon build` does not embed those assets into the native executable, so standalone runs must preserve that directory next to the runtime working directory.

## Next Major Steps

1. harden the Docker-backed Codex executor and runtime cleanup policy
2. extract preview execution into a dedicated runner boundary
3. build the first durable multi-tenant todo template
4. connect the knowledge base to real template validation
