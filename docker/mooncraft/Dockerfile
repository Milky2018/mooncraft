# syntax=docker/dockerfile:1.7

FROM docker:29-cli AS docker-cli

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONBIT_VERSION=nightly

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\n' > /etc/apt/apt.conf.d/80-retries \
  && rm -f /etc/apt/apt.conf.d/docker-clean \
  && printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
  set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    coreutils \
    curl \
    git \
    libsqlite3-dev \
    lsof \
    pkg-config \
    sqlite3 \
    unzip; \
  docker --version

RUN for attempt in 1 2 3 4 5; do \
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "${MOONBIT_VERSION}" && break; \
    if [ "$attempt" = "5" ]; then exit 1; fi; \
    sleep $((attempt * 5)); \
  done

WORKDIR /app

COPY moon.work /app/moon.work
COPY packages/sdk/moon.mod.json packages/sdk/moon.pkg /app/packages/sdk/
COPY apps/web/moon.mod.json apps/web/moon.pkg /app/apps/web/
COPY apps/web/admin/moon.pkg /app/apps/web/admin/
COPY services/control-plane/moon.mod.json services/control-plane/moon.pkg /app/services/control-plane/

RUN --mount=type=cache,target=/root/.moon,sharing=locked \
  for attempt in 1 2 3 4 5; do \
    moon -C /app update && break; \
    if [ "$attempt" = "5" ]; then exit 1; fi; \
    sleep $((attempt * 5)); \
  done

COPY . /app

RUN chmod +x /app/docker/mooncraft/entrypoint.sh \
  && moon -C /app build --release

EXPOSE 8080

VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/api/health || exit 1

ENTRYPOINT ["/app/docker/mooncraft/entrypoint.sh"]
