#!/usr/bin/env bash
set -euo pipefail

mkdir -p /app/data/control-plane

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

exec moon run --manifest-path /app/moon.work --target native services/control-plane
