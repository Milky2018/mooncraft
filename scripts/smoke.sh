#!/usr/bin/env bash
set -euo pipefail

port="${MOONCRAFT_SMOKE_PORT:-8080}"
base_url="http://127.0.0.1:$port"

if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
  echo "Port $port is already serving a control plane. Stop it first or use 'just smoke-running'." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
log_file="$tmpdir/control-plane.log"
admin_token="${MOONCRAFT_SMOKE_ADMIN_TOKEN:-smoke-admin-token}"

moon -C . build

MOONCRAFT_RUNTIME_FAKE_MODE=smoke \
  MOONCRAFT_ENABLE_DEV_AUTH=1 \
  MOONCRAFT_ADMIN_TOKEN="$admin_token" \
  MOONCRAFT_PORT="$port" \
  MOONCRAFT_PUBLIC_BASE_URL="$base_url" \
  ./_build/native/debug/build/mooncraft/control-plane/control-plane.exe >"$log_file" 2>&1 &
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
MOONCRAFT_RUNTIME_FAKE_MODE=smoke \
  MOONCRAFT_SMOKE_ADMIN_TOKEN="$admin_token" \
  ./scripts/smoke_running.sh
