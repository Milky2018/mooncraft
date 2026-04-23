#!/usr/bin/env bash
set -euo pipefail

port="${1:-8094}"
base_url="http://127.0.0.1:${port}"
pwcli="${CODEX_HOME:-$HOME/.codex}/skills/playwright/scripts/playwright_cli.sh"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required for the bundled Playwright CLI wrapper." >&2
  exit 1
fi

if [[ ! -x "$pwcli" ]]; then
  echo "Playwright CLI wrapper not found at $pwcli" >&2
  exit 1
fi

if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
  echo "Port ${port} is already serving a control plane. Stop it first." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
log_file="${tmpdir}/control-plane.log"
server_pid=""

cleanup() {
  "$pwcli" close >/dev/null 2>&1 || true
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

MOONBITCLOUD_PORT="$port" \
MOONBITCLOUD_BUILD_PROFILE=debug \
MOONBITCLOUD_CODEX_DOCKER_IMAGE= \
moon run --manifest-path moon.work services/control-plane --target native \
  >"$log_file" 2>&1 &
server_pid=$!

for _ in {1..30}; do
  if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "${base_url}/api/health" | grep -q '"ok":true'
"$pwcli" open "$base_url" >/dev/null

if ! run_output="$(
  MOONBITCLOUD_PLAYWRIGHT_BASE_URL="$base_url" \
    "$pwcli" run-code --filename scripts/playwright_full_smoke.js --raw 2>&1
)"
then
  printf '%s\n' "$run_output"
  echo
  echo "Control plane log:" >&2
  sed -n '1,220p' "$log_file" >&2
  exit 1
fi
printf '%s\n' "$run_output"
if printf '%s\n' "$run_output" | grep -q '^### Error'
then
  echo
  echo "Control plane log:" >&2
  sed -n '1,220p' "$log_file" >&2
  exit 1
fi
