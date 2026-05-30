# MoonCraft

MoonCraft lets users ask an app-building environment to create and update runnable app workspaces. This language defines the boundary between the platform, the pluggable builder environment, and the generated app preview.

## Language

**Runtime**:
A named app-building environment that MoonCraft can run for a project.
_Avoid_: Agent, model, builder

**Runtime Service**:
The project-scoped service process exposed by a Runtime while it is running for that project.
_Avoid_: Agent process, one-shot builder command

**Runtime Protocol**:
The centralized contract between MoonCraft and a Runtime.
_Avoid_: Runtime notes, agent instructions, Docker convention

**Runtime Config**:
The admin-managed configuration that tells MoonCraft how to launch or locate a Runtime Service.
_Avoid_: Runtime Protocol schema, agent config, manifest

**Runtime Launcher**:
MoonCraft's implementation-specific way to start or locate a Runtime Service.
_Avoid_: Runtime Protocol, agent command

**Docker Runtime Launcher**:
The current Runtime Launcher that starts a Docker image to provide a Runtime Service.
_Avoid_: Runtime Protocol, Docker ABI

**Runtime Secret**:
A semantics-free secret payload synchronized to a Runtime Service through the Runtime Protocol.
_Avoid_: Runtime Auth, provider credential

**Runtime Env**:
A semantics-free environment variable binding injected into a Runtime Service.
_Avoid_: Model setting, provider setting, secret

**Run**:
One user-visible asynchronous execution accepted by a Runtime Service.
_Avoid_: Job, task, agent turn

**Run Event**:
A Runtime Service record describing observable progress for one Run.
_Avoid_: Webhook, callback, raw log line

**Run Event Cursor**:
The per-Run position used by MoonCraft to continue reading Run Events.
_Avoid_: Log offset, stream token

**Run Event Polling**:
MoonCraft's repeated HTTP reads of Run Events from a Runtime Service.
_Avoid_: SSE, Runtime callback

**Run Result**:
The authoritative terminal status and message of a Run.
_Avoid_: Final log event, Runtime artifact

**Exec Idempotency**:
The Runtime Service rule that repeating an exec request with the same Run id returns the existing Run.
_Avoid_: Duplicate run, retry side effect

**Prompt Transport**:
The HTTP request body field carrying a user's instruction to a Runtime Service.
_Avoid_: Prompt file, command argument

**Runtime Error**:
A Runtime Service HTTP error represented by a human-readable message.
_Avoid_: Agent error code, provider error

**Run Status**:
The protocol state of a Run.
_Avoid_: Worker status, process status, activity label

**Ready Source Commit**:
The Project Source Repository commit that contains all source changes produced by a successful Run.
_Avoid_: Local workspace state, agent completion

**Project Workspace**:
The Runtime Service-owned project source tree that a Runtime creates or edits for a user.
_Avoid_: MoonCraft workspace volume, agent workspace

**Project Source Repository**:
The user-owned remote repository that is the authoritative persistent source store for a project.
_Avoid_: MoonCraft source archive, Runtime volume

**Project Source Host**:
The external repository service that owns Project Source Repositories.
_Avoid_: MoonCraft storage backend, Runtime storage

**Project Source Credential**:
A short-lived credential that lets a Runtime Service read and write one Project Source Repository.
_Avoid_: Runtime auth, model provider key

**MoonCraft Source Identity**:
The bot or app identity used for commits created by MoonCraft-controlled Runtime Services.
_Avoid_: User git identity, anonymous commit author

**Runtime Home**:
The Runtime Service-owned private state for one project.
_Avoid_: Project source, exported workspace

**Active Project**:
The single project currently open to a user in the MoonCraft workspace.
_Avoid_: Selected row, current tab

**Project Preview Contract**:
The part of the Runtime Protocol that defines how a Runtime Service exposes a project preview.
_Avoid_: Preview script convention, preview hint

**Preview Endpoint**:
The Runtime Service HTTP route that serves the current project preview.
_Avoid_: Preview port, preview script

**Preview Readiness**:
The Runtime Service status that says whether its Preview Endpoint is ready.
_Avoid_: Preview endpoint discovery, dynamic port allocation

**Runtime Service Readiness**:
The Runtime Service status that says whether its protocol API is ready.
_Avoid_: Preview health, container started

**Runtime Initialization**:
The first Runtime Protocol call that gives a Runtime Service its Project Source Repository, Project Source Credential, and Runtime Secrets.
_Avoid_: Container startup, workspace archive import, secret injection

**Runtime Service State**:
The lifecycle state of a project-scoped Runtime Service.
_Avoid_: Run Status, Docker status

**Source Disconnected**:
The project state where the Project Source Repository is unavailable or no longer authorized.
_Avoid_: Runtime failure, preview failure

**Runtime Idle TTL**:
The configurable duration a Ready Runtime Service may stay alive after its last Run finishes.
_Avoid_: Run timeout, browser unload timeout

