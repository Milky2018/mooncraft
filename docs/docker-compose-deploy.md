# Docker Compose Deployment

This guide describes the current test and production deployment path for Mooncraft using Docker Compose.

The two environments intentionally use the same runtime shape:

- the same locally built Mooncraft app image
- the same real Docker-backed Codex mode
- the same mounted Docker socket
- the same persistent app and PostgreSQL volume pattern
- different compose project names and host ports

## Runtime Model

Mooncraft runs as one app container plus one PostgreSQL container. When a user sends a project message, the Mooncraft container starts a background worker process. That worker calls the Docker CLI inside the Mooncraft container, which talks to the host Docker daemon through `/var/run/docker.sock`, and starts a separate Codex runtime container for the user run.

This means the host must have Docker installed and the Mooncraft service container must mount:

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

The Mooncraft app image installs `docker-ce-cli`; it does not run a Docker daemon inside the container.

## Images

Build the Mooncraft app image on the deployment host:

```bash
git pull
just build-mooncraft-image mooncraft:local linux/amd64
```

Make sure the Codex runtime image is available:

```bash
docker pull docker.io/moonbitcloud/codex:codex-0.125.0-node24
```

Mooncraft detects the Docker daemon architecture before each real builder run and starts the Codex runtime with an explicit container platform:

- `amd64` / `x86_64` -> `linux/amd64`
- `arm64` / `aarch64` -> `linux/arm64`

Any other Docker host architecture fails before the builder starts. The Codex runtime image must therefore be available for both `linux/amd64` and `linux/arm64`.

If you are publishing your own Codex runtime image, push it first and set `MOONCRAFT_CODEX_DOCKER_IMAGE` when starting Compose.

## Environment Files

Do not repeatedly export deployment variables in the shell. Keep environment-specific values in local env files and pass them to Docker Compose with `--env-file`.

Copy the examples once on the server:

```bash
cp .env.test.example .env.test
cp .env.prod.example .env.prod
```

Then edit `.env.test` and `.env.prod` with real domains, ports, passwords, admin tokens, and optional GitHub OAuth credentials.

Real env files are ignored by Git:

```text
.env
.env.*
```

Only the example files are committed.

## Test Deployment

The test environment uses [docker-compose.test.yml](../docker-compose.test.yml).

Default host port: `18080`

```bash
docker compose --env-file .env.test -f docker-compose.test.yml up -d
curl -fsS http://127.0.0.1:18080/api/health
```

If `.env.test` binds to a different port, use that port in the health check. For example, the committed example uses `127.0.0.1:18089`:

```bash
curl -fsS http://127.0.0.1:18089/api/health
```

## Production Deployment

The production environment uses [docker-compose.prod.yml](../docker-compose.prod.yml).

Default host port: `8080`

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d
curl -fsS http://127.0.0.1:8080/api/health
```

If `.env.prod` binds to a different port, use that port in the health check. For example, the committed example uses `127.0.0.1:8089`:

```bash
curl -fsS http://127.0.0.1:8089/api/health
```

## User LLM Keys

Do not configure a deployment-level OpenAI or OpenRouter key.

Each platform user configures their own provider, model, and API key in the Mooncraft UI. The worker injects that user's key into the isolated Codex container only for the active run.

## Reverse Proxy

Put Caddy, Nginx, or an AWS load balancer in front of the host ports.

Typical routing:

- `https://test.craft.moonbitlang.com` -> `127.0.0.1:18089`
- `https://craft.moonbitlang.com` -> `127.0.0.1:8089`

The public base URL must match the external URL:

```dotenv
MOONCRAFT_PUBLIC_BASE_URL=https://your-domain.com
```

This matters for OAuth callback URLs, account action links, cookies, and preview URLs.

## Upgrade

Normal upgrades should recreate the app container from the freshly built image without deleting volumes. Do not use `down -v` for upgrades because it deletes PostgreSQL and runtime data.

Upgrade test:

```bash
git pull
just build-mooncraft-image mooncraft:local linux/amd64

docker compose --env-file .env.test -f docker-compose.test.yml up -d --force-recreate
curl -fsS http://127.0.0.1:18080/api/health
```

