#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
openapi="$repo_root/docs/runtime-protocol/openapi.v3.yaml"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/mooncraft-runtime-openapi.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

extract_paths() {
  awk '
    /^paths:/ { in_paths = 1; next }
    /^components:/ { in_paths = 0 }
    in_paths && /^  \// {
      path = $1
      sub(/:$/, "", path)
      print path
    }
  ' "$openapi"
}

extract_enum() {
  local schema="$1"
  awk -v schema="$schema" '
    $0 == "    " schema ":" { in_schema = 1; next }
    in_schema && /^    [A-Za-z].*:/ { exit }
    in_schema && /^      enum:/ { in_enum = 1; next }
    in_schema && in_enum && /^        - / {
      sub(/^        - /, "")
      print
      next
    }
    in_schema && in_enum && !/^        - / { exit }
  ' "$openapi"
}

extract_run_event_level_enum() {
  awk '
    $0 == "    RunEvent:" { in_schema = 1; next }
    in_schema && /^    [A-Za-z].*:/ { exit }
    in_schema && /^        level:/ { in_level = 1; next }
    in_schema && in_level && /^          enum:/ { in_enum = 1; next }
    in_schema && in_enum && /^            - / {
      sub(/^            - /, "")
      print
      next
    }
    in_schema && in_enum && !/^            - / { exit }
  ' "$openapi"
}

cat >"$tmp_dir/expected_paths" <<'EOF'
/health
/init
/exec
/runs/{run_id}
/runs/{run_id}/events
/preview/
/preview/{path}
EOF

extract_paths >"$tmp_dir/actual_paths"
diff -u "$tmp_dir/expected_paths" "$tmp_dir/actual_paths"

cat >"$tmp_dir/expected_runtime_status" <<'EOF'
not_initialized
ready
running
EOF

extract_enum RuntimeServiceStatus >"$tmp_dir/actual_runtime_status"
diff -u "$tmp_dir/expected_runtime_status" "$tmp_dir/actual_runtime_status"

cat >"$tmp_dir/expected_run_status" <<'EOF'
running
succeeded
failed
EOF

extract_enum RunStatus >"$tmp_dir/actual_run_status"
diff -u "$tmp_dir/expected_run_status" "$tmp_dir/actual_run_status"

cat >"$tmp_dir/expected_event_level" <<'EOF'
info
warning
error
EOF

extract_run_event_level_enum >"$tmp_dir/actual_event_level"
diff -u "$tmp_dir/expected_event_level" "$tmp_dir/actual_event_level"

echo "Runtime Protocol OpenAPI drift check passed."
