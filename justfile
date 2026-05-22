set shell := ["bash", "-euo", "pipefail", "-c"]

agent_runtime_image := `cat config/agent_runtime_image.txt`
agent_runtime_repository := `sed 's/:[^:]*$//' config/agent_runtime_image.txt`
agent_runtime_version := `sed 's/.*://' config/agent_runtime_image.txt`

# Show available recipes
default:
  @just --list

# Format MoonBit code and regenerate public interfaces
fmt:
  moon fmt
  moon info --target native
  moon info --target js

# Build the whole workspace. Usage: `just build` or `just build release`
build profile='debug': fmt
  @if [ "{{profile}}" = release ]; then moon build --release; else moon build; fi

# Serve locally. Usage: `just serve`, `just serve 8107`, or `just serve release`
serve target='8080' profile='':
  @if [ -n "{{profile}}" ]; then ./scripts/serve.sh "{{target}}" "{{profile}}"; else ./scripts/serve.sh "{{target}}"; fi

# Alias for `serve`
run target='8080' profile='':
  @if [ -n "{{profile}}" ]; then just serve "{{target}}" "{{profile}}"; else just serve "{{target}}"; fi

# Open the local app in the browser
open port='8080':
  open http://localhost:{{port}}

# Build and run the fake-agent API smoke test
test: build smoke

# Start a temporary control plane and run the fake-agent API smoke test
smoke:
  ./scripts/smoke.sh

# Run the fake-agent API smoke test against a dev-auth-enabled control plane
smoke-running:
  ./scripts/smoke_running.sh

# Run a browser smoke test for auth, theme, project lifecycle, and recovery
ui-smoke port='8094':
  ./scripts/playwright_full_smoke.sh {{port}}

# Run the browser simple-project story and save screenshots
playwright-story:
  ./scripts/playwright_simple_project_story.sh

# Run an opt-in browser story against the real Docker-backed agent runtime
playwright-real-agent-story:
  ./scripts/playwright_real_agent_story.sh

# Run an opt-in real Docker-backed default-agent smoke test
agent-smoke:
  ./scripts/agent_smoke.sh "{{agent_runtime_image}}"

# Compatibility alias for the old real-agent smoke recipe name
codex-smoke:
  @just agent-smoke

# Build the Docker image used by the MoonCraft app runtime
build-mooncraft-image tag='mooncraft:local' platform='linux/amd64':
  ./scripts/docker_mooncraft_build.sh "{{tag}}" "{{platform}}"

# Build the Docker image used by MoonCraft agent workers for the Docker host architecture
build-agent-runtime-image repository=agent_runtime_repository version=agent_runtime_version platform='host':
  ./scripts/publish_agent_runtime_image.sh build "{{repository}}" "{{version}}" "{{platform}}"

# Build local architecture-suffixed agent runtime images for both supported platforms
build-agent-runtime-images repository=agent_runtime_repository version=agent_runtime_version platforms='linux/amd64,linux/arm64':
  ./scripts/publish_agent_runtime_image.sh build-all "{{repository}}" "{{version}}" "{{platforms}}"

# Build and publish the multi-architecture agent runtime image to Docker Hub
docker-agent-runtime-publish repository=agent_runtime_repository version=agent_runtime_version platforms='linux/amd64,linux/arm64':
  ./scripts/publish_agent_runtime_image.sh publish "{{repository}}" "{{version}}" "{{platforms}}"

# Show where Runtime configuration is defined
agent-runtime-config:
  @echo "Official Runtime manifests: runtime/builtin/*.json"
  @echo "Admin-created Runtime manifests: /admin Runtimes"
  @echo "Runtime images, commands, container homes, provider metadata, and secret bindings are selected from each project Runtime snapshot."

# Check required tools and knowledge assets inside the agent runtime image
check-agent-runtime-image image=agent_runtime_image:
  ./scripts/check_agent_runtime_image.sh "{{image}}"

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
