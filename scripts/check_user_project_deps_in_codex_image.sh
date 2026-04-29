#!/usr/bin/env bash
set -euo pipefail

image="${MOONBITCLOUD_CODEX_DEPS_CHECK_DOCKER_IMAGE:-docker.io/moonbitcloud/codex:codex-0.125.0-node24}"
platform="${MOONBITCLOUD_CODEX_DEPS_CHECK_DOCKER_PLATFORM:-linux/amd64}"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/moonbitcloud-user-project-deps-docker.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

docker run --rm \
  --platform "$platform" \
  -v "$tmp_root:/workspace" \
  -w /workspace \
  "$image" \
  bash -lc '
    set -euo pipefail
    for module in moonbitlang/async moonbitlang/x oboard/mocket; do
      echo "==> Fetching required module: $module"
      moon fetch --no-update "$module"
    done
    for module in moonbit-community/isomorphic moonbit-community/selene; do
      echo "==> Fetching optional module: $module"
      moon fetch --no-update "$module" || echo "Optional module is not available in the registry yet: $module" >&2
    done
    test -d "${CODEX_HOME:-${HOME:-/root}/.codex}/skills"
    echo "Codex runtime dependency and skill seed check completed."
  '
