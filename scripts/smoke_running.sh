#!/usr/bin/env bash
set -euo pipefail

port="${MOONCRAFT_SMOKE_PORT:-8080}"
base_url="http://127.0.0.1:$port"
run_poll_limit="${MOONCRAFT_SMOKE_RUN_POLL_LIMIT:-180}"
tmpdir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

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

dev_sign_in() {
  local cookie_file="$1"
  local email="$2"
  local display_name="$3"
  curl -fsS -c "$cookie_file" -b "$cookie_file" \
    -X POST "$base_url/api/dev/auth/session" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"display_name\":\"$display_name\"}" \
    | grep -q "\"email\":\"$email\""
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

dev_sign_in "$user1_cookie" "$user1_email" "Owner"
curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/session" | grep -q '"email_verified":true'
curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/account/ai-settings" | grep -q '"api_key_configured":false'
curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/account/ai-model-options/openrouter" | grep -q '"provider":"openrouter"'
curl -fsS -c "$user1_cookie" -b "$user1_cookie" \
  -X PUT "$base_url/api/account/ai-settings" \
  -H 'Content-Type: application/json' \
  -d '{"provider":"openrouter","model":"openai/gpt-5.5","api_key":"fake-smoke-key"}' \
  | grep -q '"api_key_configured":true'
curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/session" | grep -q '"ai_provider":"openrouter"'

dev_sign_in "$user2_cookie" "$user2_email" "Viewer"

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

if [[ -z "${MOONCRAFT_DATABASE_URL:-}" ]]; then
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
grep -q 'Add recovery badge' "$runtime_project_dir/workspace/README.md"
wait_for_ok "$base_url${preview_url_2}api/health"

curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/auth/logout" -d '' >/dev/null
logged_out_status="$(curl -sS -o /dev/null -w '%{http_code}' -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects" || true)"
if [[ "$logged_out_status" != "401" ]]; then
  echo "Expected logged out session to lose project access, got $logged_out_status" >&2
  exit 1
fi
dev_sign_in "$user1_cookie" "$user1_email" "Owner"
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
if [[ -z "${MOONCRAFT_DATABASE_URL:-}" ]]; then
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
