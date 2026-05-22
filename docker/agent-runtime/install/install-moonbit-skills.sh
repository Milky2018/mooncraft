#!/usr/bin/env bash
set -euo pipefail

seed_home="/opt/codex-skill-seed"
seed_skills="$seed_home/skills"

rm -rf "$seed_home"
mkdir -p "$seed_home"

HOME="$seed_home" npx skills@latest add moonbitlang/skills -g --all --copy

rm -rf "$seed_skills"
cp -R "$seed_home/.agents/skills" "$seed_skills"

find "$seed_home" -mindepth 1 -maxdepth 1 ! -name skills -exec rm -rf {} +
