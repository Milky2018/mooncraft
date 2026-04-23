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

Required Codex runtime configuration:

- `MOONBITCLOUD_CODEX_DOCKER_IMAGE`
- optional `MOONBITCLOUD_CODEX_HOME_HOST` (defaults to `$HOME/.codex`)
- optional `MOONBITCLOUD_CODEX_CONTAINER_HOME` (defaults to `/root`)
