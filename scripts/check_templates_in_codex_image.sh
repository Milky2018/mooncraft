#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${MOONBITCLOUD_TEMPLATE_CHECK_DOCKER_IMAGE:-docker.io/moonbitcloud/codex:codex-0.123.0-node24}"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/moonbitcloud-template-docker-check.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

template_ids=()
if [[ $# -gt 0 ]]; then
  template_ids=("$@")
else
  for manifest in "$repo_root"/templates/*/template.json; do
    [[ -e "$manifest" ]] || continue
    template_ids+=("$(basename "$(dirname "$manifest")")")
  done
fi

if [[ "${#template_ids[@]}" -eq 0 ]]; then
  echo "No templates found." >&2
  exit 1
fi

copy_workspace() {
  local source="$1"
  local target="$2"
  mkdir -p "$target"
  (
    cd "$source"
    tar \
      --exclude './_build' \
      --exclude './_build/*' \
      --exclude './.mooncakes' \
      --exclude './.mooncakes/*' \
      --exclude './preview-dist' \
      --exclude './preview-dist/*' \
      --exclude './.DS_Store' \
      -cf - .
  ) | (
    cd "$target"
    tar -xf -
  )
}

manifest_workspace_dir() {
  local manifest="$1"
  local workspace_dir
  workspace_dir="$(sed -n 's/^[[:space:]]*"workspace_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n1)"
  if [[ -z "$workspace_dir" ]]; then
    echo "Template manifest is missing workspace_dir: $manifest" >&2
    exit 1
  fi
  if [[ "$workspace_dir" = /* || "$workspace_dir" == *..* ]]; then
    echo "Template manifest has unsafe workspace_dir '$workspace_dir': $manifest" >&2
    exit 1
  fi
  printf '%s\n' "$workspace_dir"
}

for template_id in "${template_ids[@]}"; do
  manifest="$repo_root/templates/$template_id/template.json"
  if [[ ! -f "$manifest" ]]; then
    echo "Template '$template_id' is missing template.json: $manifest" >&2
    exit 1
  fi

  workspace_dir="$(manifest_workspace_dir "$manifest")"
  source_workspace="$repo_root/templates/$template_id/$workspace_dir"
  if [[ ! -d "$source_workspace" ]]; then
    echo "Template '$template_id' is missing $workspace_dir/: $source_workspace" >&2
    exit 1
  fi

  sandbox_workspace="$tmp_root/$template_id/$workspace_dir"
  echo "==> Checking template in Codex image: $template_id"
  copy_workspace "$source_workspace" "$sandbox_workspace"
  docker run --rm \
    -v "$sandbox_workspace:/workspace" \
    -w /workspace \
    "$image" \
    sh -lc 'moon update && moon check && moon build'
done

echo "All template workspaces passed Docker-backed moon update, moon check, and moon build."
