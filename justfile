set shell := ["bash", "-euo", "pipefail", "-c"]

codex_repository := "docker.io/moonbitcloud/codex"
codex_version := "codex-0.125.0-node24"
codex_image := "docker.io/moonbitcloud/codex:codex-0.125.0-node24"

# Show available recipes
default:
  @just --list

# Format MoonBit code and regenerate public interfaces
fmt:
  moon -C . fmt
  moon -C . info --target native
  moon -C . info --target js

# Build the whole workspace. Usage: `just build` or `just build release`
build profile='debug': fmt
  @if [ "{{profile}}" = release ]; then moon -C . build --release; else moon -C . build; fi

# Serve locally. Usage: `just serve`, `just serve 8107`, or `just serve release`
serve target='8080' profile='debug':
  ./scripts/serve.sh "{{target}}" "{{profile}}"

# Alias for `serve`
run target='8080' profile='debug':
  @just serve {{target}} {{profile}}

# Open the local app in the browser
open port='8080':
  open http://localhost:{{port}}

# Build, dependency-check, and run the fake-agent API smoke test
test: build check-user-project-deps smoke

# Start a temporary control plane and run the fake-agent API smoke test
smoke:
  ./scripts/smoke.sh

# Run the fake-agent API smoke test against an already running control plane
smoke-running:
  ./scripts/smoke_running.sh

# Run a browser smoke test for auth, theme, project lifecycle, and recovery
ui-smoke port='8094':
  scripts/playwright_full_smoke.sh {{port}}

# Run the browser simple-project story and save screenshots
playwright-story:
  ./scripts/playwright_simple_project_story.sh

# Run an opt-in browser story against real Docker-backed Codex
playwright-real-agent-story:
  ./scripts/playwright_real_agent_story.sh

# Run an opt-in real Docker-backed Codex smoke test
codex-smoke:
  ./scripts/codex_smoke.sh "{{codex_image}}"

# Build the Docker image used by the Mooncraft app runtime
build-mooncraft-image tag='mooncraft:local' platform='linux/amd64':
  docker build --platform {{platform}} -f docker/mooncraft/Dockerfile -t {{tag}} .

# Build the Docker image used by the Codex executor
build-codex-image tag=codex_image platform='linux/amd64':
  docker build --platform {{platform}} -f docker/codex/Dockerfile -t {{tag}} .

# Publish the Codex executor image to Docker Hub
docker-codex-publish repository=codex_repository version=codex_version platforms='linux/amd64,linux/arm64':
  ./scripts/docker_codex_publish.sh "{{repository}}" "{{version}}" "{{platforms}}"

# Show the effective Codex runtime configuration
codex-config:
  @echo "MOONCRAFT_CODEX_DOCKER_IMAGE=${MOONCRAFT_CODEX_DOCKER_IMAGE:-{{codex_image}}}"
  @echo "MOONCRAFT_CODEX_CONTAINER_HOME=${MOONCRAFT_CODEX_CONTAINER_HOME:-/root}"
  @echo "AI provider/API key/model are configured per user in Account settings."

# Check registry modules fetched for generated user projects
check-user-project-deps:
  ./scripts/check_user_project_deps.sh

# Check generated project dependencies inside the Codex runtime image
check-user-project-deps-codex image=codex_image:
  MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_IMAGE="{{image}}" ./scripts/check_user_project_deps_in_codex_image.sh

# Start the test Compose environment
deploy-test:
  docker compose -f docker-compose.test.yml up -d

# Start the production Compose environment
deploy-prod:
  docker compose -f docker-compose.prod.yml up -d

# Follow test logs
logs-test:
  docker compose -f docker-compose.test.yml logs -f mooncraft

# Follow production logs
logs-prod:
  docker compose -f docker-compose.prod.yml logs -f mooncraft

# Remove local build outputs
clean:
  rm -rf _build
