---
title: Build a Multi-Tenant Todo API
summary: Build a todo API in a generated project with durable storage and explicit tenant scoping
applies_to:
  - http-api
  - todo
  - multi-tenant
  - durable-storage
editable_files:
  - app/main.mbt
  - app/routes.mbt
  - app/todo_service.mbt
  - app/todo_store.mbt
entrypoints:
  - handle
validation:
  - create a todo under tenant A
  - list todos under tenant A
  - verify tenant B cannot see tenant A data
  - update and delete a todo under the owning tenant
status: draft
---

# When To Use

Use this recipe when the user asks for a collaborative or shared task-tracking backend, a simple CRUD API with durable storage, or a meaningful starter app that demonstrates tenant-aware behavior.

This recipe is the canonical first business app pattern for MoonCraft because it exercises:

- HTTP routing
- request and response handling
- durable storage
- tenant-aware reads and writes
- a product shape that is easy to demo

# Goal

Build a multi-tenant todo API where each tenant can create, list, update, and delete its own todos. Data must persist across runs. Todos belonging to one tenant must never be visible to another tenant.

# Invariants

- The app must keep the standard `handle(req, ctx)` entrypoint.
- Every read and write must be scoped by `tenant_id`.
- Durable storage is required.
- The project structure should stay recognizable to the agent.
- The API should remain HTTP-only.

# Recommended Project Shape

Prefer a small and stable structure:

- `app/main.mbt`: request entrypoint
- `app/routes.mbt`: route matching and parameter extraction
- `app/todo_service.mbt`: business logic and validation
- `app/todo_store.mbt`: persistence and tenant-scoped queries

If additional files are needed, add them carefully and keep responsibilities clear.

# Data Model

Use a single tenant-scoped todo model first:

- `tenant_id`: string, required
- `todo_id`: string, required
- `title`: string, required
- `completed`: boolean, required
- `created_at`: string or integer timestamp, required
- `updated_at`: string or integer timestamp, required

Recommended storage table:

```sql
CREATE TABLE todos (
  tenant_id TEXT NOT NULL,
  todo_id TEXT NOT NULL,
  title TEXT NOT NULL,
  completed INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (tenant_id, todo_id)
);
```

Use `tenant_id` as part of the primary key or as an indexed filter. Do not rely on `todo_id` alone.

# Tenant Model

The tenant boundary must be explicit in the runtime contract:

```mbt
pub struct Context {
  tenant_id : String
}
```

The local prototype may derive tenant identity from a controlled request header or local workspace setting, but the application logic must treat it as explicit context data rather than hidden global state.

# API Surface

Implement these routes first:

- `POST /todos`
- `GET /todos`
- `PATCH /todos/:id`
- `DELETE /todos/:id`

Keep the surface narrow until the app is stable.

# Request And Response Shapes

## `POST /todos`

Purpose:

- create a new todo for the current tenant

Request body:

```json
{
  "title": "Buy milk"
}
```

Success response:

```json
{
  "todo_id": "todo_123",
  "title": "Buy milk",
  "completed": false,
  "created_at": "2026-04-22T15:00:00Z",
  "updated_at": "2026-04-22T15:00:00Z"
}
```

Validation:

- reject empty titles

## `GET /todos`

Purpose:

- list all todos for the current tenant

Success response:

```json
{
  "items": [
    {
      "todo_id": "todo_123",
      "title": "Buy milk",
      "completed": false,
      "created_at": "2026-04-22T15:00:00Z",
      "updated_at": "2026-04-22T15:00:00Z"
    }
  ]
}
```

Ordering:

- newest-first or oldest-first are both acceptable, but choose one canonical ordering and document it in the generated app docs

## `PATCH /todos/:id`

Purpose:

- update mutable fields of a tenant-owned todo

Request body:

```json
{
  "title": "Buy milk and bread",
  "completed": true
}
```

Behavior:

- only update a todo if it belongs to the current tenant
- update `updated_at`

## `DELETE /todos/:id`

Purpose:

- delete a tenant-owned todo

Behavior:

- only delete a todo if it belongs to the current tenant

# Persistence Pattern

The persistence layer should own all tenant-scoped data access.

Preferred responsibilities for `app/todo_store.mbt`:

- initialize the storage schema
- insert a tenant-scoped todo
- list todos by tenant
- update a todo by `tenant_id` and `todo_id`
- delete a todo by `tenant_id` and `todo_id`

Do not spread raw storage queries across route handlers.

Representative query shapes:

```sql
SELECT todo_id, title, completed, created_at, updated_at
FROM todos
WHERE tenant_id = ?
ORDER BY created_at DESC;
```

```sql
UPDATE todos
SET title = ?, completed = ?, updated_at = ?
WHERE tenant_id = ? AND todo_id = ?;
```

```sql
DELETE FROM todos
WHERE tenant_id = ? AND todo_id = ?;
```

# Routing Pattern

Prefer a predictable route dispatcher:

- inspect `req.method`
- inspect `req.path`
- parse route parameters
- call the service layer
- convert domain results into HTTP responses

Keep route parsing separate from persistence.

# Allowed Extensions

Once the base app is stable, these are acceptable extensions:

- tags
- due dates
- priority
- filtering by completion state
- pagination
- search by title
- soft delete

Add one extension at a time and preserve the base route contract.

# Forbidden Changes

- removing or bypassing tenant scoping
- renaming the `handle` entrypoint without updating the contract
- coupling route handlers directly to raw storage logic
- changing the project structure arbitrarily
- adding unrelated platform experiments into this generated app

# Validation

Minimum validation for this app:

1. Create a todo under tenant A.
2. List todos under tenant A and confirm the new item exists.
3. List todos under tenant B and confirm tenant A data is absent.
4. Update the todo under tenant A and confirm the change persists.
5. Attempt to update or delete the same todo under tenant B and confirm it does not succeed.
6. Delete the todo under tenant A and confirm it is gone.

# Common Failures

- forgetting to filter reads by `tenant_id`
- updating by `todo_id` alone
- storing tenant identity outside `Context`
- spreading route, domain, and storage logic into one file
- changing response shape inconsistently across routes

# Implementation Notes

This recipe is intentionally specific. The platform should favor one canonical todo implementation pattern over several variants so the agent can make reliable edits later.

This document is still `draft` until the corresponding runnable example and validation flow exist under `examples/`.

# Related Docs

- [App Model](../concepts/app-model.md)
- [HTTP Handler Contract](../contracts/http-handler.md)
- [Tenant Model](../contracts/tenant-model.md)
