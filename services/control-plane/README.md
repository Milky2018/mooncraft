# Control Plane

This module is the local backend for the current MoonBit Cloud prototype.

Responsibilities:

- persist projects, messages, and runs in SQLite
- materialize template-backed MoonBit workspaces under `data/projects/<id>/workspace`
- serve the app-develop HTTP API
- serve the main workspace page and platform bundle
- launch asynchronous Codex workers against generated workspaces
- rebuild and restart local previews
- store preview URLs and last-known run state

Official templates live under `templates/<id>`. Each template has a `template.json` manifest plus a runnable `workspace/` directory. Project rows persist `template_id` and `template_version` so preview rebuilds can use the originating template contract.

The current `AgentGateway` uses Docker-backed Codex CLI runs. Each project keeps one persistent `codex_thread_id`, and each new chat message spawns a background worker that resumes that session, validates the workspace with `moon fmt`, `moon check`, and `moon test`, then refreshes the preview.

## Static Preview Mode

Frontend-only templates can declare `preview.kind: "static"` in `template.json`. The control plane still builds the generated MoonBit workspace, copies the public preview shell plus the JS bundle into `preview-dist/`, and launches a lightweight static preview process.

The static preview process is implemented by the control-plane executable:

```bash
moon run --manifest-path moon.work --target native services/control-plane -- \
  run-static-preview <port> <preview-dist-dir>
```

It serves:

- `/`: `index.html`
- `/app`: generated JavaScript bundle
- `/styles`: generated stylesheet
- `/__health` and `/api/health`: JSON health response

To test the `frontend-dashboard` template directly:

```bash
cd templates/frontend-dashboard/workspace
moon clean
moon check
moon build

preview_dir="$(mktemp -d)"
cp public/index.html "$preview_dir/index.html"
cp public/styles.css "$preview_dir/styles.css"
cp _build/js/debug/build/frontend-dashboard.js "$preview_dir/app.js"

cd ../../..
moon run --manifest-path moon.work --target native services/control-plane -- \
  run-static-preview 19301 "$preview_dir"
```

Then open `http://127.0.0.1:19301/` or check it with:

```bash
curl -fsS http://127.0.0.1:19301/__health
curl -fsS http://127.0.0.1:19301/app | wc -c
```

Template HTML must reference preview assets with relative URLs, such as `href="styles"` and `src="app"`. Absolute URLs like `/styles` and `/app` bypass `/p/<preview_public_id>/` and load control-plane assets when the page is opened through the product preview route.

Required Codex runtime configuration:

- `MOONBITCLOUD_CODEX_DOCKER_IMAGE`
- optional `MOONBITCLOUD_CODEX_HOME_HOST` (defaults to `$HOME/.codex`)
- optional `MOONBITCLOUD_CODEX_CONTAINER_HOME` (defaults to `/root`)

The default runtime image is `docker.io/moonbitcloud/codex:codex-0.123.0-node24`. Override it through `.env` or `MOONBITCLOUD_CODEX_DOCKER_IMAGE` when testing local images, PR images, rollbacks, or digest-pinned production deployments.

Use `just codex-config` to inspect the effective runtime configuration. Build the runtime image locally with `just build-codex-image` (defaults to the official tag for `linux/amd64`).

Publish the shared multi-arch runtime image with `just docker-codex-publish` after `docker login`. By default it pushes `docker.io/moonbitcloud/codex:codex-0.123.0-node24` and `docker.io/moonbitcloud/codex:latest` for `linux/amd64,linux/arm64`. Shared environments should set `MOONBITCLOUD_CODEX_DOCKER_IMAGE=docker.io/moonbitcloud/codex:codex-0.123.0-node24` instead of relying on `latest`.

To publish under another Docker Hub namespace, pass the repository explicitly: `just docker-codex-publish docker.io/<namespace>/codex`.

Use `just codex-smoke` from the repository root to run an end-to-end Todo List App build through the real Docker-backed Codex CLI path.
