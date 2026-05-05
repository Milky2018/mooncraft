#!/usr/bin/env bash
set -euo pipefail

default_codex_image="${1:-docker.io/moonbitcloud/codex:codex-0.125.0-node24}"
codex_image="${MOONCRAFT_CODEX_DOCKER_IMAGE:-$default_codex_image}"
export MOONCRAFT_CODEX_DOCKER_IMAGE="$codex_image"
codex_provider="${MOONCRAFT_CODEX_SMOKE_PROVIDER:-openai}"
codex_model="${MOONCRAFT_CODEX_SMOKE_MODEL:-gpt-5.5}"
codex_api_key="${MOONCRAFT_CODEX_SMOKE_API_KEY:-}"

echo "Using Codex Docker image: $codex_image"
echo "Using Codex provider: $codex_provider"
echo "Using Codex model: $codex_model"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for the real Codex smoke test." >&2
  exit 1
fi
if [[ -z "$codex_api_key" ]]; then
  echo "MOONCRAFT_CODEX_SMOKE_API_KEY is required for the real Codex smoke test. The test stores it through the user AI settings API before starting a run." >&2
  exit 1
fi

port="${MOONCRAFT_CODEX_SMOKE_PORT:-${MOONCRAFT_SMOKE_PORT:-18081}}"
timeout_seconds="${MOONCRAFT_CODEX_SMOKE_TIMEOUT_SECONDS:-1800}"
base_url="http://127.0.0.1:$port"

if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
  echo "Port $port is already serving a control plane. Stop it first or choose MOONCRAFT_CODEX_SMOKE_PORT." >&2
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

MOONCRAFT_CODEX_FAKE_MODE= \
  MOONCRAFT_PORT="$port" \
  moon -C . run --target native services/control-plane >"$log_file" 2>&1 &
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
