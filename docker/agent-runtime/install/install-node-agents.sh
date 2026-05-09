#!/usr/bin/env bash
set -euo pipefail

codex_cli_version="${CODEX_CLI_VERSION:-0.125.0}"

npm install -g "@openai/codex@${codex_cli_version}"
npm install -g "@anthropic-ai/claude-code"
npm cache clean --force
