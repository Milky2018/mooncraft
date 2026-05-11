---
name: mooncraft-generated-app
description: Use for every MoonCraft generated app task, including first-turn app creation, follow-up edits, validation failures, and preview startup repair in a MoonBit project workspace.
---

# MoonCraft Generated App Contract

MoonCraft workspaces start as plain `moon new` output. The user request decides
what the app becomes. Do not preserve the default `cmd/main` hello-world CLI as
the runnable preview.

## Required Runtime Shape

- The project must remain a valid MoonBit project at the workspace root.
- Keep root-level `moon fmt`, `moon check`, `moon build --target native`, and
  `moon test` passing.
- Build one native runnable executable for the live preview.
- The preview executable must read the first CLI argument as the port and default
  to `4300`.
- The preview server must listen on `0.0.0.0:<port>`.
- The app must serve the user-facing page at `/`.
- The app must return a successful response from `/api/health`.
- Do not create `frontend/`, `backend/`, or `shared/` directories unless the
  user request genuinely needs that structure.

## Recommended MoonBit Shape

For browser games and simple UI apps, use one root native Mocket app:

- Put the runnable server in root `main.mbt`.
- Put large HTML/CSS/JavaScript in a MoonBit block string helper such as
  `app_page_html()`.
- In root `moon.pkg`, import `moonbitlang/async`, `oboard/mocket`,
  `moonbitlang/core/env`, and `moonbitlang/core/string`.
- Set `options("is-main": true)` and `supported_targets = "native"` in the root
  `moon.pkg`.
- Add or update tests that assert stable visible behavior, not brittle
  implementation details.

## Dependency Discovery

MoonCraft fetches approved reference packages before the agent starts. If an
exact package version or API is needed, inspect the local workspace first:

- `.repos/` for fetched registry packages and versions.
- `.mooncakes/` for installed package material.
- `moon ide doc` or package source files for exact APIs.

Do not run `moon update` during normal app generation or repair. Avoid `moon add`
unless the current workspace genuinely requires a new dependency not already
available through the fetched references.

## Final Response

After editing, validate the workspace. The final response should be brief:
summarize what changed and whether validation passed. Do not expose internal
runtime names, provider keys, container details, or raw logs to the user.
