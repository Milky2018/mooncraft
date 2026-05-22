#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_agent_runtime_image="$(cat "$repo_root/config/agent_runtime_image.txt")"
image="${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_IMAGE:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_IMAGE:-${1:-$default_agent_runtime_image}}}"
platform="${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_PLATFORM:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_PLATFORM:-${2:-host}}}"
modules_file="$repo_root/config/user_project_reference_modules.txt"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/mooncraft-agent-runtime-check.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

if [[ ! -f "$modules_file" ]]; then
  echo "Missing user-project reference modules file: $modules_file" >&2
  exit 1
fi

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
  -e "MOONCRAFT_AI_API_KEY=${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_API_KEY:-dummy-runtime-check-key}" \
  -v "$tmp_root:/workspace" \
  -v "$modules_file:/mooncraft-user-project-reference-modules.txt:ro" \
  -w /workspace \
  "$image" \
  bash -lc '
    set -euo pipefail
    modules=()
    while IFS= read -r module; do
      modules+=("$module")
    done < <(grep -vE "^[[:space:]]*(#|$)" /mooncraft-user-project-reference-modules.txt)
    if [[ "${#modules[@]}" -eq 0 ]]; then
      echo "No user-project reference modules configured." >&2
      exit 1
    fi
    command -v rg >/dev/null
    command -v jq >/dev/null
    command -v sort >/dev/null
    for module in "${modules[@]}"; do
      echo "==> Fetching required module: $module"
      moon fetch --no-update "$module"
    done
    test -d "${CODEX_HOME:-${HOME:-/root}/.codex}/skills"
    test -d /opt/mooncraft/templates
    echo "Agent runtime image check completed."
  '
