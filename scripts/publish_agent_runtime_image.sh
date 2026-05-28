#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_image="$(cat "$repo_root/config/agent_runtime_image.txt")"
default_repository="${default_image%:*}"
default_version="${default_image##*:}"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/publish_agent_runtime_image.sh host-platform
  scripts/publish_agent_runtime_image.sh build [repository] [version] [host|linux/amd64|linux/arm64]
  scripts/publish_agent_runtime_image.sh build-all [repository] [version] [linux/amd64,linux/arm64]
  scripts/publish_agent_runtime_image.sh publish [repository] [version] [linux/amd64,linux/arm64]
EOF
}

host_platform() {
  local docker_arch
  docker_arch="$(docker info --format '{{.Architecture}}')"
  case "$docker_arch" in
    x86_64 | amd64) printf 'linux/amd64\n' ;;
    aarch64 | arm64) printf 'linux/arm64\n' ;;
    *)
      echo "Unsupported Docker host architecture for MoonCraft runtime: $docker_arch" >&2
      exit 65
      ;;
  esac
}

normalize_platform() {
  local platform="$1"
  case "$platform" in
    host | auto) host_platform ;;
    linux/amd64 | linux/arm64) printf '%s\n' "$platform" ;;
    *)
      echo "Unsupported runtime platform: $platform" >&2
      echo "Use host, linux/amd64, or linux/arm64." >&2
      exit 64
      ;;
  esac
}

validate_platforms() {
  local platforms="$1"
  local raw platform
  IFS=',' read -r -a platform_list <<< "$platforms"
  for raw in "${platform_list[@]}"; do
    platform="$(printf '%s' "$raw" | xargs)"
    case "$platform" in
      linux/amd64 | linux/arm64) ;;
      *)
        echo "Unsupported runtime platform: $platform" >&2
        echo "Use linux/amd64, linux/arm64, or both as a comma-separated list." >&2
        exit 64
        ;;
    esac
  done
}

platform_suffix() {
  case "$1" in
    linux/amd64) printf 'amd64\n' ;;
    linux/arm64) printf 'arm64\n' ;;
    *)
      echo "Unsupported runtime platform: $1" >&2
      exit 64
      ;;
  esac
}

runtime_templates_repo() {
  printf '%s\n' "${MOONCRAFT_TEMPLATES_REPO:-https://github.com/moonbitlang/mooncraft-templates.git}"
}

runtime_templates_ref() {
  if [[ -n "${MOONCRAFT_TEMPLATES_REF:-}" ]]; then
    printf '%s\n' "$MOONCRAFT_TEMPLATES_REF"
    return
  fi
  git ls-remote "$(runtime_templates_repo)" HEAD | awk '{print $1}'
}

build_image() {
  local repository="${1:-$default_repository}"
  local version="${2:-$default_version}"
  local platform="${3:-${MOONCRAFT_AGENT_RUNTIME_BUILD_PLATFORM:-host}}"
  local templates_repo templates_ref
  platform="$(normalize_platform "$platform")"
  templates_repo="$(runtime_templates_repo)"
  templates_ref="$(runtime_templates_ref)"
  echo "Building Runtime Protocol v3 image $repository:$version for $platform"
  docker build \
    --platform "$platform" \
    -f "$repo_root/docker/agent-runtime/Dockerfile" \
    --build-arg "MOONCRAFT_AGENT_RUNTIME_VERSION=$version" \
    --build-arg "MOONCRAFT_TEMPLATES_REPO=$templates_repo" \
    --build-arg "MOONCRAFT_TEMPLATES_REF=$templates_ref" \
    -t "$repository:$version" \
    -t "$repository:latest" \
    "$repo_root"
}

build_all_images() {
  local repository="${1:-$default_repository}"
  local version="${2:-$default_version}"
  local platforms="${3:-linux/amd64,linux/arm64}"
  local templates_repo templates_ref
  templates_repo="$(runtime_templates_repo)"
  templates_ref="$(runtime_templates_ref)"
  validate_platforms "$platforms"
  local raw platform suffix
  IFS=',' read -r -a platform_list <<< "$platforms"
  for raw in "${platform_list[@]}"; do
    platform="$(printf '%s' "$raw" | xargs)"
    suffix="$(platform_suffix "$platform")"
    echo "Building Runtime Protocol v3 image $repository:$version-$suffix for $platform"
    docker build \
      --platform "$platform" \
      -f "$repo_root/docker/agent-runtime/Dockerfile" \
      --build-arg "MOONCRAFT_AGENT_RUNTIME_VERSION=$version" \
      --build-arg "MOONCRAFT_TEMPLATES_REPO=$templates_repo" \
      --build-arg "MOONCRAFT_TEMPLATES_REF=$templates_ref" \
      -t "$repository:$version-$suffix" \
      -t "$repository:latest-$suffix" \
      "$repo_root"
  done
}

publish_image() {
  local repository="${1:-$default_repository}"
  local version="${2:-$default_version}"
  local platforms="${3:-linux/amd64,linux/arm64}"
  local builder="${MOONCRAFT_RUNTIME_BUILDX_BUILDER:-${MOONCRAFT_AGENT_RUNTIME_BUILDX_BUILDER:-mooncraft-runtime-builder}}"
  local templates_repo templates_ref
  templates_repo="$(runtime_templates_repo)"
  templates_ref="$(runtime_templates_ref)"
  validate_platforms "$platforms"
  if ! docker buildx inspect "$builder" >/dev/null 2>&1; then
    docker buildx create --name "$builder" --driver docker-container --bootstrap >/dev/null
  else
    docker buildx inspect "$builder" --bootstrap >/dev/null
  fi
  docker buildx build \
    --builder "$builder" \
    --platform "$platforms" \
    -f "$repo_root/docker/agent-runtime/Dockerfile" \
    --build-arg "MOONCRAFT_AGENT_RUNTIME_VERSION=$version" \
    --build-arg "MOONCRAFT_TEMPLATES_REPO=$templates_repo" \
    --build-arg "MOONCRAFT_TEMPLATES_REF=$templates_ref" \
    -t "$repository:$version" \
    -t "$repository:latest" \
    --push \
    "$repo_root"
  docker buildx imagetools inspect "$repository:$version"
}

command="${1:-}"
if [[ -z "$command" ]]; then
  usage
  exit 64
fi
shift
case "$command" in
  host-platform) host_platform "$@" ;;
  build) build_image "$@" ;;
  build-all) build_all_images "$@" ;;
  publish) publish_image "$@" ;;
  -h | --help | help) usage ;;
  *)
    usage
    exit 64
    ;;
esac
