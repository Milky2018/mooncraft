set shell := ["bash", "-euo", "pipefail", "-c"]

codex_repository := "docker.io/moonbitcloud/codex"
codex_version := "codex-0.125.0-node24"
codex_image := "docker.io/moonbitcloud/codex:codex-0.125.0-node24"

# Show available recipes
default:
  @just --list

# Format all MoonBit code
fmt:
  moon -C . fmt
  moon -C . info --target native
  moon -C . info --target js

# Generate public interface summaries when needed
info:
  moon -C . info

# Compatibility alias for the workspace build
build-sdk profile='debug':
  @just build {{profile}}

# Compatibility alias for the workspace build
build-web profile='debug':
  @just build {{profile}}

# Compatibility alias for the workspace build
build-control-plane profile='debug':
  @just build {{profile}}

# Build the Docker image used by the Codex executor
build-codex-image tag=codex_image platform='linux/amd64':
  docker build --platform {{platform}} -f docker/codex/Dockerfile -t {{tag}} .

# Build the Docker image used by the MoonBit Cloud app runtime
build-moonbitcloud-image tag='moonbitcloud:local' platform='linux/amd64':
  docker build --platform {{platform}} -f docker/moonbitcloud/Dockerfile -t {{tag}} .

# Publish the Codex executor image to Docker Hub for amd64 and arm64
docker-codex-publish repository=codex_repository version=codex_version platforms='linux/amd64,linux/arm64':
  #!/usr/bin/env bash
  set -euo pipefail
  repository="{{repository}}"
  version="{{version}}"
  platforms="{{platforms}}"
  builder="${MOONBITCLOUD_CODEX_BUILDX_BUILDER:-moonbitcloud-codex-builder}"
  if ! docker buildx inspect "$builder" >/dev/null 2>&1; then
    docker buildx create --name "$builder" --driver docker-container --bootstrap >/dev/null
  else
    docker buildx inspect "$builder" --bootstrap >/dev/null
  fi
  docker buildx build \
    --builder "$builder" \
    --platform "$platforms" \
    -f docker/codex/Dockerfile \
    -t "$repository:$version" \
    -t "$repository:latest" \
    --push \
    .
  docker buildx imagetools inspect "$repository:$version"

# Show the effective Codex runtime configuration
codex-config:
  #!/usr/bin/env bash
  set -euo pipefail
  image="${MOONBITCLOUD_CODEX_DOCKER_IMAGE:-{{codex_image}}}"
  container_home="${MOONBITCLOUD_CODEX_CONTAINER_HOME:-/root}"
  echo "MOONBITCLOUD_CODEX_DOCKER_IMAGE=$image"
  echo "MOONBITCLOUD_CODEX_CONTAINER_HOME=$container_home"
  echo "AI provider/API key/model are configured per user in Account settings."

# Build the whole workspace
build profile='debug': fmt
  @if [ "{{profile}}" = release ]; then moon -C . build --release; else moon -C . build; fi

# Check the registry modules fetched for generated user projects
check-user-project-deps:
  ./scripts/check_user_project_deps.sh

# Check generated user-project dependency fetches inside the Codex runtime image
check-user-project-deps-codex image=codex_image:
  MOONBITCLOUD_CODEX_DEPS_CHECK_DOCKER_IMAGE="{{image}}" ./scripts/check_user_project_deps_in_codex_image.sh

# Serve the app. Examples: `just serve`, `just serve 8107`, `just serve release`, `just serve 8107 release`
serve target='8080' profile='debug':
  #!/usr/bin/env bash
  set -euo pipefail
  target="{{target}}"
  profile="{{profile}}"
  if [[ "$target" == "debug" || "$target" == "release" ]]; then
    profile="$target"
    port="${MOONBITCLOUD_PORT:-8080}"
  else
    port="$target"
  fi
  base_url="http://localhost:$port"
  public_base_url="${MOONBITCLOUD_PUBLIC_BASE_URL:-$base_url}"
  echo "MoonBit Cloud: $base_url"
  if [[ "$profile" == "release" ]]; then
    MOONBITCLOUD_PORT="$port" MOONBITCLOUD_PUBLIC_BASE_URL="$public_base_url" MOONBITCLOUD_BUILD_PROFILE=release \
      moon -C . run --target native --release services/control-plane
  else
    MOONBITCLOUD_PORT="$port" MOONBITCLOUD_PUBLIC_BASE_URL="$public_base_url" MOONBITCLOUD_BUILD_PROFILE=debug \
      moon -C . run --target native services/control-plane
  fi

