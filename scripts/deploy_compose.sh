#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <env-file> <compose-file>" >&2
  exit 64
fi

env_file="$1"
compose_file="$2"

if [[ ! -f "$env_file" ]]; then
  echo "Missing env file: $env_file" >&2
  exit 66
fi
if [[ ! -f "$compose_file" ]]; then
  echo "Missing compose file: $compose_file" >&2
  exit 66
fi

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

echo "Runtime images are resolved from Runtime Configs at run time."

docker compose --env-file "$env_file" -f "$compose_file" up -d --wait
