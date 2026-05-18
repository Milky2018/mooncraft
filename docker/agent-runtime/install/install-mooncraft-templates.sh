#!/usr/bin/env bash
set -euo pipefail

repo="${MOONCRAFT_TEMPLATES_REPO:-https://github.com/moonbitlang/mooncraft-templates.git}"
dest="${MOONCRAFT_TEMPLATES_DIR:-/opt/mooncraft/templates}"

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
if GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$repo" "$dest"; then
  rm -rf "$dest/.git"
else
  mkdir -p "$dest"
  cat >"$dest/README.md" <<EOF
# MoonCraft Templates

The MoonCraft template knowledge repository could not be cloned while building
this runtime image. Publish or grant access to:

$repo
EOF
  echo "Warning: could not clone MoonCraft template knowledge from $repo" >&2
fi