# Open the app in your browser
open port='8080':
  open http://localhost:{{port}}

# Alias for `serve`
run target='8080' profile='debug':
  @just serve {{target}} {{profile}}

# Build, check generated project dependencies, and run the smoke test
test: build check-user-project-deps smoke

# Run the browser simple-project story and save screenshots under output/playwright/
playwright-story:
  ./scripts/playwright_simple_project_story.sh

# Start a temporary control plane and run a smoke test
smoke:
  #!/usr/bin/env bash
  set -euo pipefail
  port="${MOONBITCLOUD_SMOKE_PORT:-8080}"
  base_url="http://127.0.0.1:$port"
  if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
    echo "Port $port is already serving a control plane. Stop it first or use 'just smoke-running'." >&2
    exit 1
  fi
  tmpdir="$(mktemp -d)"
  log_file="$tmpdir/control-plane.log"
  MOONBITCLOUD_CODEX_FAKE_MODE=smoke MOONBITCLOUD_PORT="$port" MOONBITCLOUD_PUBLIC_BASE_URL="$base_url" moon -C . run --target native services/control-plane >"$log_file" 2>&1 &
  server_pid=$!
  cleanup() {
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT

  for _ in {1..60}; do
    if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  curl -fsS "$base_url/api/health" | grep -q '"ok":true'
  MOONBITCLOUD_CODEX_FAKE_MODE=smoke just smoke-running

# Run the smoke test against an already running control plane
smoke-running:
  #!/usr/bin/env bash
  set -euo pipefail
  port="${MOONBITCLOUD_SMOKE_PORT:-8080}"
  base_url="http://127.0.0.1:$port"
  run_poll_limit="${MOONBITCLOUD_SMOKE_RUN_POLL_LIMIT:-180}"
  tmpdir="$(mktemp -d)"
  cleanup() {
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT
  wait_for_response() {
    local url="$1"
    local needle="$2"
    for _ in {1..20}; do
      if curl -fsS "$url" 2>/dev/null | grep -q "$needle"; then
        return 0
      fi
      sleep 1
    done
    curl -fsS "$url" | grep -q "$needle"
  }
  wait_for_ok() {
    local url="$1"
    for _ in {1..20}; do
      if curl -fsS "$url" >/dev/null 2>&1; then
        return 0
      fi
      sleep 1
    done
    curl -fsS "$url" >/dev/null
  }
  user1_cookie="$tmpdir/user1.cookies"
  user2_cookie="$tmpdir/user2.cookies"
  user1_email="owner-$(date +%s)@example.com"
  user2_email="viewer-$(date +%s)@example.com"
  password="password123"
  outbox="data/control-plane/account-emails.log"
  extract_outbox_token() {
    local email="$1"
    local path_fragment="$2"
    { grep -A8 "to: $email" "$outbox" || true; } \
      | sed -n "s#.*$path_fragment?token=\([^[:space:]]*\).*#\1#p" \
      | tail -n1
  }
  curl -fsS "$base_url/api/health" | grep -q '"ok":true'
  curl -fsS "$base_url/" >/dev/null
  curl -fsS "$base_url/app" >/dev/null
  curl -fsS "$base_url/api/session" | grep -q '"authenticated":false'
  unauth_status="$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/api/projects" || true)"
  if [[ "$unauth_status" != "401" ]]; then
    echo "Expected unauthenticated project access to return 401, got $unauth_status" >&2
    exit 1
  fi

  user1_signup="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
    -X POST "$base_url/api/auth/signup" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user1_email\",\"password\":\"$password\",\"display_name\":\"Owner\"}")"
  printf '%s' "$user1_signup" | grep -q "\"email\":\"$user1_email\""
  printf '%s' "$user1_signup" | grep -q '"email_verified":false'
  verify_token="$(extract_outbox_token "$user1_email" "/auth/email/verify")"
  if [[ -z "$verify_token" ]]; then
    echo "Failed to parse verification token for $user1_email from $outbox" >&2
    exit 1
  fi
  curl -fsS -X POST "$base_url/api/auth/email/verification/confirm" \
    -H 'Content-Type: application/json' \
    -d "{\"token\":\"$verify_token\"}" \
    | grep -q 'Email address verified'
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/session" | grep -q '"email_verified":true'
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/account/ai-settings" | grep -q '"api_key_configured":false'
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
    -X PUT "$base_url/api/account/ai-settings" \
    -H 'Content-Type: application/json' \
    -d '{"provider":"openrouter","model":"openai/gpt-5.5","api_key":"fake-smoke-key"}' \
    | grep -q '"api_key_configured":true'
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/session" | grep -q '"ai_provider":"openrouter"'

  curl -fsS -c "$user2_cookie" -b "$user2_cookie" \
    -X POST "$base_url/api/auth/signup" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user2_email\",\"password\":\"$password\",\"display_name\":\"Viewer\"}" \
    | grep -q "\"email\":\"$user2_email\""
  curl -fsS -c "$user2_cookie" -b "$user2_cookie" \
    -X POST "$base_url/api/auth/email/verification/resend" \
    -d '' \
    | grep -q 'Verification link has been queued'

  create_response="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/projects" -H 'Content-Type: application/json' -d '{"display_name":"Smoke Running"}')"
  project_id="$(printf '%s' "$create_response" | sed -n 's/.*"project":{"id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$project_id" ]]; then
    echo "Failed to parse project id from create response: $create_response" >&2
    exit 1
  fi

  run_response="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/projects/$project_id/runs" -H 'Content-Type: application/json' -d '{"content":"Build a smoke test dashboard"}')"
  run_id="$(printf '%s' "$run_response" | sed -n 's/.*"run":{"run_id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$run_id" ]]; then
    echo "Failed to parse run id from run response: $run_response" >&2
    exit 1
  fi
  final_run=""
  for _ in $(seq 1 "$run_poll_limit"); do
    final_run="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects/$project_id/runs/$run_id")"
    if printf '%s' "$final_run" | grep -q '"state":"Running"'; then
      sleep 1
      continue
    fi
    break
  done
  preview_url="$(printf '%s' "$final_run" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
  if ! printf '%s' "$final_run" | grep -q '"state":"Succeeded"'; then
    echo "Expected first smoke run to succeed, got: $final_run" >&2
    exit 1
  fi
  printf '%s' "$final_run" | grep -q '"healthy":true'
  printf '%s' "$preview_url" | grep -q '^/p/'
  project_detail="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects/$project_id")"
  first_thread_id="$(printf '%s' "$project_detail" | sed -n 's/.*"codex_thread_id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$first_thread_id" ]]; then
    echo "Failed to parse the first codex thread id from project detail: $project_detail" >&2
    exit 1
  fi
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects/$project_id" | grep -q "\"url\":\"$preview_url\""
  user2_status="$(curl -sS -o /dev/null -w '%{http_code}' -c "$user2_cookie" -b "$user2_cookie" "$base_url/api/projects/$project_id" || true)"
  if [[ "$user2_status" != "404" ]]; then
    echo "Expected another user to receive 404 for project access, got $user2_status" >&2
    exit 1
  fi
  if curl -fsS -c "$user2_cookie" -b "$user2_cookie" "$base_url/api/projects" | grep -q "\"id\":\"$project_id\""; then
    echo "Project leaked into another user's project list: $project_id" >&2
    exit 1
  fi
  wait_for_ok "$base_url${preview_url}api/health"
  if [[ -z "${MOONBITCLOUD_DATABASE_URL:-}" ]]; then
    snapshot_count="$(sqlite3 data/control-plane/state-v2.sqlite "SELECT COUNT(*) FROM project_workspace_snapshots WHERE project_id = '$project_id';")"
    [[ "$snapshot_count" == "1" ]]
  fi
  runtime_project_dir="data/runtime/projects/$project_id"
  [[ -d "$runtime_project_dir/workspace" ]]
  rm -rf "$runtime_project_dir/workspace"

  run_response_2="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/projects/$project_id/runs" -H 'Content-Type: application/json' -d '{"content":"Add recovery badge"}')"
  run_id_2="$(printf '%s' "$run_response_2" | sed -n 's/.*"run":{"run_id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$run_id_2" ]]; then
    echo "Failed to parse second run id from run response: $run_response_2" >&2
    exit 1
  fi
  final_run_2=""
  for _ in $(seq 1 "$run_poll_limit"); do
    final_run_2="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects/$project_id/runs/$run_id_2")"
    if printf '%s' "$final_run_2" | grep -q '"state":"Running"'; then
      sleep 1
      continue
    fi
    break
  done
  preview_url_2="$(printf '%s' "$final_run_2" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
  if ! printf '%s' "$final_run_2" | grep -q '"state":"Succeeded"'; then
    echo "Expected second smoke run to succeed, got: $final_run_2" >&2
    exit 1
  fi
  printf '%s' "$final_run_2" | grep -q '"healthy":true'
  project_detail_2="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects/$project_id")"
  second_thread_id="$(printf '%s' "$project_detail_2" | sed -n 's/.*"codex_thread_id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$second_thread_id" ]]; then
    echo "Failed to parse the recovered codex thread id from project detail: $project_detail_2" >&2
    exit 1
  fi
  if [[ "$second_thread_id" == "$first_thread_id" ]]; then
    echo "Expected session recovery to replace the Codex thread id, but it stayed at $first_thread_id" >&2
    exit 1
  fi
  [[ -d "$runtime_project_dir/workspace" ]]
  [[ ! -d "$runtime_project_dir/run-workspaces/$run_id_2" ]]
  grep -q 'Add recovery badge' "$runtime_project_dir/workspace/README.md"
  wait_for_ok "$base_url${preview_url_2}api/health"

  changed_password="password456"
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
    -X POST "$base_url/api/auth/password/change" \
    -H 'Content-Type: application/json' \
    -d "{\"current_password\":\"$password\",\"new_password\":\"$changed_password\"}" \
    | grep -q 'Password changed'
  password="$changed_password"

  curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/auth/logout" -d '' >/dev/null
  logged_out_status="$(curl -sS -o /dev/null -w '%{http_code}' -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects" || true)"
  if [[ "$logged_out_status" != "401" ]]; then
    echo "Expected logged out session to lose project access, got $logged_out_status" >&2
    exit 1
  fi
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
    -X POST "$base_url/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user1_email\",\"password\":\"$password\"}" \
    | grep -q "\"email\":\"$user1_email\""
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects" | grep -q "\"id\":\"$project_id\""

  curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X DELETE "$base_url/api/projects/$project_id" -d '' >/dev/null
  if curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects/$project_id" >/dev/null 2>&1; then
    echo "Project still exists after deletion: $project_id" >&2
    exit 1
  fi
  if curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects" | grep -q "\"id\":\"$project_id\""; then
    echo "Project still appears in the project list after deletion: $project_id" >&2
    exit 1
  fi
  if [[ -z "${MOONBITCLOUD_DATABASE_URL:-}" ]]; then
    snapshot_count_after_delete="$(sqlite3 data/control-plane/state-v2.sqlite "SELECT COUNT(*) FROM project_workspace_snapshots WHERE project_id = '$project_id';")"
    if [[ "$snapshot_count_after_delete" != "0" ]]; then
      echo "Project workspace snapshot still exists after deletion: $project_id" >&2
      exit 1
    fi
  fi
  if [[ -d "data/runtime/projects/$project_id" || -d "data/projects/$project_id" ]]; then
    echo "Project runtime scratch still exists after deletion: $project_id" >&2
    exit 1
  fi

  reset_password="password789"
  curl -fsS -X POST "$base_url/api/auth/password-reset/request" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user1_email\"}" \
    | grep -q 'reset link has been queued'
  reset_token="$(extract_outbox_token "$user1_email" "/auth/password/reset")"
  if [[ -z "$reset_token" ]]; then
    echo "Failed to parse password reset token for $user1_email from $outbox" >&2
    exit 1
  fi
  curl -fsS -X POST "$base_url/api/auth/password-reset/confirm" \
    -H 'Content-Type: application/json' \
    -d "{\"token\":\"$reset_token\",\"password\":\"$reset_password\"}" \
    | grep -q 'Password updated'
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
    -X POST "$base_url/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user1_email\",\"password\":\"$reset_password\"}" \
    | grep -q "\"email\":\"$user1_email\""

