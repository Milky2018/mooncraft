FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONBIT_VERSION=latest

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  build-essential \
  ca-certificates \
  curl \
  git \
  lsof \
  pkg-config \
  sqlite3 \
  libsqlite3-dev \
  unzip \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "${MOONBIT_VERSION}"

WORKDIR /app

COPY . /app

RUN chmod +x /app/docker/entrypoint.sh \
  && moon update --manifest-path /app/moon.work \
  && moon build --manifest-path /app/moon.work

EXPOSE 8080

VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/api/health || exit 1

ENTRYPOINT ["/app/docker/entrypoint.sh"]
