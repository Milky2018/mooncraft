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
- Set `"preferred-target"` in the root `moon.mod.json`. Choose the target that
  matches the app you built instead of relying on MoonBit's default target.
- Keep root-level `moon fmt`, `moon check`, `moon build`, and `moon test`
  passing without explicit `--target` flags.
- Provide a root `mooncraft-preview.sh` script that starts the live preview.
- `mooncraft-preview.sh` must read the first CLI argument as the port and default
  to `4300`.
- `mooncraft-preview.sh` must keep the preview process in the foreground.
- The preview server must listen on `0.0.0.0:<port>`.
- The app must serve the user-facing page at `/`.
- Prefer returning a successful response from `/api/health`; MoonCraft also
  checks `/` as a fallback for static or browser-only previews.
- Do not create `frontend/`, `backend/`, or `shared/` directories unless the
  user request genuinely needs that structure.

## Recommended MoonBit Shape

For simple UI apps, a root native Mocket app is usually the fastest reliable
shape:

- Put the runnable server in root `main.mbt`.
- Put large HTML/CSS/JavaScript in a MoonBit block string helper such as
  `app_page_html()`.
- In root `moon.pkg`, import `moonbitlang/async`, `oboard/mocket`,
  `moonbitlang/core/env`, and `moonbitlang/core/string`.
- Set `"preferred-target": "native"` in `moon.mod.json` and
  `options("is-main": true)` in the root `moon.pkg`.
- Add a minimal `mooncraft-preview.sh` that runs the built app or runs the Moon
  command needed for the chosen project shape.
- Add or update tests that assert stable visible behavior, not brittle
  implementation details.

For wasm, wasm-gc, js, or multi-package apps, keep the same contract: set
`preferred-target`, make plain Moon commands pass, and put all custom build,
server, static-hosting, or loader logic inside `mooncraft-preview.sh`.

## Dependency Discovery

MoonCraft fetches approved reference packages before the agent starts. If an
exact package version or API is needed, inspect the local workspace first:

- `.repos/` for fetched registry packages and versions.
- `.mooncakes/` for installed package material.
- `moon ide doc` or package source files for exact APIs.

Do not run `moon update` during normal app generation or repair. Avoid `moon add`
unless the current workspace genuinely requires a new dependency not already
available through the fetched references.

## Preview Script Contract

Create `mooncraft-preview.sh` at the workspace root. Keep it small and explicit.
Example for a native root app:

```sh
#!/bin/sh
set -eu
port="${1:-4300}"
moon build
exe="$(find ./_build -name '*.exe' -type f ! -path '*.dSYM/*' ! -path '*/cmd/*' | head -n 1)"
exec "$exe" "$port"
```

Adjust the command for the actual generated app shape. If the app needs a static
server, Node process, wasm loader, asset build, or multiple commands, put that
logic here. The final command should stay in the foreground with `exec` when
possible.

## Final Response

After editing, validate the workspace. The final response should be brief:
summarize what changed and whether validation passed. Do not expose internal
runtime names, provider keys, container details, or raw logs to the user.
