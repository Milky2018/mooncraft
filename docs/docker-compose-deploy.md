# Docker Compose Deployment

This guide describes the current test and production deployment path for MoonCraft using Docker Compose.

The two environments intentionally use the same runtime shape:

- the same locally built MoonCraft app image
- the same real Docker-backed agent runtime mode
- the same mounted Docker socket
- the same host-mounted app data directory pattern and PostgreSQL volume pattern
- different compose project names and host ports

## Runtime Model

MoonCraft runs as one app container plus one PostgreSQL container. When a user sends a project message, the MoonCraft container starts a background worker process. That worker calls the Docker CLI inside the MoonCraft container, which talks to the host Docker daemon through `/var/run/docker.sock`, and starts a separate agent runtime container for the user run.

This means the host must have Docker installed and the MoonCraft service container must mount:

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

The MoonCraft app image installs `docker-ce-cli` and the MoonBit CLI. It does not run a Docker daemon inside the container. The MoonBit CLI must remain available at runtime because `POST /api/projects` initializes each generated project workspace with `moon new` before the first agent turn.

Because the Docker daemon is on the host, every source path in `docker run -v ...` is resolved on the host, not inside the MoonCraft container. MoonCraft therefore requires `MOONCRAFT_HOST_DATA_DIR`: an absolute host path mounted into the app container as `/app/data`. The app stores runtime workspaces under `/app/data/...` and translates those paths back to `${MOONCRAFT_HOST_DATA_DIR}/...` before starting agent runtime containers.

## Images

Build the MoonCraft app image on the deployment host:

```bash
git pull
just build-mooncraft-image mooncraft:local linux/amd64
```

Make sure the agent runtime image is available. The `just deploy-*` commands below pull it automatically from the image configured in the matching env file.

```bash
just build-agent-runtime-image docker.io/moonbitcloud/mooncraft-agent-runtime 0.1.1

# Build local architecture-suffixed images for both supported platforms:
just build-agent-runtime-images docker.io/moonbitcloud/mooncraft-agent-runtime 0.1.1

# Publish the shared multi-architecture image:
just docker-agent-runtime-publish docker.io/moonbitcloud/mooncraft-agent-runtime 0.1.1 linux/amd64,linux/arm64

just deploy-test
# or
just deploy-prod
```

MoonCraft detects the Docker daemon architecture before each real builder run and starts the agent runtime with an explicit container platform:

- `amd64` / `x86_64` -> `linux/amd64`
- `arm64` / `aarch64` -> `linux/arm64`

Any other Docker host architecture fails before the builder starts. The agent runtime image must therefore be available for both `linux/amd64` and `linux/arm64`.

`just build-agent-runtime-image` defaults to the current Docker host platform, which is the right choice for local smoke tests. `just build-agent-runtime-images` builds both local platform-specific tags, such as `:0.1.1-amd64` and `:0.1.1-arm64`. Production and shared test deployments should use `just docker-agent-runtime-publish`, which builds and pushes one multi-architecture tag that Docker can resolve by host platform.

If you are publishing your own agent runtime image, push it first and register that image in a Runtime manifest. Official built-ins are packaged under `runtime/builtin/`; admin-created Runtimes are configured from the admin page.

## Environment Files

Do not repeatedly export deployment variables in the shell. Keep environment-specific values in local env files and pass them to Docker Compose with `--env-file`.

Copy the examples once on the server:

```bash
cp .env.test.example .env.test
cp .env.prod.example .env.prod
```

Then edit `.env.test` and `.env.prod` with real domains, ports, passwords, admin tokens, GitHub OAuth credentials, and an absolute `MOONCRAFT_HOST_DATA_DIR`. OpenRouter keys are managed from the admin page after startup. GitHub OAuth is required because it is the only supported sign-in provider.

Create the data directories before starting Compose:

```bash
sudo mkdir -p /srv/mooncraft/test/data /srv/mooncraft/prod/data
sudo chown -R "$USER:$USER" /srv/mooncraft/test /srv/mooncraft/prod
```

If you previously deployed a version that used the old `mooncraft-runtime` named volume, copy it once into the new host data directory before recreating the app container:

```bash
docker run --rm \
  -v mooncraft-test_mooncraft-runtime:/from:ro \
  -v /srv/mooncraft/test/data:/to \
  alpine sh -c 'cp -a /from/. /to/'

docker run --rm \
  -v mooncraft-prod_mooncraft-runtime:/from:ro \
  -v /srv/mooncraft/prod/data:/to \
  alpine sh -c 'cp -a /from/. /to/'
```

