#!/usr/bin/env bash
set -euo pipefail

target_url="${1:-}"
timeout_seconds="${MOONCRAFT_PREVIEW_AUDIT_TIMEOUT_SECONDS:-12}"

if [[ -z "$target_url" ]]; then
  echo "Usage: preview_audit.sh <url>" >&2
  exit 2
fi

body_path="$(mktemp)"
trap 'rm -f "$body_path"' EXIT

http_code="$(
  curl \
    --location \
    --silent \
    --show-error \
    --max-time "$timeout_seconds" \
    --write-out '%{http_code}' \
    --output "$body_path" \
    "$target_url"
)" || {
  echo "Preview audit failed for $target_url: request failed." >&2
  exit 1
}

case "$http_code" in
  2*|3*) ;;
  *)
    echo "Preview audit failed for $target_url: HTTP $http_code." >&2
    head -c 1200 "$body_path" >&2 || true
    echo >&2
    exit 1
    ;;
esac

byte_count="$(wc -c <"$body_path" | tr -d '[:space:]')"
if [[ "${byte_count:-0}" -le 0 ]]; then
  echo "Preview audit failed for $target_url: response body is empty." >&2
  exit 1
fi

if grep -Eiq 'No preview is available|preview process is not reachable|preview could not be restarted|Bad Gateway' "$body_path"; then
  echo "Preview audit failed for $target_url: response contains a preview error page." >&2
  head -c 1200 "$body_path" >&2 || true
  echo >&2
  exit 1
fi

echo "Preview audit passed for $target_url: HTTP $http_code, $byte_count bytes."
