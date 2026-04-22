set shell := ["bash", "-euo", "pipefail", "-c"]

# Show available recipes
default:
  @just --list

# Format all MoonBit code
fmt:
  moon fmt --manifest-path moon.work
  moon info --manifest-path moon.work --target native

# Build the shared SDK package
build-sdk:
  moon build --manifest-path moon.work packages/sdk --target native

# Build the Rabbita web frontend bundle
build-web:
  moon build --manifest-path moon.work apps/web --target js

# Build the local control plane
build-control-plane:
  moon build --manifest-path moon.work services/control-plane --target native

# Build the whole workspace
build: fmt build-sdk build-web build-control-plane

# Serve the app at http://localhost:8080
serve:
  @echo "MoonBit Cloud: http://localhost:8080"
  moon run --manifest-path moon.work services/control-plane --target native

# Open the app in your browser
open:
  open http://localhost:8080

# Alias for `serve`
run:
  @just serve

# Build and run the smoke test
test: build smoke

# Start a temporary control plane and run a smoke test
smoke:
  #!/usr/bin/env bash
  set -euo pipefail
  if curl -fsS http://127.0.0.1:8080/api/projects >/dev/null 2>&1; then
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
    if curl -fsS http://127.0.0.1:8080/api/projects >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  curl -fsS http://127.0.0.1:8080/api/projects >/dev/null
  just smoke-running

# Run the smoke test against an already running control plane
smoke-running:
  #!/usr/bin/env bash
  set -euo pipefail
  curl -fsS http://127.0.0.1:8080/ >/dev/null
  curl -fsS http://127.0.0.1:8080/app >/dev/null
  create_response="$(curl -fsS -X POST http://127.0.0.1:8080/api/projects -H 'Content-Type: application/json' -d '{"display_name":"Smoke Running"}')"
  project_id="$(printf '%s' "$create_response" | sed -n 's/.*"project":{"id":"\([^"]*\)".*/\1/p')"
  if [[ -z "$project_id" ]]; then
    echo "Failed to parse project id from create response: $create_response" >&2
    exit 1
  fi

  run_response="$(curl -fsS -X POST http://127.0.0.1:8080/api/projects/$project_id/messages -H 'Content-Type: application/json' -d '{"content":"Build a smoke test dashboard"}')"
  printf '%s' "$run_response" | grep -q '"state":"Succeeded"'
  printf '%s' "$run_response" | grep -q '"healthy":true'
  curl -fsS "http://127.0.0.1:8080/api/projects/$project_id" | grep -q '"healthy":true'

# Remove local build outputs
clean:
  rm -rf _build
