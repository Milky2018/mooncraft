#!/usr/bin/env bash
set -euo pipefail

mkdir -p /app/data/control-plane

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

exec moon -C /app run --target native services/control-plane
