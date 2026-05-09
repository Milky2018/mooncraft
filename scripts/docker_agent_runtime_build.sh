#!/usr/bin/env bash
set -euo pipefail

repository="${1:-docker.io/moonbitcloud/mooncraft-agent-runtime}"
version="${2:-0.1.0}"
platform="${3:-linux/amd64}"

docker build \
  --platform "$platform" \
  -f docker/agent-runtime/Dockerfile \
  --build-arg "MOONCRAFT_AGENT_RUNTIME_VERSION=$version" \
  -t "$repository:$version" \
  -t "$repository:latest" \
  .
