# MoonCraft Runtimes

The authoritative Runtime contract is
[`docs/runtime-protocol.md`](runtime-protocol.md).

Runtime Protocol v2 is intentionally small. Admin Runtime JSON declares only the
Docker image, supported Builder Agent, model, and one structured auth binding.
The control plane owns the Codex/Claude command, session tracking, dynamic log
streaming, fixed mounts, and preview lifecycle.

Do not add new Runtime protocol fields outside `docs/runtime-protocol.md` and
the matching JSON schemas in `schemas/`.
