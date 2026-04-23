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
  - moon build frontend --target js
  - moon run backend --target native -- <port> <public_dir>
status: draft
---

# Summary

This is the default starter template used when a project is created without an explicit template selection.

# Structure

- `frontend/main.mbt`: small Rabbita preview shell
- `backend/main.mbt`: static asset server plus `/api/health`
- `shared/model.mbt`: app title and health payload

# Invariants

- Keep the project runnable through the standard preview runner.
- Preserve the `frontend`, `backend`, and `shared` package layout.
- Keep `/api/health` available for preview health checks.

# Supported Edits

- change the UI copy and layout
- extend the backend API
- expand the shared model

# Do Not Do This

- do not remove the backend health endpoint without updating the template contract
- do not rename the required package entrypoints without updating the template manifest
