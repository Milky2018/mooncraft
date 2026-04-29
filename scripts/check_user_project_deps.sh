#!/usr/bin/env bash
set -euo pipefail

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/moonbitcloud-user-project-deps.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

required_modules=(
  moonbitlang/async
  moonbitlang/x
  oboard/mocket
)

optional_modules=(
  moonbit-community/isomorphic
  moonbit-community/selene
)

cd "$tmp_root"

for module in "${required_modules[@]}"; do
  echo "==> Fetching required module: $module"
  moon fetch "$module"
done

for module in "${optional_modules[@]}"; do
  echo "==> Fetching optional module: $module"
  if ! moon fetch "$module"; then
    echo "Optional module is not available in the registry yet: $module" >&2
  fi
done

echo "Generated user-project dependency fetch check completed."
