FROM node:24-bookworm AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONCRAFT_AGENT_RUNTIME_VERSION=0.4.4
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.128.0
ARG MOONCRAFT_TEMPLATES_REPO=https://github.com/moonbitlang/mooncraft-templates.git
ARG MOONCRAFT_TEMPLATES_REF=main

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
  && rm -rf /var/lib/apt/lists/*

COPY docker/agent-runtime/install/ /opt/mooncraft/install/

RUN chmod +x /opt/mooncraft/install/*.sh

RUN MOONBIT_VERSION="${MOONBIT_VERSION}" /opt/mooncraft/install/install-moonbit.sh

RUN CODEX_CLI_VERSION="${CODEX_CLI_VERSION}" /opt/mooncraft/install/install-node-agents.sh

COPY packages/runtime_protocol/ /opt/mooncraft/packages/runtime_protocol/
COPY docker/agent-runtime/runtime-service/ /opt/mooncraft/runtime-service/

RUN printf '%s\n' 'members = ["packages/runtime_protocol", "runtime-service"]' \
  > /opt/mooncraft/moon.work

RUN moon -C /opt/mooncraft/runtime-service build --target native --release \
  && mkdir -p /opt/mooncraft/bin \
  && cp /opt/mooncraft/_build/native/release/build/mooncraft/runtime-service/runtime-service.exe /opt/mooncraft/bin/mooncraft-runtime-service \
  && chmod +x /opt/mooncraft/bin/mooncraft-runtime-service

RUN /opt/mooncraft/install/install-moonbit-skills.sh

RUN MOONCRAFT_TEMPLATES_REPO="${MOONCRAFT_TEMPLATES_REPO}" \
  MOONCRAFT_TEMPLATES_REF="${MOONCRAFT_TEMPLATES_REF}" \
  /opt/mooncraft/install/install-mooncraft-templates.sh

RUN rm -rf /root/.cache /root/.npm /tmp/*

FROM debian:bookworm-slim AS run

ARG DEBIAN_FRONTEND=noninteractive

ENV MOON_HOME=/home/mooncraft/.moon
ENV HOME=/home/mooncraft
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN set -eux; \
  packages="\
    bash \
    build-essential \
    ca-certificates \
    coreutils \
    curl \
    git \
    jq \
    libstdc++6 \
    pkg-config \
    python3 \
    ripgrep \
  "; \
  for attempt in 1 2 3 4 5; do \
    apt-get -o Acquire::Retries=5 update \
      && apt-get -o Acquire::Retries=5 install -y --download-only --no-install-recommends $packages \
      && break; \
    if [ "$attempt" = "5" ]; then \
      exit 1; \
    fi; \
    rm -rf /var/lib/apt/lists/*; \
    sleep "$((attempt * 5))"; \
  done; \
  apt-get install -y --no-install-recommends $packages; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*; \
  useradd --create-home --uid 10001 --shell /bin/bash mooncraft; \
  mkdir -p /workspace /artifacts /home/mooncraft/.moon; \
  chown -R mooncraft:mooncraft /workspace /artifacts /home/mooncraft

ARG MOONCRAFT_AGENT_RUNTIME_VERSION=0.4.4
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.128.0

LABEL org.opencontainers.image.title="MoonCraft Runtime"
LABEL org.opencontainers.image.description="MoonCraft Runtime Protocol v3 image with an HTTP Runtime Service."
LABEL mooncraft.agent_runtime.version="${MOONCRAFT_AGENT_RUNTIME_VERSION}"
LABEL mooncraft.runtime.version="${MOONCRAFT_AGENT_RUNTIME_VERSION}"
LABEL mooncraft.runtime_protocol.version="3"
LABEL mooncraft.codex.version="${CODEX_CLI_VERSION}"
LABEL mooncraft.moonbit.version="${MOONBIT_VERSION}"

COPY docker/agent-runtime/bin/ /usr/local/bin/
COPY docker/agent-runtime/mooncraft-agent-system.md /opt/mooncraft/mooncraft-agent-system.md
COPY --from=build /opt/moon /opt/moon
COPY --from=build /opt/codex/bin/codex /usr/local/bin/codex
COPY --from=build /opt/mooncraft/bin/mooncraft-runtime-service /usr/local/bin/mooncraft-runtime-service
COPY --from=build /opt/codex-skill-seed /opt/codex-skill-seed
COPY --from=build /opt/mooncraft/templates /opt/mooncraft/templates

RUN for tool in /opt/moon/bin/*; do \
    if [ -f "$tool" ] && [ -x "$tool" ]; then \
      ln -sf "$tool" "/usr/local/bin/$(basename "$tool")"; \
    fi; \
  done \
  && chmod +x /usr/local/bin/mooncraft-agent-* /usr/local/bin/mooncraft-runtime-service \
  && rm -rf /root/.cache /root/.npm /tmp/*

USER mooncraft

WORKDIR /workspace

EXPOSE 8080 4792

ENTRYPOINT ["mooncraft-agent-entrypoint"]

RUN moon update --quiet \
  && test -d "$MOON_HOME/registry/index/.git" \
  && test -w "$MOON_HOME" \
  && moon version \
  && python3 --version \
  && codex --version \
  && test -x /usr/local/bin/mooncraft-runtime-service \
  && test -x /usr/local/bin/mooncraft-preview-run
