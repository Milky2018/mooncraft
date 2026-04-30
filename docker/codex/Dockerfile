FROM node:24-bookworm

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.125.0

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git bash \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "${MOONBIT_VERSION}"

RUN for tool in /opt/moon/bin/*; do \
  if [ -f "$tool" ] && [ -x "$tool" ]; then \
    ln -sf "$tool" "/usr/local/bin/$(basename "$tool")"; \
  fi; \
  done

RUN moon update

RUN npm install -g "@openai/codex@${CODEX_CLI_VERSION}" \
  && npm cache clean --force

RUN git clone --depth 1 --recurse-submodules --shallow-submodules https://github.com/moonbitlang/skills.git /opt/moonbitlang-skills \
  && mkdir -p /opt/codex-skill-seed/skills \
  && find /opt/moonbitlang-skills -mindepth 1 -maxdepth 5 -name SKILL.md -print \
    -exec sh -c 'dir="$(dirname "$1")"; name="$(basename "$dir")"; cp -R "$dir" "/opt/codex-skill-seed/skills/$name"' sh {} \; \
  && rm -rf /opt/moonbitlang-skills/.git

RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'codex_home="${CODEX_HOME:-${HOME:-/root}/.codex}"' \
  'mkdir -p "$codex_home"' \
  'if [ -d /opt/codex-skill-seed/skills ]; then' \
  '  if [ ! -e "$codex_home/skills" ] || [ -d "$codex_home/skills" ]; then' \
  '    mkdir -p "$codex_home/skills"' \
  '    cp -R /opt/codex-skill-seed/skills/. "$codex_home/skills/"' \
  '  fi' \
  'fi' \
  'provider="${MOONCRAFT_AI_PROVIDER:-openai}"' \
  'api_key="${MOONCRAFT_AI_API_KEY:-}"' \
  'if [ -z "$api_key" ]; then' \
  '  echo "MOONCRAFT_AI_API_KEY is required for Codex runs." >&2' \
  '  exit 64' \
  'fi' \
  'export OPENAI_API_KEY="$api_key"' \
  'if [ "$provider" = "openrouter" ]; then' \
  '  cat > "$codex_home/config.toml" <<EOF' \
  'model_provider = "openrouter"' \
  '' \
  '[model_providers.openrouter]' \
  'name = "OpenRouter"' \
  'base_url = "https://openrouter.ai/api/v1"' \
  'env_key = "OPENAI_API_KEY"' \
  'wire_api = "chat"' \
  'EOF' \
  'elif [ "$provider" != "openai" ]; then' \
  '  echo "Unsupported MOONCRAFT_AI_PROVIDER: $provider" >&2' \
  '  exit 64' \
  'fi' \
  'if [ "$provider" = "openai" ] && [ ! -f "$codex_home/auth.json" ]; then' \
  '  printf "%s" "$OPENAI_API_KEY" | codex login --with-api-key >/dev/null' \
  'fi' \
  'unset MOONCRAFT_AI_API_KEY' \
  'exec "$@"' \
  > /usr/local/bin/mooncraft-codex-entrypoint \
  && chmod +x /usr/local/bin/mooncraft-codex-entrypoint

WORKDIR /workspace

ENTRYPOINT ["mooncraft-codex-entrypoint"]

RUN moon version && codex --version