Upgrade production:

```bash
git pull
just build-mooncraft-image mooncraft:local linux/amd64

docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate
curl -fsS http://127.0.0.1:8080/api/health
```

If the Codex runtime image changes:

```bash
docker pull docker.io/moonbitcloud/codex:codex-0.125.0-node24
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate
```

If a host previously cached the wrong-architecture runtime image, remove and repull it after upgrading:

```bash
docker image rm docker.io/moonbitcloud/codex:codex-0.125.0-node24 || true
docker pull docker.io/moonbitcloud/codex:codex-0.125.0-node24
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate
```

Plain `docker compose down` preserves named volumes but creates extra downtime. Use it only when intentionally stopping a stack. Never use `docker compose down -v` unless you intentionally want to delete the PostgreSQL and Mooncraft runtime volumes.

## Logs And Operations

User-facing test and production errors are intentionally sanitized. Operators can fetch structured diagnostics for a run through the admin endpoint when `MOONCRAFT_ADMIN_TOKEN` is configured:

```bash
curl -fsS \
  -H "Authorization: Bearer $MOONCRAFT_ADMIN_TOKEN" \
  https://your-domain.com/api/admin/runs/<run-id>/logs
```

If the admin token is only stored in `.env.prod`, load it for one command without exporting it globally:

```bash
set -a
. ./.env.prod
set +a
curl -fsS \
  -H "Authorization: Bearer $MOONCRAFT_ADMIN_TOKEN" \
  https://your-domain.com/api/admin/runs/<run-id>/logs
```

The response contains the full internal run metadata, run events, and saved builder, validation, and final-summary log contents. Large log files are tailed and marked with `"truncated": true`.

Other admin diagnostics endpoints use the same bearer token:

```text
GET /api/admin/runs/recent/<limit>
GET /api/admin/runs/<run-id>
GET /api/admin/runs/<run-id>/events/<after-seq>
GET /api/admin/runs/<run-id>/logs
GET /api/admin/projects/recent/<limit>
GET /api/admin/projects/<project-id>
```

`<limit>` is clamped to `1..200`. These endpoints are for operators only; do not expose the admin token to browsers or normal users.

Show service status:

```bash
docker compose -f docker-compose.prod.yml ps
```

Follow logs:

```bash
docker compose -f docker-compose.prod.yml logs -f mooncraft
```

Restart the app container:

```bash
docker compose -f docker-compose.prod.yml restart mooncraft
```

Stop an environment:

```bash
docker compose -f docker-compose.prod.yml down
```

Do not use `down -v` unless you intentionally want to delete PostgreSQL and Mooncraft runtime volumes.

## Data

Compose creates named volumes:

- `mooncraft-postgres` for PostgreSQL data
- `mooncraft-runtime` for app runtime data

For the current single-node deployment, preserve both volumes. PostgreSQL stores users, projects, messages, runs, and workspace snapshots. Mooncraft runtime data stores local runtime caches and per-project Codex session homes.

Before treating this as hardened production, define backup and restore for PostgreSQL and the Mooncraft runtime volume.

## Validation

After deployment:

```bash
curl -fsS http://127.0.0.1:8080/api/health
```

Then verify through the public URL:

```bash
curl -fsS https://your-domain.com/api/health
```

For an opt-in real Codex smoke test from the repo root:

```bash
export MOONCRAFT_CODEX_SMOKE_PROVIDER=openrouter
export MOONCRAFT_CODEX_SMOKE_MODEL=openai/gpt-5.5
export MOONCRAFT_CODEX_SMOKE_API_KEY='your-test-key'
just codex-smoke
```

This spends real provider quota.

## Current Limits

This Compose deployment is a single-node deployment. It is suitable for test, staging, and early production validation, but it is not yet a horizontally scalable architecture.

Known limits:

- the app container has access to the host Docker socket
- generated previews run on the same host
- Codex session homes are file-backed under the Mooncraft runtime volume
- runtime volume backups are still operator-managed
- no hard per-user resource quotas are enforced yet
