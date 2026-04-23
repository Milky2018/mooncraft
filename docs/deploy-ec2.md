# Deploying MoonBit Cloud on EC2

## Status

Do not treat the current repo state as production-ready. The correct next target is a public demo or staging deployment on one EC2 instance.

The local product loop is real, but several parts are still intentionally local-only:

- the agent layer is still a local adapter, not real Codex integration
- persistence is single-instance SQLite on local disk
- generated previews run as local child processes with light supervision

## Current Deployment Blockers

### 1. The agent runtime is still fake

The current `AgentGateway` is a deterministic local adapter that rewrites the generated app in a narrow way.

Why this matters:

- the hosted product promise is agent-driven app building
- without the real Codex path, the deployment is only a shell demo

Required fix:

- wire `AgentGateway` to the real Codex-backed execution path
- preserve the one-thread-per-project model already assumed by the architecture

### 2. Persistence is single-instance only

Today state lives in SQLite plus generated project directories on disk.

Why this matters:

- one-node staging is fine
- multi-instance or high-availability production is not

Short-term decision:

- for one EC2 instance, SQLite on EBS is acceptable
- for anything beyond one node, move metadata off SQLite and define a storage strategy for generated workspaces

### 3. Preview processes need stronger supervision

Generated apps currently run as local child processes on dynamic ports.

Why this matters:

- crash recovery is weak
- isolation is weak
- resource limits are not well-defined

Required fix:

- supervise preview processes explicitly
- keep one runtime per project
- define restart, cleanup, timeout, and health-check rules

## Blockers Already Reduced In Code

The repo now includes two deployment-oriented fixes:

- preview URLs are same-origin paths like `/p/<preview_public_id>/`, and the control plane reverse-proxies them to the private preview port
- cookie-session auth is available for platform users, with optional GitHub OAuth on top of email/password

This is enough for a first staged multi-user demo, but not enough for hardened production auth.

## Recommended First Hosted Shape

Use the simplest honest topology:

- one EC2 instance for the app
- one EBS volume for `data/`
- one Application Load Balancer in front
- one ACM certificate for HTTPS
- one target group forwarding to the control plane on port `8080`

Why this is the right first hosted shape:

- it matches the current single-instance architecture
- it gives you TLS, health checks, and a stable public entrypoint
- it keeps the control plane private behind the load balancer

## Network And Access Rules

- expose only `80` and `443` publicly on the load balancer
- keep the EC2 application port private
- allow the instance to receive app traffic only from the load balancer security group
- prefer AWS Systems Manager Session Manager for shell access instead of opening SSH widely

## EC2 Rollout Checklist

### Phase 1: Make the app internet-correct

1. Set `MOONBITCLOUD_PUBLIC_BASE_URL` for the first hosted environment.
2. Optionally set `MOONBITCLOUD_GITHUB_CLIENT_ID` and `MOONBITCLOUD_GITHUB_CLIENT_SECRET` if GitHub OAuth should be live.
3. Decide whether the first hosted target is staging-only or true production.
4. Keep the deployment single-instance until the real agent runtime and preview supervision are stronger.

### Phase 2: Prepare the host

1. Create an EC2 instance role that supports Systems Manager.
2. Attach an EBS volume sized for SQLite, generated projects, and preview artifacts.
3. Install the MoonBit toolchain and any system dependencies the control plane and generated projects need.
4. Clone the repo and verify `just build` and `just test`.

### Phase 3: Run the app as a service

1. Start the control plane with `systemd`, not an interactive shell.
2. Persist logs through `journald` and forward them to CloudWatch if you want centralized logs.
3. Make the service restart automatically on failure.
4. Keep `data/` on durable attached storage.

### Phase 4: Put HTTPS in front

1. Create an ALB.
2. Create an ACM certificate for the chosen domain.
3. Point the ALB target group at the EC2 instance on port `8080`.
4. Route the domain to the ALB.
5. Confirm that `/`, `/api/projects`, and `/p/:preview_public_id/*` work through the public domain.

### Phase 5: Add basic operations

1. Schedule EBS snapshots.
2. Add health checks and alarms.
3. Document backup and restore for SQLite plus `data/projects/`.
4. Decide how you will rotate secrets and environment variables.

## What Counts As Good Enough For The First Public Demo

This should be enough for a public demo or staging environment:

- single EC2 instance
- ALB + HTTPS
- private app port
- cookie-session auth
- reverse-proxied preview routes
- SQLite on EBS
- snapshot backups
- `systemd` service management

This is still not the final production architecture, but it is a reasonable next step.

## Recommended Implementation Order In This Repo

Do the next repo work in this order:

1. replace the local `AgentGateway` with the real Codex path
2. add service and proxy deployment files
3. write and test the EC2 deployment runbook
4. strengthen preview supervision and resource controls

## Non-Goals For The First Hosted Deployment

Do not block the first staging rollout on:

- multi-region deployment
- high availability
- horizontal scaling
- per-user isolation hardening
- billing
- team features
- production-grade multi-tenant security

The right next milestone is a safe single-instance public demo, not a complete cloud platform.
