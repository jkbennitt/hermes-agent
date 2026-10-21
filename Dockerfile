FROM ghcr.io/astral-sh/uv:0.13.4-python3.13-trixie@sha256:d6b4d13b4d926ca0deb4f1bc454aaa7e3bbb02ce1929ec1bd2e94a18c47ad757 AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

# Disable Python stdout buffering to ensure logs are printed immediately
ENV PYTHONUNBUFFERED=1

# Store Playwright browsers outside the volume mount so the build-time
# install survives the /opt/data volume overlay at runtime.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# Install system dependencies in one layer, clear APT cache.
# debian:13.4 predates the eMudhra distrust (GHSA-6q48-6c7w-9gw2).
# Track the latest ca-certificates from the configured trixie suites
# (including trixie-security) instead of an exact version pin, which
# breaks once Debian supersedes 20250419+deb13u1. Fail the build if
# the installed bundle is older than that security update.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential nodejs npm python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get upgrade -y ca-certificates && \
    v="$(dpkg-query -W -f '${Version}' ca-certificates)" && \
    if ! dpkg --compare-versions "$v" ge "20250419+deb13u1"; then \
        echo "ca-certificates $v is older than 20250419+deb13u1" >&2; \
        exit 1; \
    fi && \
    rm -rf /var/lib/apt/lists/*

# Non-root user for runtime; UID can be overridden via HERMES_UID at runtime
RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

COPY . /opt/hermes
WORKDIR /opt/hermes

# Install Node dependencies and Playwright as root (--with-deps needs apt)
RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    cd /opt/hermes/scripts/whatsapp-bridge && \
    npm install --prefer-offline --no-audit && \
    npm cache clean --force

# Hand ownership to hermes user, then install Python deps in a virtualenv
RUN chown -R hermes:hermes /opt/hermes
USER hermes

RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

USER root
RUN chmod +x /opt/hermes/docker/entrypoint.sh

ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
