#!/usr/bin/env bash
set -euo pipefail

repository="${1:-docker.io/moonbitcloud/mooncraft-agent-runtime}"
version="${2:-0.1.0}"
platforms="${3:-linux/amd64,linux/arm64}"
builder="${MOONCRAFT_AGENT_RUNTIME_BUILDX_BUILDER:-mooncraft-agent-runtime-builder}"

if ! docker buildx inspect "$builder" >/dev/null 2>&1; then
  docker buildx create --name "$builder" --driver docker-container --bootstrap >/dev/null
else
  docker buildx inspect "$builder" --bootstrap >/dev/null
fi

docker buildx build \
  --builder "$builder" \
  --platform "$platforms" \
  -f docker/agent-runtime/Dockerfile \
  --build-arg "MOONCRAFT_AGENT_RUNTIME_VERSION=$version" \
  -t "$repository:$version" \
  -t "$repository:latest" \
  --push \
  .

docker buildx imagetools inspect "$repository:$version"
