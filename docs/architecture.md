# Architecture

## System Goal

MoonBit Cloud is a chat-first system that turns user intent into a working MoonBit backend application. The user interacts with the product through conversation, preview, and plain-English feedback. Code exists in the workspace, but it is not the main interface.

The first implementation target is a local single-user prototype for HTTP APIs.

## Architectural Principles

### 1. Agent-first, not editor-first

The primary user action is sending an instruction to the agent. The product should be organized around:

- conversation
- app state
- run status
- preview
- plain-English status

not around file trees and editor chrome.

### 2. MoonBit-first application stack

The intended default is that user apps, templates, SDKs, storage helpers, routing helpers, and platform-facing app libraries are all written in MoonBit. If thin glue code is required by the browser or host environment, keep it minimal and treat it as infrastructure rather than product logic.

### 3. Request/response runtime

V1 supports HTTP APIs only. User programs should be modeled as request/response handlers rather than arbitrary long-running servers.

### 4. Local-first development

The first version should favor speed and clarity over production-grade isolation. Local files and SQLite are acceptable. Strong runtime boundaries should still exist at the architecture level so they can be hardened later.

## Product Slice To Build First

The correct first slice is:

> A user describes an API in chat, the agent creates or updates a MoonBit app, the platform runs it locally, and the product shows a human-friendly preview.

That slice is enough to validate the core product.

## High-Level Components

### 1. Web App

Purpose:

- host the chat workspace
- show current app state
- preview API behavior
- show plain-English status and errors
- support project switching

The default workspace should have:

- conversation panel
- preview panel
- agent status
- a compact project summary

The file tree and code editor are optional debug surfaces, not primary UX.

### 2. Agent Orchestrator

Purpose:

- receive user intent from the web app
- decide whether to start from a template or modify an existing project
- invoke Codex CLI to edit the project workspace
- request validation and run feedback

This layer is critical because the agent experience is the product experience.

### 3. Project Workspace Manager

Purpose:

- create and manage project directories
- track revisions made by the agent
- snapshot source state for builds
- map conversations to projects

Even when the user never sees files, the system still needs deterministic project state.

### 4. Runner Service

Purpose:

- compile MoonBit application code
- execute request handlers
- expose logs, errors, and structured run output
- provide durable storage access in local development

Keep the runner isolated from the web app process even in the local prototype.

### 5. Control Plane

Purpose:

- store projects, conversations, builds, and deployments
- manage template metadata
- store knowledge document indexes
- orchestrate run and deploy workflows

For the first iteration, metadata can live in SQLite and artifacts can live on the local filesystem.

### 6. Knowledge Base

Purpose:

- teach the agent how MoonBit Cloud apps are structured
- document platform contracts and invariants
- link templates to recipes and troubleshooting steps

This is product-critical infrastructure, not optional documentation.

## Runtime Contract

The first stable contract should be a MoonBit request handler with explicit context:

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

The exact SDK surface will evolve, but two design decisions should stay stable:

- requests are handled as stateless function calls
- tenant context is explicit in the contract

Storage, env, logging, and helper APIs can be layered into `Context` or adjacent modules after the first prototype.

## Durable Storage In V1

The flagship demo requires durable storage, so persistence is part of the first architecture.

Recommended v1 approach:

- `SQLite` for local durable storage
- tenant scoping enforced in the application data model
- request-level tenant selection through a controlled local mechanism

Do not build full authentication first just to support multi-tenancy in the demo. Model the tenant boundary explicitly and keep moving.

## Core Data Model

The control plane should at least represent:

- `Project`
- `Conversation`
- `Revision`
- `Build`
- `Deployment`
- `Template`
- `KnowledgeDocument`

These entities are enough to power the first chat-to-app loop.

## Boundaries To Preserve Early

Even before security work begins, keep these interfaces clean:

- `AgentGateway`: turns product intent into project edits
- `WorkspaceStore`: stores project files and revisions
- `Runner`: compiles and executes MoonBit apps
- `ArtifactStore`: stores source bundles and build artifacts
- `DeploymentStore`: maps builds to runnable endpoints
- `KnowledgeIndex`: resolves docs and recipes for the agent

Today they can be backed by local files and SQLite. Later they can be replaced without rewriting product logic.

## UX Constraints

The UI should optimize for comprehension, not developer power.

Good v1 behavior:

- one obvious place to type intent
- immediate visual feedback
- clear current app state
- visible last change summary
- a preview that proves the app behavior

Bad v1 behavior:

- exposing too many implementation controls
- forcing the user to read source code
- showing raw build output without explanation
- making users choose frameworks or storage models directly

## Delivery Phases

### Phase 0: Freeze Contracts

- define the app handler SDK
- define the project, build, and deployment metadata model
- define the knowledge document format

### Phase 1: Prove The Loop

- create a hello-world template
- create a multi-tenant todo template
- run both through the MoonBit runner
- expose preview and plain-English feedback in the web app

### Phase 2: Make The Agent Reliable

- connect the agent to the knowledge base
- connect templates to recipes and validations
- preserve revision history

### Phase 3: Expand Template Surface

- define and prioritize twenty templates
- standardize storage and routing patterns
- improve deployment repeatability

### Phase 4: Harden The Platform

- auth
- stronger tenant isolation
- secrets handling
- safer execution boundaries
- production deployment model
