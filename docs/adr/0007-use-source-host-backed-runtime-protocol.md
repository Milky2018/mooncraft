# Use Source-Host-Backed Runtime Protocol

Status: accepted.

This ADR supersedes ADR-0005 and ADR-0006 where they define Runtime Protocol v3 as a Docker image contract, Docker volume contract, file-secret ABI, fixed preview port, or workspace archive exchange.

## Context

Runtime Protocol v3 moved agent-specific behavior behind a Runtime Service, but the storage and launch boundary was still too Docker-specific. The protocol described Docker images, mounted `/workspace` and `/home/mooncraft` volumes, file secret targets, container identity, and a fixed preview port. That made MoonCraft responsible for Runtime-internal filesystem behavior and created ownership problems around permissions, workspace snapshots, and secret materialization.

The desired long-term direction is broader than Docker. A Runtime should be any HTTP service that implements MoonCraft's Runtime Protocol. The current MoonCraft implementation may still start that service from a Docker image, but Docker is a Runtime launcher detail, not the protocol itself.

MoonCraft also should not persist user project source as Docker volumes or workspace archives. The durable source of truth should be a user-owned source repository. GitHub is the temporary Project Source Host; MoonHub is expected to replace it later.

## Decision

Runtime Protocol v3 defines only a Runtime Service HTTP API. It does not define Docker images, container users, container paths, Docker volumes, mounted secret bundles, or preview ports.

MoonCraft has a separate Runtime Config. The first implementation supports only a Docker Runtime Launcher, but that launcher is MoonCraft configuration, not Runtime Protocol. A future launcher may locate an existing HTTP Runtime Service without changing the protocol.

Each MoonCraft project is bound to a user-owned Project Source Repository. The Project Source Repository is the authoritative persistent source store. MoonCraft creates an empty repository when a project is created, stores repository metadata and the last known ready commit, and does not delete the repository when the MoonCraft project is deleted.

Runtime initialization is explicit. Before any business operation, MoonCraft calls `POST /init` with:

- the Project Source Repository location;
- the default branch and current commit known to MoonCraft;
- a short-lived repository-scoped Project Source Credential;
- opaque Runtime Secrets resolved from Runtime Config.

The Runtime Service clones or updates its Project Workspace from the Project Source Repository during initialization. The Runtime Service, not MoonCraft, owns local workspace layout and Runtime-private state.

`POST /exec` starts an asynchronous Run. A source-modifying Run may report success only after all source changes have been committed and pushed to the Project Source Repository default branch. The terminal Run Result must name the final pushed Ready Source Commit. A Run may create multiple commits, but MoonCraft records only the final Ready Source Commit.

Runtime-created commits use the MoonCraft Source Identity. Runtime Services must not force push. They may automatically merge or rebase remote default-branch updates before pushing; if a conflict cannot be resolved automatically, the Run must not succeed.

Preview is part of the same Runtime Service HTTP origin. The Runtime Service exposes the current project preview under the fixed `/preview/` subtree, and MoonCraft proxies the project's Preview Origin to that subtree. Runtime Protocol v3 no longer defines a separate preview port.

## Consequences

MoonCraft no longer needs to inspect or repair Runtime filesystem permissions, copy secrets into Runtime homes, archive Docker workspaces, or understand generated project paths.

The control plane becomes responsible for Source Host integration:

- creating a user-owned Project Source Repository when a project is created;
- issuing short-lived Project Source Credentials for Runtime initialization;
- storing repository identity, default branch, and current Ready Source Commit;
- detecting unavailable or unauthorized repositories and surfacing Source Disconnected state.

Runtime providers become responsible for:

- implementing the Runtime Service HTTP API;
- cloning/updating the Project Source Repository during initialization;
- using Runtime Secrets according to Runtime-internal meaning;
- committing and pushing source changes before reporting source-modifying Runs as successful;
- serving preview content under `/preview/`.

GitHub is a temporary Project Source Host implementation. The domain model uses Project Source Host and Project Source Repository so MoonHub can replace GitHub without changing Runtime Protocol terms.

No compatibility layer is required. Runtime Protocol v3 is still under active development, and MoonCraft will directly migrate the development database and runtime configuration model.

## Rejected Alternatives

Keeping Docker volumes as authoritative project storage is rejected. It makes Docker container filesystem behavior part of the protocol and forces MoonCraft to reason about image users, UID/GID, path layout, and permissions.

Keeping workspace archive import/export as the persistence boundary is rejected. It avoids Docker volumes but still makes MoonCraft transfer and store project source directly. The Project Source Repository is a cleaner persistence boundary and matches the future MoonHub direction.

Passing source credentials as opaque Runtime Secrets is rejected. Repository access is part of the Runtime Protocol's source persistence contract, while Runtime Secrets remain semantics-free Runtime configuration.

Using a fixed preview port is rejected. Preview is an HTTP subtree of the Runtime Service so Docker and non-Docker Runtime launchers share the same protocol.

Automatically deleting Project Source Repositories when MoonCraft projects are deleted is rejected. The repository is user-owned source data; deleting a MoonCraft project only disconnects MoonCraft metadata.