**Runtime Lazy Recovery**:
MoonCraft's request-time recovery of an unavailable Runtime Service.
_Avoid_: Global container scan, read-path run recovery

**Runtime Network Boundary**:
The internal Docker network boundary that keeps Runtime Service APIs private to MoonCraft.
_Avoid_: Runtime HTTP authentication, host-published ports

**Preview Origin**:
The dedicated web origin assigned to one project.
_Avoid_: Preview path, preview prefix

**Preview Origin Policy**:
MoonCraft's deployment-owned rule for assigning Preview Origins.
_Avoid_: Runtime origin template, admin preview URL

## Relationships

- A **Runtime Config** describes exactly one **Runtime**.
- A **Runtime Config** names one **Runtime Launcher**.
- A **Runtime Config** may declare zero or more **Runtime Env** bindings.
- A **Runtime Config** may declare zero or more **Runtime Secrets**.
- A **Runtime Config** is MoonCraft configuration, not the **Runtime Protocol**.
- A **Runtime Launcher** starts or locates a **Runtime Service** for MoonCraft.
- The **Docker Runtime Launcher** is MoonCraft's current Runtime Launcher implementation.
- The first Runtime Config implementation supports only the **Docker Runtime Launcher**.
- The **Runtime Protocol** defines a **Runtime Service** HTTP API, not a Docker image contract.
- A **Runtime Env** binding is not a **Runtime Secret**.
- A **Runtime Secret** is synchronized to a **Runtime Service** through the Runtime Protocol before execution.
- A **Project Source Credential** is part of **Runtime Initialization**, not a **Runtime Secret**.
- A **Runtime Service** creates one **Run** for each accepted execution request.
- **Exec Idempotency** prevents duplicate **Runs** when MoonCraft retries an exec request.
- **Prompt Transport** belongs to the Runtime Service HTTP API.
- A **Runtime Service** has at most one active **Run**.
- A **Run** has one **Run Status**.
- A **Run** has one authoritative **Run Result** when it reaches a terminal **Run Status**.
- A successful source-modifying **Run** must produce a **Ready Source Commit**.
- A **Run** produces zero or more **Run Events**.
- Each **Run Event** advances one **Run Event Cursor**.
- MoonCraft uses **Run Event Polling** to read **Run Events** from a **Runtime Service**.
- A project may have one **Runtime Service**.
- A **Runtime Service** belongs to exactly one project.
- A **Runtime Service** must complete **Runtime Initialization** before accepting execution, preview, status, or workspace requests.
- **Runtime Initialization** provides the **Project Source Repository**, a **Project Source Credential**, and **Runtime Secrets**.
- During **Runtime Initialization**, the Runtime Service clones or updates the **Project Workspace** from the **Project Source Repository**.
- **Runtime Initialization** may be retried while no **Run** is active.
- **Runtime Initialization** must not replace state while a **Run** is active.
- A **Runtime Service** has one **Runtime Service State**.
- A **Runtime Service** may stop after its **Runtime Idle TTL** expires.
- A successful preview request refreshes the **Runtime Idle TTL**.
- MoonCraft uses **Runtime Lazy Recovery** when a requested **Runtime Service** is unavailable.
- A **Runtime Network Boundary** protects **Runtime Service** protocol APIs from public access.
- The **Runtime Protocol** does not define Project Workspace or Runtime Home container paths.
- MoonCraft does not directly read or write a **Project Workspace** through Docker filesystem paths.
- A **Project Workspace** is the Runtime Service-owned authoritative source storage for a project.
- A **Project Source Repository** is the authoritative persistent source storage for a project.
- A **Project Source Host** owns **Project Source Repositories** outside MoonCraft.
- MoonCraft creates an empty **Project Source Repository** when a project is created.
- Deleting a MoonCraft project does not delete its **Project Source Repository**.
- A project becomes **Source Disconnected** when its **Project Source Repository** is unavailable or unauthorized.
- A **Project Source Credential** is scoped to one **Project Source Repository** and one Runtime Service initialization.
- The first source-generating **Run** creates the initial **Ready Source Commit**.
- A Runtime Service must commit and push Project Workspace changes to the **Project Source Repository** before reporting a source-modifying **Run** as successful.
- A **Ready Source Commit** is required before MoonCraft treats source-modifying work as Ready.
- A **Run** may produce multiple source commits, but its **Run Result** names one final **Ready Source Commit**.
- A Runtime Service pushes successful source changes to the Project Source Repository default branch.
- A Runtime Service must not force push to a **Project Source Repository**.
- A Runtime Service may automatically merge or rebase remote default-branch changes before pushing.
- A source conflict prevents a **Run** from producing a **Ready Source Commit**.
- Runtime-created commits use the **MoonCraft Source Identity**.
- A **Runtime Home** is private Runtime state, not project source.
- MoonCraft does not persist **Runtime Home**.
- A **Project Workspace** must satisfy the **Project Preview Contract** before it is delivered to the user.
- A project has exactly one current **Preview Origin**.
- A **Preview Origin Policy** assigns each project its **Preview Origin**.
- A **Runtime Service** exposes its protocol API over HTTP.
- MoonCraft reads **Runtime Service Readiness** before sending execution requests.
- A **Runtime Service** exposes the current project preview through its **Preview Endpoint**.
- The **Preview Endpoint** is the fixed `/preview/` subtree on the Runtime Service.
- MoonCraft proxies a **Preview Origin** to the Runtime Service **Preview Endpoint**.
- MoonCraft reads **Preview Readiness** before proxying a **Preview Endpoint**.
- A **Runtime Error** has one message.
- The **Project Preview Contract** is part of the **Runtime Protocol**.

