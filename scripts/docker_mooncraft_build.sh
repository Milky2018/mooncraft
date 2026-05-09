#!/usr/bin/env bash
set -euo pipefail

tag="${1:-mooncraft:local}"
platform="${2:-linux/amd64}"

docker build \
  --platform "$platform" \
  -f docker/mooncraft/Dockerfile \
  -t "$tag" \
  .
