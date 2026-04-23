---
title: Bootstrap App Template
summary: Canonical minimal MoonBit Cloud starter template
applies_to:
  - templates
  - bootstrap-app
editable_files:
  - templates/bootstrap-app/workspace/frontend
  - templates/bootstrap-app/workspace/backend
  - templates/bootstrap-app/workspace/shared
entrypoints:
  - frontend/main.mbt
  - backend/main.mbt
  - shared/model.mbt
validation:
  - moon check
  - moon build
  - _build/native/debug/build/moonbitcloud/generated-app/backend/backend.exe <port> <public_dir>
status: draft
---

# Summary

This is the default starter template used when a project is created without an explicit template selection.

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

# Supported Edits

- change the UI copy and layout
- extend the backend API
- expand the shared model

# Do Not Do This

- do not remove the backend health endpoint without updating the template contract
- do not rename the required package entrypoints without updating the template manifest
