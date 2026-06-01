# Use a Runtime Protocol Package as the Source of Truth

Status: accepted.

This ADR refines ADR-0007. ADR-0007 keeps Runtime Protocol v3 as an HTTP service contract and removes Docker-specific storage, identity, path, and preview-port details from the protocol. This ADR defines how MoonCraft will keep the protocol implementation itself consistent.

## Context

Runtime Protocol v3 is currently described in documentation and then implemented separately by the control plane client and the official Runtime Service. That leaves multiple manually synchronized definitions of endpoints, DTOs, status values, Runtime Error shape, and initialization rules.

This drift caused a real failure mode: MoonCraft expected a Runtime Service that could be initialized with `POST /init`, while the published official Runtime image accepted `/exec` before initialization and returned `Runtime endpoint not found.` for `/init`. The problem was not a Docker launch detail by itself; it was that protocol semantics were not represented as shared, compiled, tested MoonBit code.

MoonCraft already uses MoonBit for both the control plane and the official Runtime Service. We should use that strength instead of treating Runtime Protocol as documentation plus duplicated HTTP glue.

## Decision

Create a MoonBit package, `packages/runtime_protocol`, as the internal source of truth for Runtime Protocol v3.

The package owns protocol semantics:

- request and response DTOs;
- route constants and route builders;
- Runtime Error JSON shape;
- protocol-visible status values;
- JSON encode/decode helpers;
- validation rules that are part of the protocol;
- initialization and run-state rules visible through HTTP, such as rejecting business endpoints before initialization.

The package does not own transport or runtime implementation:

- no Docker launcher logic;
- no HTTP client implementation;
- no HTTP server implementation;
- no GitHub or Project Source Host implementation;
- no Codex, Claude, or agent adapter logic;
- no preview process implementation;
- no Runtime Service private state.

The control plane Runtime Service client and the official Runtime Service must both depend on `packages/runtime_protocol` for shared DTOs, route definitions, status values, and Runtime Error rules.

OpenAPI remains the external documentation format for third-party Runtime authors, but it is not the internal source of truth and is not used to generate MoonBit code. A lightweight check should keep OpenAPI endpoint, method, status enum, and Run status enum documentation aligned with `packages/runtime_protocol`.

The official Runtime Service should be split into protocol-facing and implementation-facing modules so contract tests can exercise the protocol layer without building a Docker image or contacting real GitHub/Codex services.

## Consequences

Runtime Protocol behavior becomes compiled and testable by ordinary MoonBit tests before Docker image checks run.

Docker image checks remain useful as final black-box smoke tests, but they should not be the first line of defense against endpoint, DTO, initialization, or status drift.

The implementation work should stay scoped to protocol structure. Git clone behavior, preview serving internals, Codex event mapping, and Runtime image size should be fixed through separate issues unless a protocol-layer bug directly blocks the refactor.

## Rejected Alternatives

Using OpenAPI as the internal source of truth is rejected for now. MoonBit-first generation from OpenAPI is not mature enough here, and building a generator would add a second project before the protocol has stabilized.

Keeping protocol definitions duplicated in documentation, the control plane client, and the Runtime Service is rejected. It is the direct cause of protocol drift and late Docker-level discovery.

Putting HTTP client/server helpers into the shared package is rejected. That would couple protocol semantics to the current `async/http` implementation and make the package too broad.