## Example Dialogue

> **Dev:** "Can the generated app assume it is served from `/`?"
> **Domain expert:** "Yes, within its own **Preview Origin**. The **Project Preview Contract** gives each preview a dedicated origin, so the **Project Workspace** can use root-relative browser URLs inside that origin."

## Flagged Ambiguities

- "agent" was used to mean **Runtime**, an internal CLI, and model/provider metadata; resolved: Runtime Protocol v3 does not expose agent concepts to MoonCraft.
- "provider" was used to mean model vendor, API endpoint, and account authentication; resolved: Runtime Protocol v3 uses semantics-free **Runtime Secrets**.
- "env var" was considered as a way to configure model/provider behavior; resolved: Runtime Protocol v3 allows semantics-free **Runtime Env** bindings but MoonCraft does not interpret them.
- "send command" was considered a Runtime-owned arbitrary command; resolved: Runtime Protocol v3 uses HTTP `/exec`.
- "`runtime_context.json`" was considered a Runtime Protocol file; resolved: Runtime Protocol v3 does not define context files.
- "`result.json`" was considered Runtime-written protocol output; resolved: Runtime Protocol v3 exposes the authoritative **Run Result** over HTTP.
- "`prompt.txt`" was considered Runtime Protocol input; resolved: Runtime Protocol v3 uses HTTP **Prompt Transport** and does not define prompt files.
- "prompt transport" was considered an Agent Adapter concern; resolved: Runtime Protocol v3 carries prompts in the Runtime Service HTTP API.
- "`/artifacts`" was considered a Runtime protocol exchange directory; resolved: Runtime Protocol v3 does not define `/artifacts`.
- "container user" was considered a Runtime Protocol setting; resolved: Runtime Protocol v3 does not define container user, and Runtime providers own their image user policy.
- "host bind mount" was considered for project storage; resolved: the **Project Workspace** is Runtime Service-owned and exposed through Runtime Protocol APIs.
- "container home" was considered a Runtime Config setting; resolved: Runtime Protocol v3 does not define Runtime Home paths.
- "Docker volume" and "workspace archive" were considered for project persistence; resolved: the **Project Source Repository** is the authoritative persistent source store.
- "GitHub repo" was considered as the persistent source store; resolved: the domain concept is **Project Source Repository**, currently implemented by GitHub and intended to move to MoonHub later.
- "thread id" was used for both platform and agent state; resolved: Runtime Protocol v3 does not expose session ids.
- "preview path" was used as if path-prefix mounting were inherent; resolved: the domain concept is **Preview Origin**, and path-prefix routing is not the target model.
- "preview history" was considered at the run level; resolved: MoonCraft exposes only the current project **Preview Origin**, not historical run previews.
- "origin template" was considered for **Runtime Config**; resolved: preview hostnames are deployment-owned **Preview Origin Policy**, not Runtime or admin configuration.
- "preview URL" was considered as Runtime input; resolved: a Runtime does not need to know the public **Preview Origin**.
- "preview command" was considered for **Runtime Config**; resolved: Runtime Protocol v3 exposes preview through a Runtime Service **Preview Endpoint**, not a configured preview command.
- "Runtime Manifest" was considered as the admin JSON name; resolved: the admin-managed object is **Runtime Config**, while **Runtime Protocol** is only the Runtime Service HTTP contract.
- "project switch stops Runtime Service" was considered for Runtime lifecycle; resolved: each project owns its **Runtime Service State**, and stopping is driven by **Runtime Idle TTL**.
- "Docker image" was considered part of **Runtime Protocol**; resolved: Runtime Protocol v3 only defines a Runtime Service HTTP API, while Docker images are handled by MoonCraft's current **Docker Runtime Launcher**.
- "preview port" was considered part of **Runtime Protocol**; resolved: Runtime Protocol v3 uses a Runtime Service **Preview Endpoint** instead of a fixed preview port.
- "secret target" was considered as an env or file materialization path; resolved: Runtime Protocol v3 synchronizes **Runtime Secrets** through the Runtime Service API, and the Runtime Service owns any internal materialization.
- "`/workspace/archive` plus `/secrets`" was considered as separate setup calls; resolved: Runtime Protocol v3 uses **Runtime Initialization** to provide source repository access and secrets before any other business call.
