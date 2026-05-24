#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_agent_runtime_image="$(cat "$repo_root/config/agent_runtime_image.txt")"
image="${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_IMAGE:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_IMAGE:-${1:-$default_agent_runtime_image}}}"
platform="${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_PLATFORM:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_PLATFORM:-${2:-host}}}"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/mooncraft-agent-runtime-check.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT
mkdir -p "$tmp_root/workspace" "$tmp_root/home" "$tmp_root/artifacts"
chmod -R a+rwX "$tmp_root"

if [[ "$platform" = host || "$platform" = auto ]]; then
  platform="$("$repo_root/scripts/publish_agent_runtime_image.sh" host-platform)"
fi

case "$platform" in
  linux/amd64 | linux/arm64) ;;
  *)
    echo "Unsupported agent runtime image check platform: $platform" >&2
    echo "Use host, linux/amd64, or linux/arm64." >&2
    exit 64
    ;;
esac

docker run --rm \
  --platform "$platform" \
  -v "$tmp_root/workspace:/workspace" \
  -v "$tmp_root/home:/home/mooncraft" \
  -v "$tmp_root/artifacts:/artifacts" \
  -w /workspace \
  "$image" \
  bash -lc '
    set -euo pipefail
    test "$(id -u)" != "0"
    test "${HOME:-}" = "/home/mooncraft"
    test -w /workspace
    test -w /home/mooncraft
    test -w /artifacts
    command -v rg >/dev/null
    command -v jq >/dev/null
    command -v sort >/dev/null
    command -v cc >/dev/null
    command -v gcc >/dev/null
    command -v make >/dev/null
    command -v pkg-config >/dev/null
    command -v codex >/dev/null
    command -v claude >/dev/null
    printf "%s\n" "int main(void) { return 0; }" > /tmp/mooncraft-runtime-check.c
    cc /tmp/mooncraft-runtime-check.c -o /tmp/mooncraft-runtime-check
    /tmp/mooncraft-runtime-check
    test -d "$HOME/.codex/skills"
    test -d /opt/mooncraft/templates
    echo "Agent runtime image check completed."
  '
