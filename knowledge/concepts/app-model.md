---
title: App Model
summary: The core mental model for apps built on MoonCraft
applies_to:
  - product-model
  - chat-first
  - http-api
editable_files: []
entrypoints: []
validation: []
status: draft
---

# When To Use

Use this document when deciding how a MoonCraft app should be structured or when choosing between multiple implementation shapes.

# Model Summary

MoonCraft apps are generated and modified through agent interaction. The end user does not manage the source code directly. The app should therefore stay predictable and easy for the agent to reason about.

The first platform model is:

- HTTP API only
- request/response execution
- local single-instance multi-user prototype
- platform-level cookie sessions for project ownership
- public preview access through opaque preview URLs
- durable storage when required
- explicit tenant scoping when required

# Invariants

- The main user interface is chat, not a code editor.
- Platform users own projects explicitly; project access must stay owner-scoped.
- The app must remain runnable through the platform runner.
- The app should use the MoonBit project structure that fits the request; MoonCraft must not assume every app has `frontend/`, `backend/`, and `shared/` directories.
- The workspace root must keep `moon fmt`, `moon check`, and `moon build` valid. Browser-only JavaScript apps must also pass `moon test --build-only`; other apps must pass `moon test`.
- The workspace root must provide `mooncraft-preview.sh` so MoonCraft can start the live preview.
- Public previews must stay tied to opaque preview identifiers, not predictable project ids.
- Tenant-aware apps must scope data explicitly.
- Product-facing complexity should stay hidden from the end user.

# Recommended Shape

Prefer a small set of predictable modules:

- request entrypoint
- route handling
- domain logic
- persistence layer
- shared request/response types

Avoid highly dynamic or ad hoc project shapes in v1.

# Validation

- Confirm the app still exposes the expected handler entrypoint.
- Confirm the runner can build and run the app.
- Confirm the generated workspace remains understandable to the agent.

# Related Docs

- [HTTP Handler](../contracts/http-handler.md)
- [Tenant Model](../contracts/tenant-model.md)
