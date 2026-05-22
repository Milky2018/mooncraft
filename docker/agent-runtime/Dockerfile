FROM node:24-bookworm

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONCRAFT_AGENT_RUNTIME_VERSION=0.1.3
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.125.0

LABEL org.opencontainers.image.title="MoonCraft Agent Runtime"
LABEL org.opencontainers.image.description="MoonCraft runtime image for isolated app-building agents."
LABEL mooncraft.agent_runtime.version="${MOONCRAFT_AGENT_RUNTIME_VERSION}"
LABEL mooncraft.codex.version="${CODEX_CLI_VERSION}"
LABEL mooncraft.node.version="24"
LABEL mooncraft.moonbit.version="${MOONBIT_VERSION}"

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/opt/kimi-cli/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY docker/agent-runtime/bin/ /usr/local/bin/
COPY docker/agent-runtime/install/ /opt/mooncraft/install/
COPY docker/agent-runtime/mooncraft-agent-system.md /opt/mooncraft/mooncraft-agent-system.md

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git bash ripgrep jq coreutils python3 \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 --shell /bin/bash mooncraft

RUN chmod +x /usr/local/bin/mooncraft-agent-* /opt/mooncraft/install/*.sh

RUN MOONBIT_VERSION="${MOONBIT_VERSION}" /opt/mooncraft/install/install-moonbit.sh

RUN CODEX_CLI_VERSION="${CODEX_CLI_VERSION}" /opt/mooncraft/install/install-node-agents.sh

RUN /opt/mooncraft/install/install-kimi.sh

RUN /opt/mooncraft/install/install-moonbit-skills.sh

RUN /opt/mooncraft/install/install-mooncraft-templates.sh

WORKDIR /workspace

ENTRYPOINT ["mooncraft-agent-entrypoint"]

RUN moon version && codex --version && claude --version && kimi --version
