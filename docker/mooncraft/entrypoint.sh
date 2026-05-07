#!/usr/bin/env bash
set -euo pipefail

mkdir -p /app/data/control-plane

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

exec stdbuf -oL -eL moon -C /app run --target native --release services/control-plane
