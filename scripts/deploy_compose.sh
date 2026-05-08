#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <env-file> <compose-file>" >&2
  exit 64
fi

env_file="$1"
compose_file="$2"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_agent_runtime_image="$(cat "$repo_root/config/agent_runtime_image.txt")"

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

agent_runtime_image="${MOONCRAFT_AGENT_RUNTIME_IMAGE:-${MOONCRAFT_CODEX_DOCKER_IMAGE:-$default_agent_runtime_image}}"
if [[ -z "$agent_runtime_image" ]]; then
  echo "MOONCRAFT_AGENT_RUNTIME_IMAGE resolved to an empty value." >&2
  exit 65
fi

echo "Pulling agent runtime image: $agent_runtime_image"
docker pull "$agent_runtime_image"

docker compose --env-file "$env_file" -f "$compose_file" up -d --wait
