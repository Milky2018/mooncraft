#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_agent_runtime_image="${1:-$(cat "$repo_root/config/agent_runtime_image.txt")}"
agent_runtime_image="${MOONCRAFT_AGENT_SMOKE_RUNTIME_IMAGE:-$default_agent_runtime_image}"

model="${MOONCRAFT_AGENT_SMOKE_MODEL:-gpt-5.4-mini}"
if [[ -n "${MOONCRAFT_AGENT_SMOKE_KEY_REF:-}" ]]; then
  key_ref="$MOONCRAFT_AGENT_SMOKE_KEY_REF"
elif [[ -n "${MOONCRAFT_AGENT_SMOKE_API_KEY:-}" ]]; then
  key_ref="MOONCRAFT_AGENT_SMOKE_API_KEY"
else
  key_ref="OPENROUTER_API_KEY"
fi
api_key="${!key_ref:-}"
admin_token="${MOONCRAFT_AGENT_SMOKE_ADMIN_TOKEN:-agent-smoke-admin-token}"

echo "Registering smoke Runtime image: $agent_runtime_image"
echo "Using smoke model hint: $model"
echo "Loading provider key from local shell variable: $key_ref"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for the real agent smoke test." >&2
  exit 1
fi
if [[ -z "$api_key" ]]; then
  echo "Set $key_ref or MOONCRAFT_AGENT_SMOKE_KEY_REF to an environment variable containing the provider API key expected by the smoke Runtime image." >&2
  exit 1
fi

port="${MOONCRAFT_AGENT_SMOKE_PORT:-${MOONCRAFT_SMOKE_PORT:-18081}}"
timeout_seconds="${MOONCRAFT_AGENT_SMOKE_TIMEOUT_SECONDS:-1800}"
base_url="http://127.0.0.1:$port"

if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
  echo "Port $port is already serving a control plane. Stop it first or choose MOONCRAFT_AGENT_SMOKE_PORT." >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/mooncraft-agent-smoke.XXXXXX")"
server_log="$tmp_root/server.log"
cookie_jar="$tmp_root/cookies.txt"
project_id=""
run_id=""
cleanup() {
  if [[ -n "$project_id" && -f "$cookie_jar" ]]; then
    curl -fsS -b "$cookie_jar" -X DELETE "$base_url/api/projects/$project_id" -d '' >/dev/null 2>&1 || true
  fi
  if [[ -n "${server_pid:-}" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_root"
}
trap cleanup EXIT

moon -C . build

MOONCRAFT_APP_MODE=development \
  MOONCRAFT_ENABLE_DEV_AUTH=1 \
  MOONCRAFT_ADMIN_TOKEN="$admin_token" \
  MOONCRAFT_PORT="$port" \
  MOONCRAFT_PUBLIC_BASE_URL="$base_url" \
  MOONCRAFT_RUNTIME_FAKE_MODE= \
  ./_build/native/debug/build/mooncraft/control-plane/control-plane.exe \
  >"$server_log" 2>&1 &
server_pid="$!"

for _ in $(seq 1 120); do
  if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    cat "$server_log" >&2 || true
    exit 1
  fi
  sleep 1
done

curl -fsS \
  -H "Authorization: Bearer $admin_token" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "{\"name\":\"agent_smoke_ai_api_key_$$\",\"value\":\"$api_key\"}" \
  "$base_url/api/admin/secrets" >/dev/null

runtime_config_json="$(
  jq -cn \
    --arg image "$agent_runtime_image" \
    --arg model "$model" \
    --arg secret_source "agent_smoke_ai_api_key_$$" \
    '{
      config_version: 3,
      launcher: {
        kind: "docker",
        image: $image
      },
      env: {
        OPENAI_BASE_URL: "https://openrouter.ai/api/v1",
        MODEL: $model
      },
      secrets: [
        {
          source: $secret_source,
          name: "OPENAI_API_KEY"
        }
      ]
    }'
)"
runtime_request="$(
  jq -cn \
    --arg name "Agent Smoke Runtime" \
    --arg config_json "$runtime_config_json" \
    '{name: $name, config_json: $config_json, enabled: true, is_default: true}'
)"
runtime_response="$(
  curl -fsS \
    -H "Authorization: Bearer $admin_token" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$runtime_request" \
    "$base_url/api/admin/runtimes"
)"
runtime_id="$(printf '%s' "$runtime_response" | jq -r '.id')"

user_email="agent-smoke-$(date +%s)-$$@example.com"
curl -fsS \
  -c "$cookie_jar" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$user_email\",\"display_name\":\"Agent Smoke\"}" \
  "$base_url/api/dev/auth/session" >/dev/null

project_response="$(
  curl -fsS \
    -b "$cookie_jar" \
    -H "Content-Type: application/json" \
    -d "{\"display_name\":\"Agent Smoke Todo\",\"runtime_id\":\"$runtime_id\"}" \
    "$base_url/api/projects"
)"
project_id="$(printf '%s' "$project_response" | jq -r '.project.id')"

run_response="$(
  curl -fsS \
    -b "$cookie_jar" \
    -H "Content-Type: application/json" \
    -d '{"content":"Build a simple todo list app with a live web page. Keep it small and make sure the preview works."}' \
    "$base_url/api/projects/$project_id/runs"
)"
run_id="$(printf '%s' "$run_response" | jq -r '.run.run_id')"

deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  run_json="$(curl -fsS -b "$cookie_jar" "$base_url/api/projects/$project_id/runs/$run_id")"
  state="$(printf '%s' "$run_json" | jq -r '.state')"
  case "$state" in
    Succeeded | succeeded)
      project_json="$(curl -fsS -b "$cookie_jar" "$base_url/api/projects/$project_id")"
      preview_url="$(printf '%s' "$project_json" | jq -r '.preview.url // empty')"
      if [[ -z "$preview_url" ]]; then
        echo "Run succeeded without a preview URL." >&2
        printf '%s\n' "$project_json" >&2
        exit 1
      fi
      curl -fsS "$base_url$preview_url" >/dev/null
      echo "Real agent smoke passed: project=$project_id run=$run_id preview=$preview_url"
      exit 0
      ;;
    Failed | failed)
      printf '%s\n' "$run_json" | jq . >&2
      echo "Server log:" >&2
      cat "$server_log" >&2 || true
      exit 1
      ;;
  esac
  sleep 5
done

echo "Timed out waiting for run $run_id" >&2
cat "$server_log" >&2 || true
exit 1
