# Agent Docs Plan

## Role Of Documentation

Documentation is a core runtime dependency for MoonBit Cloud. The end user interacts with the system through an agent, so the agent needs precise and reliable internal knowledge about how apps are structured, how templates work, and how platform invariants must be preserved.

These docs are primarily for the agent. Human readability matters, but agent usability matters more.

## Documentation Goals

The knowledge base should help the agent do four things well:

- choose the right template
- edit the correct files
- preserve platform invariants
- validate the result before presenting it to the user

If the docs do not improve those four behaviors, they are not doing their job.

## What To Document First

Write the first documents in this order:

1. project layout and file ownership
2. request/response handler contract
3. tenant model for the local prototype
4. storage and persistence pattern
5. routing pattern
6. logging and debugging pattern
7. run and deploy workflow
8. template selection policy
9. common failure modes
10. migration path for adding new platform libraries

## Recommended Knowledge Base Shape

```text
knowledge/
├── concepts/          # product and architecture concepts
├── contracts/         # stable SDK and data contracts
├── recipes/           # task-oriented implementation guides
├── templates/         # template metadata and usage rules
├── policies/          # invariants and do-not-break rules
└── troubleshooting/   # common failures and debugging steps
```

## Required Document Format

Each knowledge document should use explicit frontmatter and predictable sections:

```md
---
title: Multi-Tenant Todo API
summary: Build and extend the default todo template
applies_to: [http-api, todo, durable-storage]
editable_files:
  - app/main.mbt
  - app/routes.mbt
entrypoints:
  - handle
validation:
  - run template smoke test
  - verify tenant scoping
---

# When To Use

# Invariants

# Files To Change

# Minimal Pattern

# Validation

# Common Failures

# Related Docs
```

## Authoring Rules

- write in English
- optimize for precise execution, not marketing prose
- keep examples runnable
- mention exact file entrypoints and validation steps
- state invariants explicitly
- include "do not do this" guidance where relevant
- prefer one canonical pattern over many options

## Source Of Truth Rule

The order of truth is:

1. working template
2. tests or smoke checks
3. knowledge document

Never promote a pattern to official knowledge before it exists in a working template.

## Doc Categories

### Concepts

Explain the architecture and mental model:

- chat-first product model
- hidden-code UX model
- template-first app generation
- tenant model

### Contracts

Define stable interfaces:

- `Request`
- `Response`
- `Context`
- storage and logging interfaces when they exist

### Recipes

Teach the agent how to perform concrete tasks:

- add a route
- add a persistent model
- scope data by tenant
- add pagination
- expose a CRUD endpoint

### Policies

Protect platform invariants:

- tenant data must be scoped explicitly
- template structure must remain recognizable
- deployable apps must keep required entrypoints

### Troubleshooting

Capture repeat failures:

- compile errors
- missing route wiring
- data not persisted
- tenant leakage in queries

## First Official Documents

The first set should be:

- `knowledge/concepts/app-model.md`
- `knowledge/contracts/http-handler.md`
- `knowledge/contracts/tenant-model.md`
- `knowledge/recipes/build-a-todo-api.md`
- `knowledge/recipes/add-durable-storage.md`
- `knowledge/recipes/add-a-route.md`
- `knowledge/troubleshooting/common-run-failures.md`

## Quality Bar

Every official document should answer:

- when should the agent use this?
- which files can it edit?
- what entrypoint must remain valid?
- how should it validate the result?
- what is the most common mistake?

If a document cannot answer those questions, it is still draft material.
