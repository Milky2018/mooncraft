#!/usr/bin/env bash
set -euo pipefail

target_url="${1:-}"
timeout_seconds="${MOONCRAFT_PREVIEW_AUDIT_TIMEOUT_SECONDS:-12}"

if [[ -z "$target_url" ]]; then
  echo "Usage: preview_audit.sh <url>" >&2
  exit 2
fi

body_path="$(mktemp)"
asset_list_path="$(mktemp)"
asset_body_path="$(mktemp)"
root_absolute_matches_path="$(mktemp)"
trap 'rm -f "$body_path" "$asset_list_path" "$asset_body_path" "$root_absolute_matches_path"' EXIT

if [[ "$target_url" =~ ^(https?://[^/]+)(/.*)?$ ]]; then
  origin="${BASH_REMATCH[1]}"
else
  echo "Preview audit failed for $target_url: expected an absolute http(s) URL." >&2
  exit 1
fi

if [[ "$target_url" == */ ]]; then
  document_base="$target_url"
else
  document_base="${target_url%/*}/"
fi

is_skippable_url() {
  case "$1" in
    ""|\#*|mailto:*|tel:*|data:*|blob:*|javascript:*) return 0 ;;
    *) return 1 ;;
  esac
}

resolved_url() {
  local ref="$1"
  case "$ref" in
    http://*|https://*) printf '%s\n' "$ref" ;;
    //*) printf '%s:%s\n' "${target_url%%://*}" "$ref" ;;
    /*) printf '%s%s\n' "$origin" "$ref" ;;
    *) printf '%s%s\n' "$document_base" "$ref" ;;
  esac
}

assert_no_root_absolute_browser_urls() {
  local path="$1"
  local label="$2"
  if grep -En \
    '(src|href|action)[[:space:]]*=[[:space:]]*["'\'']/|url\([[:space:]]*["'\'']?/|fetch[[:space:]]*\([[:space:]]*["'\'']/|import[[:space:]]*\([[:space:]]*["'\'']/|new[[:space:]]+Worker[[:space:]]*\([[:space:]]*["'\'']/|["'\'']/api/|["'\'']/[^"'\'']+\.(js|mjs|css|wasm|json|png|jpg|jpeg|webp|svg|woff|woff2)|["'\'']/vendor/' \
    "$path" >"$root_absolute_matches_path" 2>/dev/null; then
    echo "Preview audit failed for $target_url: $label contains root-absolute browser URLs." >&2
    echo "MoonCraft previews are mounted under a path prefix such as /p/<preview-id>/." >&2
    echo "Use relative URLs like ./frontend.js and ./api/metrics instead of /frontend.js or /api/metrics." >&2
    head -20 "$root_absolute_matches_path" >&2 || true
    exit 1
  fi
  : >"$root_absolute_matches_path"
}

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

assert_no_root_absolute_browser_urls "$body_path" "the preview HTML"

grep -Eoi '(src|href|action)[[:space:]]*=[[:space:]]*"[^"]+"' "$body_path" \
  | sed -E 's/^[^"]*"([^"]+)".*$/\1/' >"$asset_list_path" || true

while IFS= read -r ref; do
  if is_skippable_url "$ref"; then
    continue
  fi
  asset_url="$(resolved_url "$ref")"
  case "$asset_url" in
    "$origin"/*) ;;
    *) continue ;;
  esac
  asset_code="$(
    curl \
      --location \
      --silent \
      --show-error \
      --max-time "$timeout_seconds" \
      --write-out '%{http_code}' \
      --output "$asset_body_path" \
      "$asset_url"
  )" || {
    echo "Preview audit failed for $target_url: asset request failed: $asset_url" >&2
    exit 1
  }
  case "$asset_code" in
    2*|3*) ;;
    *)
      echo "Preview audit failed for $target_url: asset $asset_url returned HTTP $asset_code." >&2
      exit 1
      ;;
  esac
  case "$asset_url" in
    *.js|*.mjs|*.css|*.html|*/) assert_no_root_absolute_browser_urls "$asset_body_path" "$asset_url" ;;
  esac
done <"$asset_list_path"

echo "Preview audit passed for $target_url: HTTP $http_code, $byte_count bytes, browser assets reachable."
