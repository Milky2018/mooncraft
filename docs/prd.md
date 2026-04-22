# MoonBit Cloud PRD

## Product Summary

MoonBit Cloud is an agent-first platform that lets non-technical or AI-first builders create backend applications by talking to an agent. The user should not need to know MoonBit, frameworks, or backend architecture. The platform should translate product intent into a working MoonBit application.

The first version is a local single-user prototype for HTTP APIs only.

## Problem

Current AI coding tools still assume the user is willing to read code, choose frameworks, and debug infrastructure. That is too much for the target user.

The product goal is to remove those decisions from the user-facing experience:

- no framework selection
- no visible code as the main interface
- no terminal workflow
- no backend setup ceremony

The user should describe the desired product behavior and get a working API-backed app.

## Target User

Primary user:
- AI-first indie builders

Traits:
- comfortable describing product ideas in natural language
- not interested in language or framework choices
- wants fast iteration and visible results
- accepts some platform constraints in exchange for speed

## Primary Job To Be Done

When I describe a backend app in natural language, I want the platform to generate, run, and iteratively improve it, so I can ship useful software without managing the codebase directly.

## First Showcase App

The flagship v1 demo should be:

- a multi-tenant todo app
- durable storage
- HTTP API only

For the local prototype, "multi-tenant" should be modeled explicitly in the platform contract. It does not require full production auth on day one. A tenant can initially be selected through a controlled local mechanism such as a workspace selector or request header.

## Product Principles

### 1. Chat-First Experience

The main interface is conversation with an agent. Code exists, but it is an implementation artifact behind the scenes.

### 2. MoonBit-First Implementation

User applications, templates, SDKs, and platform-facing app libraries should be written in MoonBit wherever practical. If a capability is missing, the team should prefer building the missing MoonBit library rather than changing the product promise.

### 3. Reliable Templates Over Open-Ended Magic

The agent should build from stable, tested templates and recipes. Reliability matters more than raw freedom in v1.

### 4. Local Prototype Before Hosted Platform

The first version should optimize for learning speed, not production readiness. Security hardening, real isolation, and infrastructure scale can wait.

### 5. The User Does Not Need To See Code

The UI should expose goals, state, logs, preview, and deployment status. It should not force the user to understand files, frameworks, or compiler output.

## MVP Scope

Included:

- browser-only product surface
- chat interface to create and modify projects
- HTTP APIs only
- local single-user prototype
- MoonBit application generation and execution
- logs, errors, and basic run feedback
- deployment history for local prototype builds
- durable storage for templates that need persistence
- a knowledge base for agents to follow
- at least one strong demo template

Not included:

- collaboration
- terminal access
- code editor as the primary interface
- billing
- teams and permissions
- production-grade security hardening
- arbitrary long-running servers
- broad integration marketplace

## User Experience

### Primary flow

1. The user opens the browser app.
2. The user describes the app they want in chat.
3. The agent chooses a template or creates one from a template family.
4. The platform generates or updates the MoonBit project.
5. The user runs the app and sees preview, logs, and current behavior.
6. The user asks for changes in chat.
7. The user deploys the current build to a local prototype endpoint.

### Core screens

- project/chat workspace
- app preview or API inspector
- logs and diagnostics
- template picker
- deployment history

The code view can exist internally or behind a debug mode, but it is not part of the main user promise.

## Platform Scope Decisions

- End users do not choose the language.
- The app contract is request/response oriented.
- The first prototype should run locally on one machine.
- No external integration is mandatory for v1.
- The product should still support durable storage because the flagship demo requires it.

## Success Criteria

By the end of the first milestone cycle, success means:

- a demo video exists
- a multi-tenant todo app can be generated and run locally
- the app persists data durably
- the agent can modify the app through conversation
- twenty reusable templates have been defined and prioritized

## Main Risks

### Reliability risk

If the agent edits projects without strong templates and docs, the user experience will feel random.

### Ecosystem risk

If MoonBit is missing important application libraries, platform progress may stall unless the team actively builds those libraries.

### UX risk

A chat-first product can still become confusing if users cannot understand current state, recent changes, or why a run failed.

### Scope risk

Trying to match Replit or Lovable feature breadth too early will delay the core product loop.

## Product Constraint For Now

The practical constraint is not yet known. Until real usage proves otherwise, the project should optimize for:

- fast iteration
- design clarity
- reliability of the generated apps

That is the right default for an early local prototype.
