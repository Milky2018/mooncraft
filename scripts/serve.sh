#!/usr/bin/env bash
set -euo pipefail

target="${1:-8080}"
profile="${2:-debug}"

if [[ "$target" == "debug" || "$target" == "release" ]]; then
  profile="$target"
  port="${MOONCRAFT_PORT:-8080}"
else
  port="$target"
fi

base_url="http://localhost:$port"
public_base_url="${MOONCRAFT_PUBLIC_BASE_URL:-$base_url}"
echo "Mooncraft: $base_url"

if [[ "$profile" == "release" ]]; then
  MOONCRAFT_APP_MODE="${MOONCRAFT_APP_MODE:-development}" \
    MOONCRAFT_PORT="$port" \
    MOONCRAFT_PUBLIC_BASE_URL="$public_base_url" \
    MOONCRAFT_BUILD_PROFILE=release \
    moon -C . run --target native --release services/control-plane
else
  MOONCRAFT_APP_MODE="${MOONCRAFT_APP_MODE:-development}" \
    MOONCRAFT_PORT="$port" \
    MOONCRAFT_PUBLIC_BASE_URL="$public_base_url" \
    MOONCRAFT_BUILD_PROFILE=debug \
    moon -C . run --target native services/control-plane
fi
