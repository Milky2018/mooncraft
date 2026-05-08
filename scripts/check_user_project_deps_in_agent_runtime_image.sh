#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_agent_runtime_image="$(cat "$repo_root/config/agent_runtime_image.txt")"
image="${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_IMAGE:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_IMAGE:-$default_agent_runtime_image}}"
platform="${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_PLATFORM:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_PLATFORM:-linux/amd64}}"
modules_file="$repo_root/config/user_project_reference_modules.txt"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/mooncraft-user-project-deps-docker.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

if [[ ! -f "$modules_file" ]]; then
  echo "Missing user-project reference modules file: $modules_file" >&2
  exit 1
fi

docker run --rm \
  --platform "$platform" \
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
    echo "Agent runtime dependency and skill seed check completed."
  '
