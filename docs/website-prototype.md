# Website Prototype

## Scope

This document defines the first website prototype for MoonBit Cloud.

The prototype is intentionally narrow:

- one app-develop page
- desktop-first
- chat-first
- preview-focused
- code hidden
- no deploy flow
- no auth
- no template picker in the main UX

The goal is to validate the product feel before building the full platform surface.

## Prototype Goal

The website should make a user feel that building software is as simple as asking for it.

The first prototype does not need to prove the full backend platform. It needs to prove the interaction model:

1. open a project
2. type a request in chat
3. wait while the agent works
4. inspect the resulting preview
5. ask for changes

If that feels clear and pleasant, the prototype is doing its job.

## User And Tone

Target user:

- AI-first indie builder

Desired tone:

- consumer friendly
- simple
- calm
- not technical
- not IDE-like

The page should not feel like a developer tool full of panes, tabs, and system jargon.

## Product Decisions Captured Here

- No landing page is required for this stage.
- The first screen should open directly into the app-develop workspace.
- The first state should be an empty chat.
- Templates can exist internally, but the user does not need to see them in v1.
- While the agent works, the UI should show a spinner.
- Code should remain hidden.
- Navigation should focus on projects only.
- There is no deploy feature in this first website version.
- Errors should be explained in plain English.
- The only major surfaces are workspace and preview.

## Core Assumption

Because the product builds HTTP APIs only, "preview" should mean a human-friendly interactive result view rather than a raw API console.

For the first demo, the preview should be specialized for the current app shape:

- for the multi-tenant todo demo, show a todo-style preview UI
- for simpler APIs later, show a structured preview card instead of raw logs

This keeps the product understandable for non-technical users.

## Information Architecture

The prototype should have only two visible app areas:

- workspace
- preview panel

The workspace itself should include:

- project switcher
- chat history
- composer
- agent status

Do not add separate pages for deployments, templates, settings, or account management yet.

## Primary Layout

Recommended desktop layout:

- left rail: projects
- center panel: chat workspace
- right panel: preview

### Left Rail

Purpose:

- show the project list
- create a new project
- switch between projects

Keep it compact and simple. This rail is for orientation, not power-user navigation.

### Center Panel

Purpose:

- hold the conversation with the agent
- show recent agent responses
- show working state
- accept the next instruction

Core elements:

- project title
- short project status
- message list
- composer input
- submit action

### Right Panel

Purpose:

- show what the current app does
- update after the agent changes the project
- help the user judge progress without reading code

Core elements:

- preview header
- current state badge
- preview canvas

## First Screen

The first screen should be intentionally minimal.

Recommended empty state:

- an empty chat area
- a clear prompt input at the bottom
- a quiet preview placeholder on the right
- a small project list on the left

The user should immediately understand where to type.

Do not start with:

- template cards
- setup forms
- settings dialogs
- code editors

## Agent Working State

While the agent is working, show:

- a spinner
- a short plain-language status such as "Building your app"

Do not show complex job graphs or technical build stages yet.

The main point is to reassure the user that work is in progress without introducing developer-facing complexity.

## Success State

After a successful agent action, show:

- a short plain-English summary in chat
- the updated preview on the right
- a small project state label such as "Preview ready"

The user should understand what changed without inspecting files.

## Failure State

Failures should be shown in plain English only.

Good error presentation:

- "I could not run the app because the todo storage schema is invalid."
- "I updated the route, but the preview could not start yet."

Avoid raw compiler logs in the main flow.

If technical details are needed later, they should live behind an internal debug mode rather than the main prototype.

## Preview Design

The preview should look like a small product, not like a diagnostics pane.

For the todo demo, the preview should include:

- tenant selector
- todo input
- todo list
- completion toggle
- delete action

This gives the user a direct sense that the backend is working.

For later generic APIs, the preview can degrade into:

- labeled request form
- response card
- plain-language state message

## Interaction Rules

- The user types requests in chat.
- The agent responds in plain language.
- Preview updates are the main proof of progress.
- Projects are the only navigation concept exposed to the user.
- Code is never part of the default workflow.

## Visual Direction

The visual direction should be consumer-friendly rather than enterprise or developer-heavy.

Design characteristics:

- bright and clean
- soft but confident contrast
- generous spacing
- large readable type
- obvious primary input
- minimal chrome

Avoid:

- terminal aesthetics
- dense sidebars
- dark industrial dashboards
- highly technical labels

## Suggested Component List

- `ProjectRail`
- `NewProjectButton`
- `WorkspaceHeader`
- `ChatTimeline`
- `AgentThinking`
- `MessageComposer`
- `PreviewPanel`
- `PreviewEmptyState`
- `PreviewTodoDemo`
- `PlainEnglishErrorCard`

## What Can Be Fake In The Prototype

These can be mocked at the website-prototype stage:

- project persistence
- agent execution details
- preview update timing
- generated app state
- run history

What should not feel fake:

- the page layout
- the chat flow
- the sense of progress
- the preview experience

## Out Of Scope

- deploy flow
- authentication
- mobile optimization
- settings page
- template browsing UI
- code viewer
- raw logs viewer

## Deliverable

The first deliverable should be a single polished app-develop page that can support a short demo video.

That page should communicate the full product promise better than a broader but weaker multi-page prototype.
