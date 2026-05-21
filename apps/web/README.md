# Web App

This module renders the current MoonCraft workspace UI with Rabbita.

The page is intentionally narrow:

- left project rail
- center chat workspace
- right live preview panel

Default UX rules:

- desktop-first
- code hidden
- no deploy flow
- plain-English errors
- one obvious composer input

The frontend talks only to the local control-plane APIs and shared DTOs in `packages/sdk`.

Static shell assets that are served by the control plane live under
`apps/web/assets/control-plane`. This keeps HTML/CSS/JS frontend source in the
web app while allowing the backend to serve stable routes such as `/`,
`/admin`, `/admin/login`, and `/control-plane-assets/**`. The fake-agent smoke
preview HTML also lives there so generated preview markup is not embedded in the
control-plane backend.
