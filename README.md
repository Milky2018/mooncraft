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
│   └── control-plane/        # Mocket backend, Morm persistence, preview orchestration
├── packages/
│   └── sdk/                  # shared DTOs
├── docs/
├── knowledge/
└── data/                     # local SQLite state and disposable runtime scratch
```

Generated user projects are materialized as disposable scratch workspaces under `data/runtime/projects/<project-id>/workspace/`. The authoritative project source snapshot is stored in SQLite, not in that directory. Every new project starts without an app scaffold; it only contains MoonBit Cloud metadata so snapshots and agent instructions have a stable anchor.

The first user prompt decides what the app becomes. Codex is instructed to use `moon new`, choose the MoonBit project shape that fits the request, keep root-level `moon fmt`, `moon check`, `moon test`, and `moon build` working, and maintain a root `moonbitcloud-preview.sh` script for live preview startup.

The platform no longer keeps official app templates or template manifests.

## Implementation Notes

- `apps/web` renders the app-develop page with a left project rail, center chat workspace, and right preview panel.
- `services/control-plane` persists `users`, `sessions`, `oauth_accounts`, `projects`, `messages`, `runs`, and workspace snapshots through Morm. It defaults to SQLite for dev/test and switches to PostgreSQL when `MOONBITCLOUD_DATABASE_URL` is set.
- Each successful run fetches approved MoonBit reference packages, rebuilds the generated project, and restarts a local preview server on a stable port.
- Generated previews run through the project's root `moonbitcloud-preview.sh` contract instead of a fixed platform-owned app layout.
- Preview URLs are public opaque paths like `/p/<preview_public_id>/` and stay same-origin through the control plane.
- `packages/sdk` defines the shared request and response payloads used by the frontend and control plane.
- `AgentGateway` runs Docker-backed Codex CLI work through a durable async worker process and persists one `codex_thread_id` per project so later messages can resume the same Codex session.
- Before validation and preview builds, the control plane runs `moon fetch` for the approved user-project modules. `moonbit-community/isomorphic` and `moonbit-community/selene` are currently optional fetches because they are not published in the registry yet.

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
just build-moonbitcloud-image
docker run --rm \
  -p 8080:8080 \
  -v moonbitcloud-data:/app/data \
  moonbitcloud:local
```

Then open `http://localhost:8080`.

Notes:

- local dev/test leaves `MOONBITCLOUD_DATABASE_URL` unset, so the control plane uses `data/control-plane/state-v2.sqlite`
- production should set `MOONBITCLOUD_DATABASE_URL` to a PostgreSQL URL; the included `docker-compose.yml` wires this to a colocated `postgres` service
- the image includes the MoonBit toolchain because the control plane still rebuilds generated previews at runtime
- the image copies the full repo into `/app`, including `services/control-plane/assets`, which the control plane reads at runtime for file-backed HTML/CSS shells
- set `MOONBITCLOUD_BUILD_PROFILE=release` if you want the control plane to stage and run release artifacts inside the container
- Codex-backed editing also needs a separate Docker image that contains both `codex` and the MoonBit toolchain, exposed through:
  - `MOONBITCLOUD_CODEX_DOCKER_IMAGE`
  - optional `MOONBITCLOUD_CODEX_MODEL` (defaults to `gpt-5.5`)
  - required `OPENAI_API_KEY`
  - optional `MOONBITCLOUD_CODEX_CONTAINER_HOME` (defaults to `/root`)
- the default Codex runtime image is `docker.io/moonbitcloud/codex:codex-0.125.0-node24`; override it through `.env` or `MOONBITCLOUD_CODEX_DOCKER_IMAGE`
- the Codex runtime image seeds skills from `https://github.com/moonbitlang/skills` into the container-local Codex home before each run
- MoonBit Cloud never mounts a host Codex home; every Codex run authenticates from `OPENAI_API_KEY` inside an isolated container
- the default Codex model is `gpt-5.5`; override it through `.env` or `MOONBITCLOUD_CODEX_MODEL` if your account needs a different accessible model
- inspect the effective Codex runtime config with `just codex-config`
- build the Codex runtime image locally with `just build-codex-image` (defaults to the official tag for `linux/amd64`)
- the Codex runtime image must have an initialized MoonBit registry; the bundled Dockerfile runs `moon update` at image build time so Docker-backed validation can run without mutating the registry at runtime
- publish the multi-arch Codex runtime image with `just docker-codex-publish` after `docker login` (defaults to `docker.io/moonbitcloud/codex:codex-0.125.0-node24` and `docker.io/moonbitcloud/codex:latest` for `linux/amd64,linux/arm64`)
- publish to another Docker Hub namespace with `just docker-codex-publish docker.io/<namespace>/codex`
- for shared environments, prefer `MOONBITCLOUD_CODEX_DOCKER_IMAGE=docker.io/moonbitcloud/codex:codex-0.125.0-node24` over `latest`
- run `just codex-smoke` to verify the real Docker-backed Codex CLI path by building a Todo List App end to end
- GitHub OAuth is optional and uses:
  - `MOONBITCLOUD_GITHUB_CLIENT_ID`
  - `MOONBITCLOUD_GITHUB_CLIENT_SECRET`
  - `MOONBITCLOUD_PUBLIC_BASE_URL`

### Docker Compose

For EC2-style deployment with PostgreSQL:

```bash
cp .env.example .env
# edit .env: set MOONBITCLOUD_PUBLIC_BASE_URL, MOONBITCLOUD_POSTGRES_PASSWORD,
# OPENAI_API_KEY, and optionally MOONBITCLOUD_IMAGE
docker compose pull
docker compose up -d
```

The compose file keeps the app stateless with durable data in Docker volumes:

- `moonbitcloud-postgres` for PostgreSQL
- `moonbitcloud-runtime` for runtime scratch files, staged bundles, and logs

## Build Profiles

The local workflow supports both debug and release profiles:

```bash
just build
just check-user-project-deps
just build release
just serve
just serve 8107
just serve release
just serve 8107 release
```

`just serve <port>` sets `MOONBITCLOUD_PORT` and `MOONBITCLOUD_PUBLIC_BASE_URL` for that local origin. `just serve release` sets `MOONBITCLOUD_BUILD_PROFILE=release`, so the control plane stages the platform bundle and generated preview bundles from the release build output directories.

`just check-user-project-deps` verifies that required generated-project registry modules can be fetched and reports optional modules that are not published yet.

`just check-user-project-deps-codex` runs the same fetch check inside the Codex runtime image and verifies that the image seeds Codex skills.

Control-plane HTML/CSS shells are runtime files under `services/control-plane/assets`. They are available in the documented local workflow because `just serve` and `moon -C . run --target native services/control-plane` run from the repository root. `moon build` does not embed those assets into the native executable, so standalone runs must preserve that directory next to the runtime working directory.

## Next Major Steps

1. harden the Docker-backed Codex executor and runtime cleanup policy
2. extract preview execution into a dedicated runner boundary
3. replace source snapshots in SQLite with external object storage or filesystem-backed archives
4. decide how unpublished MoonBit libraries should be mirrored for generated projects
