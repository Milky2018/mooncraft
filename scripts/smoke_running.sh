#!/usr/bin/env bash
set -euo pipefail

port="${MOONCRAFT_SMOKE_PORT:-8080}"
base_url="http://127.0.0.1:$port"
run_poll_limit="${MOONCRAFT_SMOKE_RUN_POLL_LIMIT:-180}"
tmpdir="$(mktemp -d)"
admin_token="${MOONCRAFT_SMOKE_ADMIN_TOKEN:-smoke-admin-token}"

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

register_smoke_runtime() {
  local runtime_config_json='{"config_version":3,"launcher":{"kind":"docker","image":"mooncraft/fake-runtime:smoke"},"env":{},"secrets":{}}'
  local escaped_runtime_config_json="${runtime_config_json//\"/\\\"}"
  local runtime_response
  runtime_response="$(curl -fsS \
    -H "Authorization: Bearer $admin_token" \
    -H 'Content-Type: application/json' \
    -X POST "$base_url/api/admin/runtimes" \
    -d "{\"name\":\"Smoke Runtime $$\",\"config_json\":\"$escaped_runtime_config_json\",\"enabled\":true,\"is_default\":true}")"
  printf '%s' "$runtime_response" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
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

dev_sign_in "$user2_cookie" "$user2_email" "Viewer"

empty_project_status="$(curl -sS -o /dev/null -w '%{http_code}' -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/projects" -H 'Content-Type: application/json' -d '{"display_name":"   "}' || true)"
if [[ "$empty_project_status" != "422" ]]; then
  echo "Expected blank project names to return 422, got $empty_project_status" >&2
  exit 1
fi
curl -fsS \
  -H "Authorization: Bearer $admin_token" \
  "$base_url/api/admin/logs/recent/5" \
  | grep -q '"operation":"create_project"'

smoke_runtime_id="$(register_smoke_runtime)"
if [[ -z "$smoke_runtime_id" ]]; then
  echo "Failed to register a smoke Runtime through the admin API." >&2
  exit 1
fi
curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/runtimes" | grep -q "\"id\":\"$smoke_runtime_id\""

create_response="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/projects" -H 'Content-Type: application/json' -d "{\"display_name\":\"Smoke Running\",\"runtime_id\":\"$smoke_runtime_id\"}")"
project_id="$(printf '%s' "$create_response" | sed -n 's/.*"project":{"id":"\([^"]*\)".*/\1/p')"
if [[ -z "$project_id" ]]; then
  echo "Failed to parse project id from create response: $create_response" >&2
  exit 1
fi
printf '%s' "$create_response" | grep -q '"display_name":"Smoke Running"'
printf '%s' "$create_response" | grep -q '"source_repository"'
printf '%s' "$create_response" | grep -q '"host":"smoke"'
printf '%s' "$create_response" | grep -q '"status":"connected"'

rename_response="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X PUT "$base_url/api/projects/$project_id" -H 'Content-Type: application/json' -d '{"display_name":"Renamed Smoke Project"}')"
printf '%s' "$rename_response" | grep -q '"display_name":"Renamed Smoke Project"'

user2_rename_status="$(curl -sS -o /dev/null -w '%{http_code}' -c "$user2_cookie" -b "$user2_cookie" -X PUT "$base_url/api/projects/$project_id" -H 'Content-Type: application/json' -d '{"display_name":"Leaked Rename"}' || true)"
if [[ "$user2_rename_status" != "404" ]]; then
  echo "Expected another user to receive 404 for project rename, got $user2_rename_status" >&2
  exit 1
fi

run_response="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" -X POST "$base_url/api/projects/$project_id/runs" -H 'Content-Type: application/json' -d '{"content":"Build a smoke test dashboard"}')"
run_id="$(printf '%s' "$run_response" | sed -n 's/.*"run":{"run_id":"\([^"]*\)".*/\1/p')"
if [[ -z "$run_id" ]]; then
  echo "Failed to parse run id from run response: $run_response" >&2
  exit 1
fi
printf '%s' "$run_response" | grep -q '"phase":"RuntimeRunning"'
curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects" | grep -q '"current_run_phase":"RuntimeRunning"'

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
printf '%s' "$final_run" | grep -q '"phase":"NoPhase"'
printf '%s' "$final_run" | grep -q '"healthy":true'
printf '%s' "$preview_url" | grep -q '^/p/'

project_detail="$(curl -fsS -c "$user1_cookie" -b "$user1_cookie" "$base_url/api/projects/$project_id")"
printf '%s' "$project_detail" | grep -q '"current_run_phase":"NoPhase"'
printf '%s' "$project_detail" | grep -q '"source_repository"'

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
