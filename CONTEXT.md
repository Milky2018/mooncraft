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

**Runtime Manifest**:
The configured description of a Runtime available to MoonCraft.
_Avoid_: Runtime JSON, agent config

**Runtime Image Contract**:
The Docker image requirements a Runtime image must satisfy before MoonCraft can run it.
_Avoid_: Container override, Docker run policy

**Secret Target**:
The environment variable or container-home file where a Runtime Secret is materialized.
_Avoid_: Secret type, provider key type

**Runtime Secret**:
A semantics-free secret binding injected into a Runtime Service.
_Avoid_: Runtime Auth, provider credential

**Runtime Entrypoint**:
The image-defined default process that starts a Runtime Service.
_Avoid_: Manifest command, send command

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

**Project Workspace**:
The durable project source tree that a Runtime creates or edits for a user.
_Avoid_: Runtime workspace, agent workspace

**Runtime Home**:
The project-scoped private durable state mounted as a Runtime Service's home directory.
_Avoid_: Project source, exported workspace

**Runtime Volume**:
A MoonCraft-managed Docker volume mounted into a Runtime Service.
_Avoid_: Host bind mount, workspace snapshot

**Active Project**:
The single project currently open to a user in the MoonCraft workspace.
_Avoid_: Selected row, current tab

**Project Preview Contract**:
The part of the Runtime Protocol that defines how a Runtime Service exposes a project preview.
_Avoid_: Preview script convention, preview hint

**Preview Port**:
The fixed container port where the current project preview is served.
_Avoid_: Public preview URL, host port

**Preview Readiness**:
The Runtime Service status that says whether the fixed Preview Port is ready.
_Avoid_: Preview endpoint discovery, dynamic port allocation

**Runtime Service Readiness**:
The Runtime Service status that says whether its protocol API is ready.
_Avoid_: Preview health, container started

**Runtime Service State**:
The lifecycle state of a project-scoped Runtime Service.
_Avoid_: Run Status, Docker status

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

- A **Runtime Manifest** describes exactly one **Runtime**.
- A **Runtime Manifest** names an image that must satisfy the **Runtime Image Contract**.
- A **Runtime Manifest** may declare zero or more **Runtime Secrets**.
- A **Runtime Manifest** has no Runtime-specific extension fields.
- A **Runtime Secret** binds one admin-managed secret to one **Secret Target**.
- A **Runtime Image Contract** requires one **Runtime Entrypoint**.
- A **Runtime Service** creates one **Run** for each accepted execution request.
- **Exec Idempotency** prevents duplicate **Runs** when MoonCraft retries an exec request.
- **Prompt Transport** belongs to the Runtime Service HTTP API.
- A **Runtime Service** has at most one active **Run**.
- A **Run** has one **Run Status**.
- A **Run** has one authoritative **Run Result** when it reaches a terminal **Run Status**.
- A **Run** produces zero or more **Run Events**.
- Each **Run Event** advances one **Run Event Cursor**.
- MoonCraft uses **Run Event Polling** to read **Run Events** from a **Runtime Service**.
- A project may have one **Runtime Service**.
- A **Runtime Service** belongs to exactly one project.
- A **Runtime Service** has one **Runtime Service State**.
- A **Runtime Service** may stop after its **Runtime Idle TTL** expires.
- A successful preview request refreshes the **Runtime Idle TTL**.
- MoonCraft uses **Runtime Lazy Recovery** when a requested **Runtime Service** is unavailable.
- A **Runtime Network Boundary** protects **Runtime Service** protocol APIs from public access.
- The **Runtime Image Contract** fixes `/workspace` and `/home/mooncraft` as container paths.
- MoonCraft provides **Runtime Volumes** for `/workspace` and `/home/mooncraft`.
- A **Project Workspace** is the authoritative source storage for a project.
- A **Runtime Home** is private Runtime state, not project source.
- A **Runtime Home** belongs to exactly one project.
- A **Project Workspace** must satisfy the **Project Preview Contract** before it is delivered to the user.
- A project has exactly one current **Preview Origin**.
- A **Preview Origin Policy** assigns each project its **Preview Origin**.
- A **Runtime Service** exposes its protocol API on fixed container port `8080`.
- MoonCraft reads **Runtime Service Readiness** before sending execution requests.
- A **Preview Port** is fixed at `4792` and internal to the Runtime container.
- MoonCraft reads **Preview Readiness** before proxying a **Preview Port**.
- A **Runtime Error** has one message.
- The **Project Preview Contract** is part of the **Runtime Protocol**.

## Example Dialogue

> **Dev:** "Can the generated app assume it is served from `/`?"
> **Domain expert:** "Yes, within its own **Preview Origin**. The **Project Preview Contract** gives each preview a dedicated origin, so the **Project Workspace** can use root-relative browser URLs inside that origin."

## Flagged Ambiguities

- "agent" was used to mean **Runtime**, an internal CLI, and model/provider metadata; resolved: Runtime Protocol v3 does not expose agent concepts to MoonCraft.
- "provider" was used to mean model vendor, API endpoint, and account authentication; resolved: Runtime Protocol v3 uses semantics-free **Runtime Secrets**.
- "send command" was considered a Runtime-owned arbitrary command; resolved: Runtime Protocol v3 uses the image-defined **Runtime Entrypoint** and HTTP `/exec`.
- "`runtime_context.json`" was considered a Runtime Protocol file; resolved: Runtime Protocol v3 does not define context files.
- "`result.json`" was considered Runtime-written protocol output; resolved: Runtime Protocol v3 exposes the authoritative **Run Result** over HTTP.
- "`prompt.txt`" was considered Runtime Protocol input; resolved: Runtime Protocol v3 uses HTTP **Prompt Transport** and does not define prompt files.
- "prompt transport" was considered an Agent Adapter concern; resolved: Runtime Protocol v3 carries prompts in the Runtime Service HTTP API.
- "`/artifacts`" was considered a Runtime protocol exchange directory; resolved: Runtime Protocol v3 does not define `/artifacts`.
- "container user" was considered a Runtime Protocol setting; resolved: Runtime Protocol v3 does not define container user, and Runtime providers own their image user policy.
- "host bind mount" was considered for project storage; resolved: Runtime Protocol v3 uses MoonCraft-managed **Runtime Volumes**.
- "container home" was considered a Runtime Manifest setting; resolved: the **Runtime Image Contract** fixes Runtime home at `/home/mooncraft`, backed by a **Runtime Volume**.
- "thread id" was used for both platform and agent state; resolved: Runtime Protocol v3 does not expose session ids.
- "preview path" was used as if path-prefix mounting were inherent; resolved: the domain concept is **Preview Origin**, and path-prefix routing is not the target model.
- "preview history" was considered at the run level; resolved: MoonCraft exposes only the current project **Preview Origin**, not historical run previews.
- "origin template" was considered for **Runtime Manifest**; resolved: preview hostnames are deployment-owned **Preview Origin Policy**, not Runtime or admin configuration.
- "preview URL" was considered as Runtime input; resolved: a Runtime does not need to know the public **Preview Origin**.
- "preview command" was considered for **Runtime Manifest**; resolved: Runtime Protocol v3 has a fixed **Preview Port**, not a manifest preview command.
- "project switch stops Runtime Service" was considered for Runtime lifecycle; resolved: each project owns its **Runtime Service State**, and stopping is driven by **Runtime Idle TTL**.
