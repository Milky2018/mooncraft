# MoonCraft PRD

## Product Summary

MoonCraft is an agent-first app builder for AI-first indie builders who do not want to choose languages, frameworks, or backend architecture. The user should describe intent in chat, wait briefly, and see a working app preview.

The current product target is a local single-instance multi-user prototype.

## Target User

Primary user:

- AI-first indie builders

Traits:

- willing to describe software in natural language
- not interested in implementation details
- wants visible product progress quickly
- accepts constraints if the workflow feels simple

## Core Job

When I describe an app in natural language, I want the platform to generate and iteratively improve it for me, so I can build software without managing the codebase directly.

## Current V1 Scope

Included:

- one desktop-first app-develop page
- GitHub OAuth sign-in
- cookie sessions
- projects rail
- chat workspace
- live preview panel
- hidden code by default
- plain-English agent feedback
- local project runtime scratch under `data/runtime`
- SQLite persistence for projects, messages, runs, and workspace snapshots

Not included:

- deploy flow
- starter browser
- mobile UX
- terminal access
- code editor in the main flow
- production security hardening

## Product Principles

### 1. Chat First

The main user action is sending intent to the agent, not opening files or editing code.

### 2. MoonBit First

The platform and generated apps should stay MoonBit-first. Missing capabilities should be filled with MoonBit libraries where practical.

### 3. Preview Is The Proof

The main evidence of progress is a running app preview, not raw logs or source diffs.

### 4. Local Before Hosted

The first goal is a reliable local loop. Hosted deployment and hard multi-tenant isolation can come later.

## Current Product Flow

1. The user opens the app-develop page.
2. The user creates or selects a project.
3. The user sends a request in chat.
4. The platform updates a generated MoonBit workspace.
5. The platform rebuilds and restarts the preview.
6. The user sees a plain-English summary and an updated live preview.

## Current Implementation Boundary

The repo already includes a runnable local control plane and workspace UI. The remaining product-critical gap is the real agent runtime.

Today:

- project persistence is real
- generated MoonBit workspaces are real
- preview rebuild and restart are real
- the visible workspace UI is real
- the agent editing layer is still a local adapter seam

## Success Criteria

Near-term success means:

- a demo video exists
- the app-develop page feels clear and consumer-friendly
- one project can be created, edited through chat, and previewed locally
- project state survives refresh through SQLite and disk
- the system is ready for a real Codex-backed `AgentGateway`
