# Define the Runtime Storage and Secret ABI

Status: accepted, superseded by ADR-0007.

This ADR refines ADR-0005 and supersedes the parts of ADR-0005 that left Runtime storage ownership, container identity, and file secret placement to the Runtime image provider.

## Context

Runtime Protocol v3 correctly moved agent-specific behavior behind a project-scoped Runtime Service. MoonCraft now talks to a Runtime through HTTP instead of constructing Codex, Claude, or other agent commands in the control plane.

The v3 storage and secret boundary was still incomplete. The protocol said MoonCraft mounts Docker named volumes at `/workspace` and `/home/mooncraft`, but it also said Runtime Protocol v3 does not specify the container user, UID, GID, or privilege model. That is not a stable contract with Docker named volumes. A named volume mounted over `/home/mooncraft` hides whatever ownership the image set during build, so an image-level `chown` cannot guarantee that the mounted directory is writable at runtime.

The file secret contract had the same boundary problem. File secret targets were relative to `/home/mooncraft`, which made MoonCraft write Runtime-internal files such as `.codex/auth.json` into the Runtime Home. That leaks agent-specific filesystem semantics into the control plane and can create root-owned files or directories before the Runtime Service starts.

The root problem is not that MoonCraft needs more knowledge about Codex, Claude, model names, or auth files. The root problem is that Runtime Protocol v3 needs a clear container ABI for durable storage and a secret delivery mechanism that does not mutate Runtime-private home state.

## Decision

Runtime Protocol v3 will define a fixed storage and identity ABI.

MoonCraft provides these project-scoped durable mounts:

- `/workspace`: durable Project Workspace and authoritative project source storage.
- `/home/mooncraft`: durable Runtime Home for Runtime-private state.

MoonCraft must initialize these mounts before the Runtime Service starts. The Runtime may assume both directories exist and are writable.

Runtime images must provide a default user named `mooncraft` with UID `10001` and GID `10001`. The image default user must be `mooncraft`, and `$HOME` must be `/home/mooncraft`. MoonCraft must not pass `docker run --user`; it uses the image default command and default user. The container driver initializes the mounted `/workspace` and `/home/mooncraft` ownership for `10001:10001`.

File secrets no longer target `/home/mooncraft`. MoonCraft exposes file secrets through a read-only secret bundle mounted at:

```text
/run/mooncraft/secrets
```

Runtime Manifest file secret paths are relative to `/run/mooncraft/secrets`. For example:

```json
{
  "source": "codex_account",
  "target": {
    "type": "file",
    "path": "codex/auth.json"
  }
}
```

MoonCraft does not interpret the path beyond validation and materialization. It does not know that `codex/auth.json` is a Codex account file. It only guarantees that the file appears in the secret bundle with restricted permissions and is readable by the Runtime Service user.

If a Runtime needs a secret under `$HOME`, the Runtime image is responsible for installing it during startup. For example, the official Codex Runtime may copy `/run/mooncraft/secrets/codex/auth.json` to `$CODEX_HOME/auth.json`. That copy is Runtime-internal behavior and is not part of the MoonCraft control-plane contract.

Environment secrets keep their existing v3 behavior. They are injected into the Runtime Service process environment and must not collide with normal Runtime `env` keys. MoonCraft does not interpret environment variable names.

## Consequences

The control plane remains unaware of agent, model, provider, account file, and CLI semantics. It only manages Docker storage, secret delivery, Runtime lifecycle, and Runtime Service HTTP calls.

The Docker container driver becomes responsible for:

- creating project-scoped workspace and home volumes;
- initializing those volumes for UID/GID `10001:10001`;
- preparing the read-only secret bundle;
- mounting `/workspace`, `/home/mooncraft`, and `/run/mooncraft/secrets`;
- injecting plain `env` values and environment secrets;
- starting the Runtime image through its default entrypoint and command;
- talking to the Runtime Service on `8080` and preview service on `4792`.

The Runtime image provider becomes responsible for:

- using the fixed `mooncraft` user ABI;
- starting the Runtime Service from the image default command;
- reading `/workspace` and `$HOME`;
- consuming `/run/mooncraft/secrets` according to its own internal meaning;
- starting and managing project preview on port `4792`.

Runtime Manifest file secret semantics are a breaking change. Existing manifests that used paths such as `.codex/auth.json` must migrate to paths such as `codex/auth.json`, and the corresponding Runtime image must install that secret into `$HOME` if needed.

No compatibility layer is required. Runtime Protocol v3 is still under active development and MoonCraft will directly migrate the development database and built-in runtime examples.

## Rejected Alternatives

Dynamic image user detection is rejected. Running the Runtime image to execute `id -u` or `id -g` before startup makes the control plane depend on image internals and creates another hidden lifecycle path.

Passing `docker run --user` is rejected. It overrides the image provider's default process model and can break images that intentionally configure their own user, home, or entrypoint environment.

Asking Runtime images to repair volume permissions at startup is rejected. A Runtime running as a non-root user cannot reliably fix named volume ownership, and requiring root startup would weaken the Runtime ABI.

Continuing to copy file secrets into `/home/mooncraft` is rejected. It mutates Runtime-private state from the control plane, leaks agent-specific paths into manifests, and can create ownership bugs before the Runtime Service starts.

Adding manifest fields such as `container_user`, `container_home`, `uid`, or `gid` is rejected. The platform ABI should be fixed and small instead of configurable per Runtime.
