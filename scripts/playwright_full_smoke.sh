#!/usr/bin/env bash
set -euo pipefail

port="${1:-8094}"

MOONCRAFT_PLAYWRIGHT_PORT="$port" \
MOONCRAFT_PLAYWRIGHT_OUTPUT_DIR="${MOONCRAFT_PLAYWRIGHT_OUTPUT_DIR:-output/playwright/full-smoke}" \
  ./scripts/playwright_simple_project_story.sh
