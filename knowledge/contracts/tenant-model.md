---
title: Tenant Model
summary: The local prototype tenant contract for MoonBit Cloud apps
applies_to:
  - multi-tenant
  - durable-storage
editable_files:
  - packages/sdk
  - examples
entrypoints:
  - handle
validation:
  - verify tenant isolation in storage queries
status: draft
---

# When To Use

Use this document when building any app that stores user data or claims to be multi-tenant.

# Model Summary

The first prototype must support a meaningful tenant boundary without requiring a full production authentication system.

V1 tenant behavior:

- tenant identity is explicit
- tenant identity is available in `Context`
- storage queries must scope by tenant
- local selection of tenant can come from a controlled request header or local workspace setting

# Invariants

- No multi-tenant template may store shared user data without tenant scoping.
- Tenant identity must be handled as application data, not hidden magic.
- The lack of real auth does not justify mixing tenant data.

# Recommended V1 Pattern

- include `tenant_id` in `Context`
- persist tenant-scoped records with an explicit tenant column
- require tenant-aware queries in the persistence layer

# Validation

- Create data under tenant A.
- Query data under tenant B.
- Confirm tenant B cannot see tenant A data.

# Common Failures

- forgetting to include tenant filters in reads
- writing shared tables without tenant columns
- deriving tenant state indirectly instead of from context

# Related Docs

- [HTTP Handler Contract](./http-handler.md)
- [Template Invariants](../policies/template-invariants.md)
