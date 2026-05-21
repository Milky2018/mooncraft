FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG MOONBIT_VERSION=latest

ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\n' > /etc/apt/apt.conf.d/80-retries

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  build-essential \
  ca-certificates \
  coreutils \
  curl \
  git \
  gnupg \
  lsof \
  nodejs \
  npm \
  pkg-config \
  sqlite3 \
  libsqlite3-dev \
  unzip \
  && rm -rf /var/lib/apt/lists/*

RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && . /etc/os-release \
  && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' "$(dpkg --print-architecture)" "$VERSION_CODENAME" > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends docker-ce-cli \
  && docker --version \
  && rm -rf /var/lib/apt/lists/*

RUN for attempt in 1 2 3 4 5; do \
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "${MOONBIT_VERSION}" && break; \
    if [ "$attempt" = "5" ]; then exit 1; fi; \
    sleep $((attempt * 5)); \
  done

WORKDIR /app

COPY . /app

RUN npm install --no-save --no-package-lock playwright@1.57.0 \
  && npx playwright install --with-deps chromium

RUN chmod +x /app/docker/mooncraft/entrypoint.sh \
  && for attempt in 1 2 3 4 5; do \
    moon -C /app update && break; \
    if [ "$attempt" = "5" ]; then exit 1; fi; \
    sleep $((attempt * 5)); \
  done \
  && moon -C /app build --release

EXPOSE 8080

VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/api/health || exit 1

ENTRYPOINT ["/app/docker/mooncraft/entrypoint.sh"]
