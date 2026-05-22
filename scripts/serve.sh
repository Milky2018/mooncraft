#!/usr/bin/env bash
set -euo pipefail

target="${1:-8080}"
profile="${2:-debug}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ "$target" == "debug" || "$target" == "release" ]]; then
  profile="$target"
  port="${MOONCRAFT_PORT:-8080}"
else
  port="$target"
fi

base_url="http://localhost:$port"
public_base_url="${MOONCRAFT_PUBLIC_BASE_URL:-$base_url}"
echo "MoonCraft: $base_url"

if [[ "$profile" == "release" ]]; then
  moon -C . build --release
  MOONCRAFT_APP_MODE="${MOONCRAFT_APP_MODE:-development}" \
    MOONCRAFT_PORT="$port" \
    MOONCRAFT_PUBLIC_BASE_URL="$public_base_url" \
    MOONCRAFT_BUILD_PROFILE=release \
    ./_build/native/release/build/mooncraft/control-plane/control-plane.exe
else
  moon -C . build
  MOONCRAFT_APP_MODE="${MOONCRAFT_APP_MODE:-development}" \
    MOONCRAFT_PORT="$port" \
    MOONCRAFT_PUBLIC_BASE_URL="$public_base_url" \
    MOONCRAFT_BUILD_PROFILE=debug \
    ./_build/native/debug/build/mooncraft/control-plane/control-plane.exe
fi
