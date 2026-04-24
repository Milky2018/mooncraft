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

Frontend-only templates can declare `preview.kind: "static"` in `template.json`. The control plane still builds the generated MoonBit workspace, copies the full public preview tree into `preview-dist/`, stages declared build artifacts, and launches a lightweight static preview process.

The static preview process is implemented by the control-plane executable:

```bash
moon run --manifest-path moon.work --target native services/control-plane -- \
  run-static-preview <port> <preview-dist-dir>
```

It serves:

- `/`: `index.html`
- arbitrary staged files such as `loader.js`, `app.js`, `styles.css`, and `app.wasm.txt`
- compatibility aliases `/app` -> `app.js` and `/styles` -> `styles.css`
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

Template HTML must reference preview assets with relative URLs, such as `href="styles.css"` and `src="app.js"`. Absolute URLs like `/styles` and `/app` bypass `/p/<preview_public_id>/` and load control-plane assets when the page is opened through the product preview route.

## Template Testing

Every official template should pass two smoke levels:

1. direct template smoke
2. control-plane product smoke

Direct template smoke validates the template workspace in isolation:

- run `moon clean`, `moon check`, and `moon build` inside `templates/<id>/workspace`
- stage a temporary preview directory from `public/` plus the template's declared build artifacts
- launch the preview runner directly
  - static templates: `services/control-plane -- run-static-preview <port> <preview-dist-dir>`
  - backend templates: run the built native preview executable
- verify the health endpoint and main asset paths are non-empty

Control-plane product smoke validates the real platform flow:

- start a temporary control plane with `MOONBITCLOUD_CODEX_FAKE_MODE=smoke`
- sign up or log in through the platform
- create a project with the target `template_id`
- create a run and wait for `Succeeded` plus a healthy preview
- verify the public preview route `/p/<preview_public_id>/` and the template-specific asset paths

The existing `just smoke` and `just smoke-running` cover the default project flow. Template-specific smokes should follow the same API path but set an explicit `template_id`.

Each template knowledge document should record:

- the direct preview staging command
- the product smoke flow
- the template-specific asset paths that must render through `/p/<preview_public_id>/`

Required Codex runtime configuration:

- `MOONBITCLOUD_CODEX_DOCKER_IMAGE`
- optional `MOONBITCLOUD_CODEX_HOME_HOST` (defaults to `$HOME/.codex`)
- optional `MOONBITCLOUD_CODEX_CONTAINER_HOME` (defaults to `/root`)
