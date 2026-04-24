# Templates Roadmap

## Purpose

The platform needs templates because the agent cannot reliably build production-shaped apps from a blank slate every time. Templates are the substrate that makes the product repeatable.

The initial success target is twenty templates, but they should be introduced in layers rather than all at once.

## Template Strategy

The first templates should share a common platform contract:

- HTTP APIs only
- MoonBit-first implementation
- local durable storage where needed
- explicit tenant model where needed
- deployable through the same runner

This keeps template quality higher than trying to support unrelated stacks.

## Phase 1: Foundation Templates

1. Hello World API
2. Echo JSON API
3. Health Check API
4. Single-Tenant Todo API
5. Multi-Tenant Todo API

These templates establish:

- routing
- request/response contract
- basic storage
- tenant scoping

## Phase 2: CRUD Business Templates

6. Notes API
7. Contacts API
8. Inventory API
9. Orders API
10. Booking API

These templates establish:

- reusable CRUD patterns
- table design patterns
- filtering and pagination

## Phase 3: Workflow Templates

11. Kanban API
12. Issue Tracker API
13. Form Submission API
14. Survey API
15. Comment Thread API

These templates establish:

- richer domain logic
- multi-entity relationships
- validation patterns

## Phase 4: Content And Utility Templates

16. Blog CMS API
17. Link Shortener API
18. Simple CMS API
19. Webhook Receiver API
20. Agent Tools API

These templates establish:

- content models
- webhook handling
- tool-style endpoints for agent workflows

## Template Quality Standard

Every official template should include:

- a working MoonBit project
- a passing sandbox check through `just check-template <template_id>`
- direct preview smoke steps
- control-plane product smoke steps
- a matching knowledge document
- a short product description
- a list of supported modifications

## Template Metadata

Each template should eventually declare:

- name
- category
- summary
- app shape
- storage requirement
- tenant requirement
- editable entrypoints
- validation command

## First Template To Build

The first serious template should be `Multi-Tenant Todo API` because it tests the core product claim:

- chat-driven creation
- durable storage
- tenant-aware behavior
- enough complexity to be meaningful
- still small enough to debug
