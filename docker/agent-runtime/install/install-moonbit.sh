#!/usr/bin/env bash
set -euo pipefail

moonbit_version="${MOONBIT_VERSION:-latest}"

for attempt in 1 2 3 4 5; do
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh |
    bash -s -- "$moonbit_version" &&
    break
  if [[ "$attempt" == "5" ]]; then
    exit 1
  fi
  sleep $((attempt * 5))
done

for tool in /opt/moon/bin/*; do
  if [[ -f "$tool" && -x "$tool" ]]; then
    ln -sf "$tool" "/usr/local/bin/$(basename "$tool")"
  fi
done

moon update
