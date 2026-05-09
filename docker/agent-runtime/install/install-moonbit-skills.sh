#!/usr/bin/env bash
set -euo pipefail

git clone \
  --depth 1 \
  --recurse-submodules \
  --shallow-submodules \
  https://github.com/moonbitlang/skills.git \
  /opt/moonbitlang-skills

mkdir -p /opt/codex-skill-seed/skills

while IFS= read -r skill_file; do
  skill_dir="$(dirname "$skill_file")"
  skill_name="$(basename "$skill_dir")"
  cp -R "$skill_dir" "/opt/codex-skill-seed/skills/$skill_name"
done < <(find /opt/moonbitlang-skills -mindepth 1 -maxdepth 5 -name SKILL.md -print)

rm -rf /opt/moonbitlang-skills/.git
