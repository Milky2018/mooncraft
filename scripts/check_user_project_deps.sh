#!/usr/bin/env bash
set -euo pipefail

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/moonbitcloud-user-project-deps.XXXXXX")"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
modules_file="$repo_root/config/user_project_reference_modules.txt"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

if [[ ! -f "$modules_file" ]]; then
  echo "Missing user-project reference modules file: $modules_file" >&2
  exit 1
fi

required_modules=()
while IFS= read -r module; do
  required_modules+=("$module")
done < <(grep -vE '^[[:space:]]*(#|$)' "$modules_file")

if [[ "${#required_modules[@]}" -eq 0 ]]; then
  echo "No user-project reference modules configured in: $modules_file" >&2
  exit 1
fi

cd "$tmp_root"

for module in "${required_modules[@]}"; do
  echo "==> Fetching required module: $module"
  moon fetch --no-update "$module"
done

echo "Generated user-project dependency fetch check completed."
