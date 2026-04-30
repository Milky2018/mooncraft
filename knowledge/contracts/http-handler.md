---
title: HTTP Handler Contract
summary: The initial request, response, and context contract for Mooncraft apps
applies_to:
  - http-api
  - sdk
editable_files:
  - packages/sdk
entrypoints:
  - handle
validation:
  - compile the generated app
  - execute one smoke request
status: draft
---

# When To Use

Use this document when defining the SDK or modifying the app entrypoint.

# Contract

The first stable app contract should look like this:

```mbt
pub struct Request {
  method : String
  path : String
  query : Map[String, String]
  headers : Map[String, String]
  body : Bytes
}

pub struct Response {
  status : Int
  headers : Map[String, String]
  body : Bytes
}

pub struct Context {
  tenant_id : String
}

pub fn handle(req : Request, ctx : Context) -> Response raise {
  ...
}
```

# Invariants

- The entrypoint must remain `handle`.
- The handler must be request/response oriented.
- Tenant context must be available explicitly.
- Storage and logging helpers can be added later, but must not break the entrypoint contract.

# Files To Change

During initial platform work, expected edit targets are:

- SDK contract modules
- generated app entrypoint files
- runner adapters

# Validation

- Verify the app compiles with the current runner target.
- Verify one request can be executed end to end.
- Verify the tenant context is passed correctly.

# Common Failures

- Missing or renamed `handle` entrypoint
- Request shape diverges from runner expectations
- Tenant context is assumed implicitly instead of passed explicitly

# Related Docs

- [App Model](../concepts/app-model.md)
- [Tenant Model](./tenant-model.md)
