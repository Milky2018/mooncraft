FROM node:24-bookworm

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONCRAFT_AGENT_RUNTIME_VERSION=0.1.0
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.125.0

LABEL org.opencontainers.image.title="Mooncraft Agent Runtime"
LABEL org.opencontainers.image.description="Mooncraft runtime image for isolated app-building agents."
LABEL mooncraft.agent_runtime.version="${MOONCRAFT_AGENT_RUNTIME_VERSION}"
LABEL mooncraft.codex.version="${CODEX_CLI_VERSION}"
LABEL mooncraft.node.version="24"
LABEL mooncraft.moonbit.version="${MOONBIT_VERSION}"

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/opt/kimi-cli/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git bash ripgrep jq coreutils python3 \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 --shell /bin/bash mooncraft

RUN for attempt in 1 2 3 4 5; do \
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "${MOONBIT_VERSION}" && break; \
    if [ "$attempt" = "5" ]; then exit 1; fi; \
    sleep $((attempt * 5)); \
  done

RUN for tool in /opt/moon/bin/*; do \
  if [ -f "$tool" ] && [ -x "$tool" ]; then \
    ln -sf "$tool" "/usr/local/bin/$(basename "$tool")"; \
  fi; \
  done

RUN moon update

RUN npm install -g "@openai/codex@${CODEX_CLI_VERSION}" \
  && npm install -g "@anthropic-ai/claude-code" \
  && npm cache clean --force

RUN export PATH="/root/.local/bin:${PATH}" \
  && curl -LsSf https://code.kimi.com/install.sh | bash \
  && cp -a /root/.local/share/uv/tools/kimi-cli /opt/kimi-cli \
  && cp -a /root/.local/share/uv/python /opt/uv-python \
  && python_path="$(find /opt/uv-python -path '*/bin/python3.13' -type f | head -n 1)" \
  && test -n "$python_path" \
  && ln -sf "$python_path" /opt/kimi-cli/bin/python \
  && ln -sf python /opt/kimi-cli/bin/python3 \
  && ln -sf python /opt/kimi-cli/bin/python3.13 \
  && sed -i '1s|^#!.*$|#!/opt/kimi-cli/bin/python|' /opt/kimi-cli/bin/kimi /opt/kimi-cli/bin/kimi-cli \
  && ln -sf /opt/kimi-cli/bin/kimi /usr/local/bin/kimi \
  && ln -sf /opt/kimi-cli/bin/kimi-cli /usr/local/bin/kimi-cli \
  && chmod -R a+rX /opt/kimi-cli /opt/uv-python \
  && kimi --version

RUN git clone --depth 1 --recurse-submodules --shallow-submodules https://github.com/moonbitlang/skills.git /opt/moonbitlang-skills \
  && mkdir -p /opt/codex-skill-seed/skills \
  && find /opt/moonbitlang-skills -mindepth 1 -maxdepth 5 -name SKILL.md -print \
    -exec sh -c 'dir="$(dirname "$1")"; name="$(basename "$dir")"; cp -R "$dir" "/opt/codex-skill-seed/skills/$name"' sh {} \; \
  && rm -rf /opt/moonbitlang-skills/.git

RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'echo "mooncraft-agent-doctor: agent=${MOONCRAFT_AGENT_CLI:-unknown}"' \
  'for tool in moon rg jq codex claude kimi; do' \
  '  command -v "$tool" >/dev/null' \
  'done' \
  'moon version >/dev/null' \
  'rg --version >/dev/null' \
  'jq --version >/dev/null' \
  'codex --version >/dev/null' \
  'claude --version >/dev/null' \
  'kimi --version >/dev/null' \
  'for dir in /workspace /artifacts "${HOME:-/root}"; do' \
  '  mkdir -p "$dir"' \
  '  probe="$dir/.mooncraft-doctor-write-test"' \
  '  printf ok > "$probe"' \
  '  rm -f "$probe"' \
  'done' \
  'if [ "${MOONCRAFT_AGENT_CLI:-}" = "claude_code" ]; then' \
  '  chmod -R a+rwX /workspace /artifacts "${HOME:-/home/mooncraft}" >/dev/null 2>&1 || true' \
  '  runuser -u mooncraft -- env HOME="${HOME:-/home/mooncraft}" claude --version >/dev/null' \
  'fi' \
  'echo "mooncraft-agent-doctor: ok"' \
  > /usr/local/bin/mooncraft-agent-doctor \
  && chmod +x /usr/local/bin/mooncraft-agent-doctor

RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'codex_home="${CODEX_HOME:-${HOME:-/root}/.codex}"' \
  'export CODEX_HOME="$codex_home"' \
  'mkdir -p "$codex_home"' \
  'if [ -d /opt/codex-skill-seed/skills ]; then' \
  '  if [ ! -e "$codex_home/skills" ] || [ -d "$codex_home/skills" ]; then' \
  '    mkdir -p "$codex_home/skills"' \
  '    cp -R /opt/codex-skill-seed/skills/. "$codex_home/skills/"' \
  '  fi' \
  'fi' \
  'provider="${MOONCRAFT_AI_PROVIDER:-openrouter}"' \
  'agent_cli="${MOONCRAFT_AGENT_CLI:-codex}"' \
  'api_key="${MOONCRAFT_AI_API_KEY:-}"' \
  'model="${MOONCRAFT_AI_MODEL:-anthropic/claude-sonnet-4.5}"' \
  'if [ "${1:-}" = "mooncraft-agent-doctor" ]; then' \
  '  exec "$@"' \
  'fi' \
  'if [ -z "$api_key" ]; then' \
  '  echo "MOONCRAFT_AI_API_KEY is required for OpenRouter-backed agent runs." >&2' \
  '  exit 64' \
  'fi' \
  'export OPENROUTER_API_KEY="$api_key"' \
  'if [ "$provider" != "openrouter" ]; then' \
  '  echo "Only OpenRouter is supported by the Mooncraft agent runtime." >&2' \
  '  exit 64' \
  'fi' \
  'case "$agent_cli" in' \
  '  codex)' \
  '  cat > "$codex_home/config.toml" <<EOF' \
  'model_provider = "openrouter"' \
  '' \
  '[model_providers.openrouter]' \
  'name = "OpenRouter"' \
  'base_url = "https://openrouter.ai/api/v1"' \
  'env_key = "OPENROUTER_API_KEY"' \
  'wire_api = "responses"' \
  'EOF' \
  '    ;;' \
  '  claude_code)' \
  '    export ANTHROPIC_BASE_URL="https://openrouter.ai/api"' \
  '    export ANTHROPIC_AUTH_TOKEN="$api_key"' \
  '    export ANTHROPIC_API_KEY=""' \
  '    export ANTHROPIC_DEFAULT_OPUS_MODEL="$model"' \
  '    export ANTHROPIC_DEFAULT_SONNET_MODEL="$model"' \
  '    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$model"' \
  '    export CLAUDE_CODE_SUBAGENT_MODEL="$model"' \
  '    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1' \
  '    ;;' \
  '  kimi_code)' \
  '    mkdir -p "${KIMI_SHARE_DIR:-${HOME:-/root}/.kimi}"' \
  '    cat > "${KIMI_SHARE_DIR:-${HOME:-/root}/.kimi}/config.toml" <<EOF' \
  'default_model = "mooncraft-openrouter"' \
  'default_thinking = false' \
  'default_yolo = true' \
  'default_plan_mode = false' \
  'merge_all_available_skills = true' \
  '' \
  '[providers.openrouter]' \
  'type = "openai_legacy"' \
  'base_url = "https://openrouter.ai/api/v1"' \
  'api_key = "$api_key"' \
  '' \
  '[models.mooncraft-openrouter]' \
  'provider = "openrouter"' \
  'model = "$model"' \
  'max_context_size = 262144' \
  'capabilities = []' \
  'EOF' \
  '    export OPENAI_BASE_URL="https://openrouter.ai/api/v1"' \
  '    export OPENAI_API_KEY="$api_key"' \
  '    export KIMI_CLI_NO_AUTO_UPDATE=1' \
  '    ;;' \
  '  *)' \
  '    echo "Unsupported MOONCRAFT_AGENT_CLI: $agent_cli" >&2' \
  '    exit 64' \
  '    ;;' \
  'esac' \
  'unset MOONCRAFT_AI_API_KEY' \
  'exec "$@"' \
  > /usr/local/bin/mooncraft-agent-entrypoint \
  && chmod +x /usr/local/bin/mooncraft-agent-entrypoint

WORKDIR /workspace

ENTRYPOINT ["mooncraft-agent-entrypoint"]

RUN moon version && codex --version && claude --version && kimi --version
