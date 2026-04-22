---
title: App Model
summary: The core mental model for apps built on MoonBit Cloud
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

Use this document when deciding how a MoonBit Cloud app should be structured or when choosing between multiple implementation shapes.

# Model Summary

MoonBit Cloud apps are generated and modified through agent interaction. The end user does not manage the source code directly. The app should therefore stay predictable, template-driven, and easy for the agent to reason about.

The first platform model is:

- HTTP API only
- request/response execution
- local single-user prototype
- durable storage when required
- explicit tenant scoping when required

# Invariants

- The main user interface is chat, not a code editor.
- The app must remain runnable through the platform runner.
- The app should preserve a recognizable template structure.
- Tenant-aware apps must scope data explicitly.
- Product-facing complexity should stay hidden from the end user.

# Recommended Shape

Prefer a small set of predictable modules:

- request entrypoint
- route handling
- domain logic
- persistence layer
- template metadata

Avoid highly dynamic or ad hoc project shapes in v1.

# Validation

- Confirm the app still exposes the expected handler entrypoint.
- Confirm the runner can build and run the app.
- Confirm the template remains understandable to the agent.

# Related Docs

- [HTTP Handler](../contracts/http-handler.md)
- [Tenant Model](../contracts/tenant-model.md)
- [Template Invariants](../policies/template-invariants.md)
