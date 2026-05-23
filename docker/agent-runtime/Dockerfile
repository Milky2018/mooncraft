FROM node:24-bookworm AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONCRAFT_AGENT_RUNTIME_VERSION=0.2.0
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.125.0

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY docker/agent-runtime/install/ /opt/mooncraft/install/

RUN chmod +x /opt/mooncraft/install/*.sh

RUN MOONBIT_VERSION="${MOONBIT_VERSION}" /opt/mooncraft/install/install-moonbit.sh

RUN CODEX_CLI_VERSION="${CODEX_CLI_VERSION}" /opt/mooncraft/install/install-node-agents.sh

RUN /opt/mooncraft/install/install-moonbit-skills.sh

RUN /opt/mooncraft/install/install-mooncraft-templates.sh

RUN rm -rf /root/.cache /root/.npm /tmp/*

FROM debian:bookworm-slim AS run

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONCRAFT_AGENT_RUNTIME_VERSION=0.2.0
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.125.0

LABEL org.opencontainers.image.title="MoonCraft Agent Runtime"
LABEL org.opencontainers.image.description="MoonCraft runtime image for isolated app-building agents."
LABEL mooncraft.agent_runtime.version="${MOONCRAFT_AGENT_RUNTIME_VERSION}"
LABEL mooncraft.codex.version="${CODEX_CLI_VERSION}"
LABEL mooncraft.node.version="24"
LABEL mooncraft.moonbit.version="${MOONBIT_VERSION}"

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get -o Acquire::Retries=5 update \
  && apt-get -o Acquire::Retries=5 install -y --no-install-recommends ca-certificates curl git bash ripgrep jq coreutils libstdc++6 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --create-home --uid 10001 --shell /bin/bash mooncraft

COPY docker/agent-runtime/bin/ /usr/local/bin/
COPY docker/agent-runtime/mooncraft-agent-system.md /opt/mooncraft/mooncraft-agent-system.md
COPY --from=build /usr/local/bin/node /usr/local/bin/node
COPY --from=build /usr/local/bin/npm /usr/local/bin/npm
COPY --from=build /usr/local/bin/npx /usr/local/bin/npx
COPY --from=build /usr/local/bin/corepack /usr/local/bin/corepack
COPY --from=build /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY --from=build /usr/local/lib/node_modules/corepack /usr/local/lib/node_modules/corepack
COPY --from=build /opt/moon /opt/moon
COPY --from=build /opt/codex-skill-seed /opt/codex-skill-seed
COPY --from=build /opt/mooncraft/templates /opt/mooncraft/templates
COPY --from=build /usr/local/lib/node_modules/@openai /usr/local/lib/node_modules/@openai
COPY --from=build /usr/local/lib/node_modules/@anthropic-ai /usr/local/lib/node_modules/@anthropic-ai

RUN ln -sf ../lib/node_modules/@openai/codex/bin/codex.js /usr/local/bin/codex \
  && ln -sf ../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe /usr/local/bin/claude \
  && for tool in /opt/moon/bin/*; do \
    if [ -f "$tool" ] && [ -x "$tool" ]; then \
      ln -sf "$tool" "/usr/local/bin/$(basename "$tool")"; \
    fi; \
  done \
  && chmod +x /usr/local/bin/mooncraft-agent-* /usr/local/bin/mooncraft-runtime-* \
  && rm -rf /root/.cache /root/.npm /tmp/*

WORKDIR /workspace

ENTRYPOINT ["mooncraft-agent-entrypoint"]

RUN moon version && codex --version && claude --version
