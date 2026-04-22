# Control Plane

This module is the local backend for the current MoonBit Cloud prototype.

Responsibilities:

- persist projects, messages, and runs in SQLite
- scaffold generated MoonBit workspaces under `data/projects/<id>/workspace`
- serve the app-develop HTTP API
- serve the main workspace page and platform bundle
- rebuild and restart local previews
- store preview URLs and last-known run state

The current `AgentGateway` is a local adapter. It should later be replaced with a real Codex-backed implementation without changing the surrounding control-plane contracts.
