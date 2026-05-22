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
  -e "MOONCRAFT_AI_PROVIDER=openrouter" \
  -e "MOONCRAFT_AGENT_CLI=codex" \
  -e "MOONCRAFT_AI_MODEL=openai/gpt-5.4-mini" \
  -e "MOONCRAFT_AI_API_KEY=${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_API_KEY:-dummy-runtime-check-key}" \
  -v "$tmp_root:/workspace" \
  -w /workspace \
  "$image" \
  bash -lc '
    set -euo pipefail
    command -v rg >/dev/null
    command -v jq >/dev/null
    command -v sort >/dev/null
    command -v mooncraft-runtime-send >/dev/null
    test -n "${HOME:-}"
    test -d "$HOME/.codex/skills"
    test -d /opt/mooncraft/templates
    echo "Agent runtime image check completed."
  '
