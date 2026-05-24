# Control Plane Owns Agent Adapters

MoonCraft Runtime Protocol v2 will not let Runtime manifests provide arbitrary send commands. A Runtime selects a supported **Builder Agent** such as Codex or Claude, declares structured **Runtime Auth** through an `auth` object, and the control plane owns the corresponding **Agent Adapter**, including CLI invocation, authentication setup, dynamic log streaming, and agent-native output interpretation. The v2 Runtime Manifest removes `send`; concrete CLI commands are generated only by MoonCraft, and each Runtime Auth strategy binds exactly one admin-managed secret to one explicit **Secret Target** instead of using a separate top-level `secrets` list. The first v2 Auth Kinds are `openrouter_api_key`, `codex_auth_json`, and `claude_auth_json`; `openrouter_api_key` is shared across Builder Agents, while agent-specific environment setup belongs to the selected Agent Adapter. Account-file auth is materialized to the manifest's file target under `/home/mooncraft`. This keeps Runtime manifests simple for admins while allowing MoonCraft to provide detailed progress without making progress events part of the Runtime Protocol.

The v2 Runtime Manifest field set is deliberately small: `protocol_version`, `image`, `agent`, `model`, and `auth`. It removes v1 `provider`, `send`, `secrets`, `container_home`, and `container_user`.

Runtime Protocol v2 also removes `runtime_context.json`, Runtime-written `result.json`, and prompt files as protocol inputs. Since Agent Adapters live in the control plane, MoonCraft no longer asks Runtime images to read a protocol context file, read a prompt file, or write protocol results; the control plane invokes the supported Builder Agent, extracts the Runtime Session, writes its own Agent Artifacts, and then starts the Project Preview Contract.

MoonCraft may still mount `/artifacts` into the Runtime container, but it is an **Agent Artifact Area** for the control-plane Agent Adapter, not a Runtime Protocol input/output directory.

Prompt transport is also an Agent Adapter implementation detail. Runtime Protocol v2 does not require prompt argv, stdin, or prompt files.
