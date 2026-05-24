# MoonCraft

MoonCraft lets users ask an app-building environment to create and update runnable app workspaces. This language defines the boundary between the platform, the pluggable builder environment, and the generated app preview.

## Language

**Runtime**:
A named app-building environment that MoonCraft can run for a project.
_Avoid_: Agent, model, builder

**Runtime Protocol**:
The centralized contract between MoonCraft and a Runtime.
_Avoid_: Runtime notes, agent instructions, Docker convention

**Agent Artifact**:
A MoonCraft-owned file produced while running an Agent Adapter.
_Avoid_: Runtime output file, protocol context file

**Agent Artifact Area**:
The container-visible scratch directory where an Agent Adapter may write Agent Artifacts.
_Avoid_: Runtime protocol directory, result directory

**Runtime Manifest**:
The configured description of a Runtime available to MoonCraft.
_Avoid_: Runtime JSON, agent config

**Runtime Image Contract**:
The Docker image requirements a Runtime image must satisfy before MoonCraft can run it.
_Avoid_: Container override, Docker run policy

**Builder Agent**:
The supported app-building CLI family selected by a Runtime.
_Avoid_: Runtime, arbitrary command

**Agent Adapter**:
MoonCraft-owned control-plane logic that invokes and streams a Builder Agent.
_Avoid_: Runtime script, agent log parser

**Runtime Auth**:
The Runtime Manifest setting that tells an Agent Adapter how to authenticate a Builder Agent.
_Avoid_: Provider, model provider, API backend

**Runtime Auth Kind**:
The supported authentication strategy named by Runtime Auth.
_Avoid_: Provider name, secret kind

**Secret Target**:
The environment variable or container-home file where a Runtime Auth secret is materialized.
_Avoid_: Secret type, provider key type

**Runtime Turn**:
One execution of a Runtime against a project workspace and prompt.
_Avoid_: Agent run, Codex run

**Project Workspace**:
The project source tree that a Runtime creates or edits for a user.
_Avoid_: Runtime workspace, agent workspace

**Project Preview Contract**:
The part of the Runtime Protocol that defines how a Project Workspace becomes a user-visible preview.
_Avoid_: Preview script convention, preview hint

**Preview Entrypoint**:
The fixed Project Workspace command MoonCraft starts to serve a preview.
_Avoid_: Runtime preview command, framework preview script

**Preview Runtime Parameters**:
The local preview values MoonCraft gives to a Runtime Turn.
_Avoid_: Public preview URL, deployment URL

**Preview Origin**:
The dedicated web origin assigned to one project.
_Avoid_: Preview path, preview prefix

**Preview Origin Policy**:
MoonCraft's deployment-owned rule for assigning Preview Origins.
_Avoid_: Runtime origin template, admin preview URL

**Agent Session**:
MoonCraft-owned durable state mounted for a Runtime across turns of one project.
_Avoid_: Thread id, runtime session

**Runtime Session**:
Runtime-owned resumable conversation state reported back to MoonCraft.
_Avoid_: Thread id, agent session

## Relationships

- A **Runtime Manifest** describes exactly one **Runtime**.
- A **Runtime Manifest** names an image that must satisfy the **Runtime Image Contract**.
- A **Runtime Manifest** selects one **Builder Agent**.
- A **Runtime Manifest** declares one **Runtime Auth** strategy.
- A **Runtime Auth** strategy uses one supported **Runtime Auth Kind**.
- A **Runtime Auth** strategy binds exactly one admin-managed secret.
- A **Runtime Auth** strategy has exactly one **Secret Target**.
- The `openrouter_api_key` **Runtime Auth Kind** can authenticate multiple **Builder Agents**.
- An **Agent Adapter** invokes one **Builder Agent** during a **Runtime Turn**.
- An **Agent Adapter** may use an **Agent Artifact Area** during a **Runtime Turn**.
- A **Runtime Turn** uses one **Runtime** and one **Project Workspace**.
- A **Runtime Turn** may create or update one **Runtime Session**.
- A **Runtime** receives one **Agent Session** per project.
- The **Runtime Image Contract** fixes `/workspace`, `/home/mooncraft`, and `/artifacts` as container paths.
- A **Project Workspace** must satisfy the **Project Preview Contract** before it is delivered to the user.
- A **Project Preview Contract** requires one **Preview Entrypoint** in the **Project Workspace**.
- A project has exactly one current **Preview Origin**.
- A **Preview Origin Policy** assigns each project its **Preview Origin**.
- A **Runtime Turn** may update the project preview served through that **Preview Origin**.
- A **Runtime Turn** receives **Preview Runtime Parameters**, not the public **Preview Origin**.
- The **Project Preview Contract** is part of the **Runtime Protocol**.

## Example Dialogue

> **Dev:** "Can the generated app assume it is served from `/`?"
> **Domain expert:** "Yes, within its own **Preview Origin**. The **Project Preview Contract** gives each preview a dedicated origin, so the **Project Workspace** can use root-relative browser URLs inside that origin."

## Flagged Ambiguities

- "agent" was used to mean **Runtime**, an internal CLI, and model/provider metadata; resolved: users choose a **Runtime**, while the Runtime selects a supported **Builder Agent**.
- "provider" was used to mean model vendor, API endpoint, and account authentication; resolved: Runtime Protocol v2 uses **Runtime Auth** and the manifest field name `auth`.
- "send command" was considered a Runtime-owned arbitrary command; resolved: MoonCraft owns **Agent Adapters** for supported **Builder Agents**.
- "`runtime_context.json`" was considered a Runtime Protocol file; resolved: Runtime Protocol v2 deletes it, and MoonCraft may write **Agent Artifacts** for debugging only.
- "`result.json`" was considered Runtime-written protocol output; resolved: Runtime Protocol v2 deletes it, and MoonCraft writes any result **Agent Artifact** itself.
- "`prompt.txt`" was considered Runtime Protocol input; resolved: Runtime Protocol v2 deletes prompt files from the protocol, and MoonCraft may keep prompts only as **Agent Artifacts**.
- "prompt transport" was considered a Runtime Protocol concern; resolved: prompt transport belongs to the **Agent Adapter**.
- "`/artifacts`" was considered a Runtime protocol exchange directory; resolved: it is an **Agent Artifact Area** owned by MoonCraft's Agent Adapter.
- "container user" was considered a Runtime Manifest setting; resolved: the Dockerfile default `USER` belongs to the **Runtime Image Contract**, and MoonCraft should not override it with `docker run --user`.
- "container home" was considered a Runtime Manifest setting; resolved: the **Runtime Image Contract** fixes Runtime home at `/home/mooncraft`.
- "thread id" was used for both **Agent Session** and **Runtime Session**; resolved: MoonCraft owns the **Agent Session**, and the Runtime reports the **Runtime Session**.
- "preview path" was used as if path-prefix mounting were inherent; resolved: the domain concept is **Preview Origin**, and path-prefix routing is not the target model.
- "preview history" was considered at the run level; resolved: MoonCraft exposes only the current project **Preview Origin**, not historical run previews.
- "origin template" was considered for **Runtime Manifest**; resolved: preview hostnames are deployment-owned **Preview Origin Policy**, not Runtime or admin configuration.
- "preview URL" was considered as Runtime input; resolved: a Runtime receives **Preview Runtime Parameters** and does not need to know the public **Preview Origin**.
- "preview command" was considered for **Runtime Manifest**; resolved: the fixed **Preview Entrypoint** belongs to the **Project Preview Contract**.
