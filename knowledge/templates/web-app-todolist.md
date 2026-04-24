---
title: Web App Todo List Template
summary: Canonical MoonBit Cloud todo-list web app template
applies_to:
  - templates
  - web-app-todolist
editable_files:
  - templates/web-app-todolist/workspace/frontend
  - templates/web-app-todolist/workspace/backend
  - templates/web-app-todolist/workspace/shared
entrypoints:
  - frontend/main.mbt
  - backend/main.mbt
  - shared/model.mbt
validation:
  - moon check
  - moon build
  - _build/native/debug/build/moonbitcloud/generated-app/backend/backend.exe <port> <public_dir>
  - run control-plane smoke with template_id web-app-todolist
status: draft
---

# Summary

This is the default todo-list web app template used when a project is created without an explicit template selection.

# Structure

- `frontend/main.mbt`: small Rabbita preview shell
- `backend/main.mbt`: static asset server plus `/api/health`
- `shared/model.mbt`: app title and health payload
- `moon.work`: workspace root that joins the `frontend`, `backend`, and `shared` modules
- each module has its own `moon.mod.json`; the workspace root must not have one

# Invariants

- Keep the project runnable through the standard preview runner.
- Preserve the `frontend`, `backend`, and `shared` package layout.
- Keep `/api/health` available for preview health checks.
- Template materialization must copy source files only; MoonBit build/cache outputs such as `_build` and `.mooncakes` are ignored.
- Run preview servers from the built native executable, not `moon run`, so the backend is not served through `tcc -run`.
- Run `moon check` and `moon build` once at the workspace root without target flags; module `preferred-target` fields select the appropriate backend.

# Product Smoke

```bash
cd /Users/zhengyu/.codex/worktrees/6b76/moonbitcloud
MOONBITCLOUD_CODEX_FAKE_MODE=smoke MOONBITCLOUD_PORT=19312 \
  moon run --manifest-path moon.work --target native services/control-plane
```

Then:

- open `http://127.0.0.1:19312/`
- sign up or log in
- create a project with `template_id: "web-app-todolist"` or omit `template_id` and use the default
- create one run and wait for a healthy preview
- verify `/p/<preview_public_id>/api/health`, `/p/<preview_public_id>/app`, and `/p/<preview_public_id>/styles`

# Supported Edits

- change the UI copy and layout
- extend the backend API
- expand the shared model

# Do Not Do This

- do not remove the backend health endpoint without updating the template contract
- do not rename the required package entrypoints without updating the template manifest