Skip the matching command if that environment has no old runtime volume.

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
just deploy-test
```

This starts Compose with `--wait`. It returns only after PostgreSQL and MoonCraft report healthy, or fails if either service cannot become healthy.

If `.env.test` binds to a different port, use that port in the health check. For example, the committed example uses `127.0.0.1:18089`:

```bash
curl -fsS http://127.0.0.1:18089/api/health
```

## Production Deployment

The production environment uses [docker-compose.prod.yml](../docker-compose.prod.yml).

Default host port: `8080`

```bash
just deploy-prod
```

This starts Compose with `--wait`. It returns only after PostgreSQL and MoonCraft report healthy, or fails if either service cannot become healthy.

If `.env.prod` binds to a different port, use that port in the health check. For example, the committed example uses `127.0.0.1:8089`:

```bash
curl -fsS http://127.0.0.1:8089/api/health
```

## AI Key Pool

Users do not configure LLM providers or API keys.

Admins use the admin page at `/admin` to inspect users, manage projects, inspect recent runs, configure named secrets, and configure runtimes. Browser access to `/admin` redirects to `/admin/login` until the operator enters `MOONCRAFT_ADMIN_TOKEN`; the server stores an HTTP-only admin session cookie after a successful login. Runtime JSON declares which secret names it needs, and the worker injects only those declared secrets into the isolated agent runtime container for that run. Secret values are accepted on create/update and are never returned by the API; list responses show only a masked hint.

The runtime model picker loads the live OpenRouter text model catalog from `GET https://openrouter.ai/api/v1/models` using the `mooncraft_ai_api_key` admin Secret, then saves the selected default model and allowed model list in SQLite.

Open the admin page in a browser:

```text
https://craft-test.moonbitlang.com/admin
https://craft.moonbitlang.com/admin
```

Use `MOONCRAFT_ADMIN_TOKEN` from the environment file on the `/admin/login` page.

The admin API can inspect configured secrets and models:

```bash
curl -fsS -H "Authorization: Bearer $MOONCRAFT_ADMIN_TOKEN" \
  "$MOONCRAFT_PUBLIC_BASE_URL/api/admin/secrets"
curl -fsS -H "Authorization: Bearer $MOONCRAFT_ADMIN_TOKEN" \
  "$MOONCRAFT_PUBLIC_BASE_URL/api/admin/ai/models"
curl -fsS -H "Authorization: Bearer $MOONCRAFT_ADMIN_TOKEN" \
  "$MOONCRAFT_PUBLIC_BASE_URL/api/admin/ai/usages/recent/20"
```

## Reverse Proxy

Put Caddy, Nginx, or an AWS load balancer in front of the host ports.

Typical routing:

- `https://craft-test.moonbitlang.com` -> `127.0.0.1:18089`
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

just deploy-test
```

Upgrade production:

```bash
git pull
just build-mooncraft-image mooncraft:local linux/amd64

just deploy-prod
```

If an official built-in Runtime image changes, update the matching manifest under `runtime/builtin/`, rebuild the MoonCraft image, and run the matching deploy command. If an admin-created Runtime image changes, update that Runtime from the admin page.

If a host previously cached the wrong-architecture runtime image, remove and repull it after upgrading:

```bash
docker image rm docker.io/moonbitcloud/mooncraft-agent-runtime:0.1.1 || true
just deploy-prod
```

Plain `docker compose down` preserves named volumes and host bind-mounted data, but creates extra downtime. Use it only when intentionally stopping a stack. Never use `docker compose down -v` unless you intentionally want to delete PostgreSQL volumes. Remove `${MOONCRAFT_HOST_DATA_DIR}` only when you intentionally want to delete MoonCraft runtime caches and agent session homes.

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
GET /api/admin/users/recent/<limit>
GET /api/admin/users/<user-id>
GET /api/admin/users/<user-id>/projects
GET /api/admin/projects/recent/<limit>
GET /api/admin/projects/<project-id>
GET /api/admin/projects/<project-id>/messages
DELETE /api/admin/projects/<project-id>
```

`<limit>` is clamped to `1..200`. Admin project deletion uses the same cleanup path as user project deletion and refuses to delete a project while it is running. These endpoints are for operators only; do not expose the admin token to normal users.

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

Do not use `down -v` unless you intentionally want to delete PostgreSQL volumes. Do not remove `${MOONCRAFT_HOST_DATA_DIR}` unless you intentionally want to delete MoonCraft runtime caches and agent session homes.

## Data

Compose creates named volumes:

- `mooncraft-postgres` for PostgreSQL data

Compose also bind-mounts `${MOONCRAFT_HOST_DATA_DIR}` to `/app/data`.

For the current single-node deployment, preserve both the PostgreSQL volume and the host data directory. PostgreSQL stores users, projects, messages, runs, and workspace snapshots. The host data directory stores local runtime caches and Codex session homes, and it must be visible to sibling agent runtime containers through host bind mounts.

Before treating this as hardened production, define backup and restore for PostgreSQL and the MoonCraft host data directory.

## Validation

After deployment:

```bash
curl -fsS http://127.0.0.1:8080/api/health
```

Then verify through the public URL:

```bash
curl -fsS https://your-domain.com/api/health
```

For an opt-in real agent smoke test from the repo root:

```bash
export MOONCRAFT_AGENT_SMOKE_MODEL=openai/gpt-5.4-mini
export OPENROUTER_API_KEY='your-test-key'
just agent-smoke
```

This spends real provider quota. The smoke script uses the admin API to save the key into the running test server; it does not pass the key as a MoonCraft service environment variable.

## Current Limits

This Compose deployment is a single-node deployment. It is suitable for test, staging, and early production validation, but it is not yet a horizontally scalable architecture.

Known limits:

- the app container has access to the host Docker socket
- generated previews run on the same host
- Codex session homes are file-backed under the MoonCraft host data directory
- host data directory backups are still operator-managed
- no hard per-user resource quotas are enforced yet