# Run an end-to-end smoke test against the real Docker-backed Codex CLI
codex-smoke:
  #!/usr/bin/env bash
  set -euo pipefail
  codex_image="${MOONBITCLOUD_CODEX_DOCKER_IMAGE:-{{codex_image}}}"
  export MOONBITCLOUD_CODEX_DOCKER_IMAGE="$codex_image"
  codex_provider="${MOONBITCLOUD_CODEX_SMOKE_PROVIDER:-openai}"
  codex_model="${MOONBITCLOUD_CODEX_SMOKE_MODEL:-gpt-5.5}"
  codex_api_key="${MOONBITCLOUD_CODEX_SMOKE_API_KEY:-}"
  echo "Using Codex Docker image: $codex_image"
  echo "Using Codex provider: $codex_provider"
  echo "Using Codex model: $codex_model"
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for the real Codex smoke test." >&2
    exit 1
  fi
  if [[ -z "$codex_api_key" ]]; then
    echo "MOONBITCLOUD_CODEX_SMOKE_API_KEY is required for the real Codex smoke test. The test stores it through the user AI settings API before starting a run." >&2
    exit 1
  fi

  port="${MOONBITCLOUD_CODEX_SMOKE_PORT:-${MOONBITCLOUD_SMOKE_PORT:-18081}}"
  timeout_seconds="${MOONBITCLOUD_CODEX_SMOKE_TIMEOUT_SECONDS:-1800}"
  base_url="http://127.0.0.1:$port"
  if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
    echo "Port $port is already serving a control plane. Stop it first or choose MOONBITCLOUD_CODEX_SMOKE_PORT." >&2
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  log_file="$tmpdir/control-plane.log"
  user_cookie="$tmpdir/user.cookies"
  project_id=""
  run_id=""
  cleanup() {
    if [[ -n "$project_id" && -f "$user_cookie" ]]; then
      curl -fsS -c "$user_cookie" -b "$user_cookie" -X DELETE "$base_url/api/projects/$project_id" -d '' >/dev/null 2>&1 || true
    fi
    if [[ -n "${server_pid:-}" ]]; then
      kill "$server_pid" >/dev/null 2>&1 || true
      wait "$server_pid" >/dev/null 2>&1 || true
    fi
    rm -rf "$tmpdir"
  }
  show_artifacts() {
    if [[ -n "$project_id" && -n "$run_id" ]]; then
      artifact_dir="data/runtime/projects/$project_id/artifacts/runs/$run_id"
      echo "Run artifacts: $artifact_dir"
      for artifact in codex.log validation.log last_message.txt; do
        artifact_path="$artifact_dir/$artifact"
        if [[ -f "$artifact_path" ]]; then
          echo
          echo "==> $artifact_path"
          tail -n 120 "$artifact_path" || true
        fi
      done
    fi
    echo
    echo "==> control plane log: $log_file"
    tail -n 160 "$log_file" || true
  }
  fail() {
    echo "$1" >&2
    show_artifacts >&2
    exit 1
  }
  wait_for_ok() {
    local url="$1"
    for _ in {1..60}; do
      if curl -fsS "$url" >/dev/null 2>&1; then
        return 0
      fi
      sleep 1
    done
    curl -fsS "$url" >/dev/null
  }
  trap cleanup EXIT

  MOONBITCLOUD_CODEX_FAKE_MODE= MOONBITCLOUD_PORT="$port" moon -C . run --target native services/control-plane >"$log_file" 2>&1 &
  server_pid=$!
  for _ in {1..60}; do
    if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  curl -fsS "$base_url/api/health" | grep -q '"ok":true' || fail "The control plane did not become healthy on port $port."

  user_email="codex-smoke-$(date +%s)-$$@example.com"
  password="password123"
  curl -fsS -c "$user_cookie" -b "$user_cookie" \
    -X POST "$base_url/api/auth/signup" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user_email\",\"password\":\"$password\",\"display_name\":\"Codex Smoke\"}" \
    | grep -q "\"email\":\"$user_email\"" || fail "Signup failed."
  settings_payload="{\"provider\":\"$codex_provider\",\"model\":\"$codex_model\",\"api_key\":\"$codex_api_key\"}"
  curl -fsS -c "$user_cookie" -b "$user_cookie" \
    -X PUT "$base_url/api/account/ai-settings" \
    -H 'Content-Type: application/json' \
    --data-binary "$settings_payload" \
    | grep -q '"api_key_configured":true' || fail "Saving user AI settings failed."

  create_response="$(curl -fsS -c "$user_cookie" -b "$user_cookie" -X POST "$base_url/api/projects" -H 'Content-Type: application/json' -d '{"display_name":"Codex Todo Smoke"}')"
  project_id="$(printf '%s' "$create_response" | sed -n 's/.*"project":{"id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$project_id" ]]; then
    fail "Failed to parse project id from create response: $create_response"
  fi

  run_response="$(curl -fsS -c "$user_cookie" -b "$user_cookie" -X POST "$base_url/api/projects/$project_id/runs" -H 'Content-Type: application/json' -d '{"content":"Build a Todo List App in MoonBit. It should let users create todo items, list them, mark them complete, delete them, and present a simple usable preview UI."}')"
  run_id="$(printf '%s' "$run_response" | sed -n 's/.*"run":{"run_id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$run_id" ]]; then
    fail "Failed to parse run id from run response: $run_response"
  fi

  final_run=""
  deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    final_run="$(curl -fsS -c "$user_cookie" -b "$user_cookie" "$base_url/api/projects/$project_id/runs/$run_id" || true)"
    if [[ -n "$final_run" ]] && ! printf '%s' "$final_run" | grep -q '"state":"Running"'; then
      break
    fi
    sleep 5
  done
  if [[ -z "$final_run" ]]; then
    fail "Codex smoke did not receive a final run response."
  fi
  if printf '%s' "$final_run" | grep -q '"state":"Running"'; then
    fail "Codex smoke timed out after ${timeout_seconds}s waiting for run $run_id."
  fi
  printf '%s' "$final_run" | grep -q '"state":"Succeeded"' || fail "Codex smoke run did not succeed: $final_run"
  printf '%s' "$final_run" | grep -q '"healthy":true' || fail "Codex smoke run did not report a healthy preview: $final_run"
  preview_url="$(printf '%s' "$final_run" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
  printf '%s' "$preview_url" | grep -q '^/p/' || fail "Codex smoke did not return a preview URL: $final_run"

  project_detail="$(curl -fsS -c "$user_cookie" -b "$user_cookie" "$base_url/api/projects/$project_id")"
  thread_id="$(printf '%s' "$project_detail" | sed -n 's/.*"codex_thread_id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$thread_id" ]]; then
    fail "Codex smoke did not persist a codex_thread_id: $project_detail"
  fi
  snapshot_count="$(sqlite3 data/control-plane/state-v2.sqlite "SELECT COUNT(*) FROM project_workspace_snapshots WHERE project_id = '$project_id';")"
  [[ "$snapshot_count" == "1" ]] || fail "Codex smoke did not persist a database workspace snapshot."
  [[ -d "data/runtime/projects/$project_id/workspace" ]] || fail "Codex smoke did not restore the canonical workspace cache."
  [[ ! -d "data/runtime/projects/$project_id/run-workspaces/$run_id" ]] || fail "Codex smoke left the run workspace behind."
  wait_for_ok "$base_url${preview_url}api/health" || fail "Codex smoke preview health endpoint was not reachable."

  curl -fsS -c "$user_cookie" -b "$user_cookie" -X DELETE "$base_url/api/projects/$project_id" -d '' >/dev/null
  project_id=""
  echo "Codex smoke passed: Todo List App run $run_id produced preview $preview_url"

# Run a browser smoke test for auth, theme, project lifecycle, and run failure recovery
ui-smoke port='8094':
  scripts/playwright_full_smoke.sh {{port}}

# Remove local build outputs
clean:
  rm -rf _build
