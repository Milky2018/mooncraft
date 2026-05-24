#!/bin/sh
set -eu

target_url="${1:-}"
timeout_seconds="${MOONCRAFT_PREVIEW_AUDIT_TIMEOUT_SECONDS:-12}"
body_file="$(mktemp "${TMPDIR:-/tmp}/mooncraft-preview-audit.XXXXXX")"

cleanup() {
  rm -f "$body_file"
}
trap cleanup EXIT INT TERM

print_body_excerpt() {
  if [ -s "$body_file" ]; then
    dd if="$body_file" bs=1200 count=1 2>/dev/null >&2 || true
    printf '\n' >&2
  fi
}

fail() {
  printf '%s\n' "$1" >&2
  print_body_excerpt
  exit 1
}

case "$target_url" in
  http://* | https://*) ;;
  *) fail "Preview audit failed for ${target_url}: expected an absolute http(s) URL." ;;
esac

if ! http_status="$(
  curl \
    --location \
    --silent \
    --show-error \
    --max-time "$timeout_seconds" \
    --output "$body_file" \
    --write-out "%{http_code}" \
    "$target_url"
)"; then
  fail "Preview audit failed for ${target_url}: page request failed."
fi

case "$http_status" in
  2* | 3*) ;;
  *) fail "Preview audit failed for ${target_url}: HTTP ${http_status}." ;;
esac

byte_count="$(wc -c <"$body_file" | tr -d ' ')"
if [ "$byte_count" -le 0 ]; then
  fail "Preview audit failed for ${target_url}: response body is empty."
fi

for needle in \
  "No preview is available" \
  "preview process is not reachable" \
  "preview could not be restarted" \
  "Bad Gateway"
do
  if grep -Fq "$needle" "$body_file"; then
    fail "Preview audit failed for ${target_url}: response contains a preview error page."
  fi
done

printf 'Preview audit passed for %s: HTTP %s, %s bytes.\n' \
  "$target_url" \
  "$http_status" \
  "$byte_count"
