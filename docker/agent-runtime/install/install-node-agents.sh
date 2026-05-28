#!/usr/bin/env bash
set -euo pipefail

codex_cli_version="${CODEX_CLI_VERSION:-0.128.0}"

npm install -g "@openai/codex@${codex_cli_version}"

codex_binary="$(
  find /usr/local/lib/node_modules/@openai/codex -type f -path '*/vendor/*/codex/codex' |
    head -n 1
)"
if [[ -z "$codex_binary" ]]; then
  echo "Could not find native Codex binary in @openai/codex ${codex_cli_version}." >&2
  exit 1
fi

mkdir -p /opt/codex/bin
cp "$codex_binary" /opt/codex/bin/codex
chmod +x /opt/codex/bin/codex
/opt/codex/bin/codex --version

npm cache clean --force
