# Website Prototype

## Scope

The first website prototype is one desktop-first app-develop page.

It includes:

- left project rail
- center chat workspace
- right live preview panel

It excludes:

- landing page
- auth
- deploy flow
- settings
- template browser
- code viewer

## Product Feel

The page should feel consumer-friendly, calm, and obvious to use. It should not feel like an IDE.

The main user loop is:

1. create or select a project
2. type a request
3. wait on a spinner
4. inspect the live preview
5. continue in chat

## Current UI Contract

### Left Rail

- shows projects only
- exposes project creation
- shows basic status badges

### Workspace

- shows message history
- shows one composer
- disables sending while a run is active
- appends a short assistant summary when the run completes

### Preview Panel

- embeds the live preview URL in an iframe when available
- shows clear empty, loading, and failure states
- never shows source code

## Working State

While the agent is working, the user should see:

- a spinner
- a short plain-English status

The goal is clarity, not technical transparency.

## Error State

Errors should remain plain English in the main flow.

Do not surface:

- raw compiler output
- stack traces
- internal agent logs

## Current Preview Assumption

The current prototype uses a real running generated app as the preview target. The right panel is not a fake demo card and not a raw API console.

That is the important product decision:

- preview means runnable software
- code stays hidden

## Design Constraints

- desktop-first
- light visual tone
- generous spacing
- obvious primary input
- low chrome density

The prototype succeeds if a user immediately understands where to type and whether the app changed.
