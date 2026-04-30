# Web App

This module renders the current Mooncraft workspace UI with Rabbita.

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
