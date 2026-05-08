#!/usr/bin/env bash
set -euo pipefail

mkdir -p /app/data/control-plane

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

exec stdbuf -oL -eL /app/_build/native/release/build/mooncraft/control-plane/control-plane.exe
