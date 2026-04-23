FROM node:22-bookworm

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONBIT_VERSION=latest
ARG CODEX_CLI_VERSION=0.123.0

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "${MOONBIT_VERSION}"

RUN for tool in /opt/moon/bin/*; do \
  if [ -f "$tool" ] && [ -x "$tool" ]; then \
    ln -sf "$tool" "/usr/local/bin/$(basename "$tool")"; \
  fi; \
  done

RUN npm install -g "@openai/codex@${CODEX_CLI_VERSION}" \
  && npm cache clean --force

WORKDIR /workspace

RUN moon version && codex --version
