set shell := ["bash", "-euo", "pipefail", "-c"]

# Show available recipes
default:
  @just --list

# Format all MoonBit code
fmt:
  moon fmt --manifest-path moon.work
  moon info --manifest-path moon.work --target native

# Build the shared SDK package
build-sdk profile='debug':
  @if [ "{{profile}}" = release ]; then moon build --manifest-path moon.work packages/sdk --target native --release; else moon build --manifest-path moon.work packages/sdk --target native; fi

# Build the Rabbita web frontend bundle
build-web profile='debug':
  @if [ "{{profile}}" = release ]; then moon build --manifest-path moon.work apps/web --target js --release; else moon build --manifest-path moon.work apps/web --target js; fi

# Build the local control plane
build-control-plane profile='debug':
  @if [ "{{profile}}" = release ]; then moon build --manifest-path moon.work services/control-plane --target native --release; else moon build --manifest-path moon.work services/control-plane --target native; fi

# Build the whole workspace
build profile='debug': fmt
  @just build-sdk {{profile}}
  @just build-web {{profile}}
  @just build-control-plane {{profile}}

# Serve the app at http://localhost:8080
serve profile='debug':
  @echo "MoonBit Cloud: http://localhost:8080"
  @if [ "{{profile}}" = release ]; then MOONBITCLOUD_BUILD_PROFILE=release moon run --manifest-path moon.work services/control-plane --target native --release; else MOONBITCLOUD_BUILD_PROFILE=debug moon run --manifest-path moon.work services/control-plane --target native; fi

# Open the app in your browser
open:
  open http://localhost:8080

# Alias for `serve`
run profile='debug':
  @just serve {{profile}}

# Build and run the smoke test
test: build smoke

# Start a temporary control plane and run a smoke test
smoke:
  #!/usr/bin/env bash
  set -euo pipefail
  if curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
    echo "Port 8080 is already serving a control plane. Stop it first or use 'just smoke-running'." >&2
    exit 1
  fi
  tmpdir="$(mktemp -d)"
  log_file="$tmpdir/control-plane.log"
  moon run --manifest-path moon.work services/control-plane --target native >"$log_file" 2>&1 &
  server_pid=$!
  cleanup() {
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT

  for _ in {1..20}; do
    if curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  curl -fsS http://127.0.0.1:8080/api/health | grep -q '"ok":true'
  just smoke-running

# Run the smoke test against an already running control plane
smoke-running:
  #!/usr/bin/env bash
  set -euo pipefail
  tmpdir="$(mktemp -d)"
  cleanup() {
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT
  user1_cookie="$tmpdir/user1.cookies"
  user2_cookie="$tmpdir/user2.cookies"
  user1_email="owner-$(date +%s)@example.com"
  user2_email="viewer-$(date +%s)@example.com"
  password="password123"
  curl -fsS http://127.0.0.1:8080/api/health | grep -q '"ok":true'
  curl -fsS http://127.0.0.1:8080/ >/dev/null
  curl -fsS http://127.0.0.1:8080/app >/dev/null
  curl -fsS http://127.0.0.1:8080/api/session | grep -q '"authenticated":false'
  unauth_status="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/api/projects || true)"
  if [[ "$unauth_status" != "401" ]]; then
    echo "Expected unauthenticated project access to return 401, got $unauth_status" >&2
    exit 1
  fi

  curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
    -X POST http://127.0.0.1:8080/api/auth/signup \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user1_email\",\"password\":\"$password\",\"display_name\":\"Owner\"}" \
    | grep -q "\"email\":\"$user1_email\""

  curl -fsS -c "$user2_cookie" -b "$user2_cookie" \
    -X POST http://127.0.0.1:8080/api/auth/signup \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user2_email\",\"password\":\"$password\",\"display_name\":\"Viewer\"}" \
    | grep -q "\"email\":\"$user2_email\""

  create_response="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST http://127.0.0.1:8080/api/projects -H 'Content-Type: application/json' -d '{"display_name":"Smoke Running"}')"
  project_id="$(printf '%s' "$create_response" | sed -n 's/.*"project":{"id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$project_id" ]]; then
    echo "Failed to parse project id from create response: $create_response" >&2
    exit 1
  fi

  run_response="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST http://127.0.0.1:8080/api/projects/$project_id/runs -H 'Content-Type: application/json' -d '{"content":"Build a smoke test dashboard"}')"
  preview_url="$(printf '%s' "$run_response" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
  printf '%s' "$run_response" | grep -q '"state":"Succeeded"'
  printf '%s' "$run_response" | grep -q '"healthy":true'
  printf '%s' "$preview_url" | grep -q '^/p/'
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" "http://127.0.0.1:8080/api/projects/$project_id" | grep -q "\"url\":\"$preview_url\""
  user2_status="$(curl -sS -o /dev/null -w '%{http_code}' -c "$user2_cookie" -b "$user2_cookie" "http://127.0.0.1:8080/api/projects/$project_id" || true)"
  if [[ "$user2_status" != "404" ]]; then
    echo "Expected another user to receive 404 for project access, got $user2_status" >&2
    exit 1
  fi
  if curl -fsS -c "$user2_cookie" -b "$user2_cookie" "http://127.0.0.1:8080/api/projects" | grep -q "\"id\":\"$project_id\""; then
    echo "Project leaked into another user's project list: $project_id" >&2
    exit 1
  fi
  curl -fsS "http://127.0.0.1:8080$preview_url" | grep -q 'MoonBit Cloud Preview'
  curl -fsS "http://127.0.0.1:8080${preview_url}api/health" | grep -q '"ok":true'

  curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST http://127.0.0.1:8080/api/auth/logout >/dev/null
  logged_out_status="$(curl -sS -o /dev/null -w '%{http_code}' -c "$user1_cookie" -b "$user1_cookie" http://127.0.0.1:8080/api/projects || true)"
  if [[ "$logged_out_status" != "401" ]]; then
    echo "Expected logged out session to lose project access, got $logged_out_status" >&2
    exit 1
  fi
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
    -X POST http://127.0.0.1:8080/api/auth/login \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$user1_email\",\"password\":\"$password\"}" \
    | grep -q "\"email\":\"$user1_email\""
  curl -fsS -c "$user1_cookie" -b "$user1_cookie" "http://127.0.0.1:8080/api/projects" | grep -q "\"id\":\"$project_id\""

  curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X DELETE "http://127.0.0.1:8080/api/projects/$project_id" >/dev/null
  if curl -fsS -c "$user1_cookie" -b "$user1_cookie" "http://127.0.0.1:8080/api/projects/$project_id" >/dev/null 2>&1; then
    echo "Project still exists after deletion: $project_id" >&2
    exit 1
  fi
  if curl -fsS -c "$user1_cookie" -b "$user1_cookie" "http://127.0.0.1:8080/api/projects" | grep -q "\"id\":\"$project_id\""; then
    echo "Project still appears in the project list after deletion: $project_id" >&2
    exit 1
  fi
  if [[ -d "data/projects/$project_id" ]]; then
    echo "Project workspace still exists after deletion: data/projects/$project_id" >&2
    exit 1
  fi

# Remove local build outputs
clean:
  rm -rf _build
