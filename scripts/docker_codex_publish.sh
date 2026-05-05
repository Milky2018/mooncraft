#!/usr/bin/env bash
set -euo pipefail

repository="${1:-docker.io/moonbitcloud/codex}"
version="${2:-codex-0.125.0-node24}"
platforms="${3:-linux/amd64,linux/arm64}"
builder="${MOONCRAFT_CODEX_BUILDX_BUILDER:-mooncraft-codex-builder}"

if ! docker buildx inspect "$builder" >/dev/null 2>&1; then
  docker buildx create --name "$builder" --driver docker-container --bootstrap >/dev/null
else
  docker buildx inspect "$builder" --bootstrap >/dev/null
fi

docker buildx build \
  --builder "$builder" \
  --platform "$platforms" \
  -f docker/codex/Dockerfile \
  -t "$repository:$version" \
  -t "$repository:latest" \
  --push \
  .

docker buildx imagetools inspect "$repository:$version"
