# Web App

This module renders the current MoonCraft workspace UI with Rabbita.

The page is intentionally narrow:

- left project rail
- center chat workspace
- preview button that opens the generated app in a new tab

Default UX rules:

- desktop-first
- code hidden
- no deploy flow
- plain-English errors
- one obvious composer input

The frontend talks only to the local control-plane APIs and shared DTOs in `packages/sdk`.
Runtime configuration UI follows Runtime Protocol v3; admin-facing Runtime JSON should match `docs/runtime-protocol/`.

Static files served directly over HTTP live under `apps/web/public`. The
directory mirrors public URL paths, so `/assets/**` comes from
`apps/web/public/assets/**` and `/control-plane-assets/**` comes from
`apps/web/public/control-plane-assets/**`. This keeps HTML/CSS/JS frontend
source in the web app while the backend only maps stable routes such as `/`,
`/admin`, and `/admin/login` to public files.
