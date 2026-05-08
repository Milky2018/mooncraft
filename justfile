set shell := ["bash", "-euo", "pipefail", "-c"]

agent_runtime_repository := "docker.io/moonbitcloud/mooncraft-agent-runtime"
agent_runtime_version := `sed 's/.*://' config/agent_runtime_image.txt`
agent_runtime_image := `cat config/agent_runtime_image.txt`

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

# Run the fake-agent API smoke test against a dev-auth-enabled control plane
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
  ./scripts/codex_smoke.sh "{{agent_runtime_image}}"

# Build the Docker image used by the Mooncraft app runtime
build-mooncraft-image tag='mooncraft:local' platform='linux/amd64':
  docker build --platform {{platform}} -f docker/mooncraft/Dockerfile -t {{tag}} .

# Build the Docker image used by Mooncraft agent workers
build-agent-runtime-image tag=agent_runtime_image platform='linux/amd64':
  docker build --platform {{platform}} -f docker/agent-runtime/Dockerfile -t {{tag}} .

# Publish the agent runtime image to Docker Hub
docker-agent-runtime-publish repository=agent_runtime_repository version=agent_runtime_version platforms='linux/amd64,linux/arm64':
  ./scripts/docker_agent_runtime_publish.sh "{{repository}}" "{{version}}" "{{platforms}}"

# Show the effective agent runtime configuration
agent-runtime-config:
  @echo "MOONCRAFT_AGENT_RUNTIME_IMAGE=${MOONCRAFT_AGENT_RUNTIME_IMAGE:-${MOONCRAFT_CODEX_DOCKER_IMAGE:-{{agent_runtime_image}}}}"
  @echo "MOONCRAFT_CODEX_CONTAINER_HOME=${MOONCRAFT_CODEX_CONTAINER_HOME:-/root}"
  @echo "OpenRouter keys and model are configured by admins at /admin."

# Check registry modules fetched for generated user projects
check-user-project-deps:
  ./scripts/check_user_project_deps.sh

# Check generated project dependencies inside the agent runtime image
check-user-project-deps-agent-runtime image=agent_runtime_image:
  MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_IMAGE="{{image}}" ./scripts/check_user_project_deps_in_agent_runtime_image.sh

# Start the test Compose environment
deploy-test:
  ./scripts/deploy_compose.sh .env.test docker-compose.test.yml

# Start the production Compose environment
deploy-prod:
  ./scripts/deploy_compose.sh .env.prod docker-compose.prod.yml

# Follow test logs
logs-test:
  docker compose -f docker-compose.test.yml logs -f mooncraft

# Follow production logs
logs-prod:
  docker compose -f docker-compose.prod.yml logs -f mooncraft

# Remove local build outputs
clean:
  rm -rf _build
