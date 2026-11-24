# CCCC for Railway: the official CCCC v0.4.60 Linux release binary (checked
# against the release's sha256), plus pinned agent CLIs (Claude Code, Codex, Pi)
# and a small start script that keeps every piece of state on the /data volume
# and locks the Web UI with a generated admin Access Token.
# Upstream publishes no container image, so we pin the release tarball by digest.
# Bump the version, its sha256 and the CHANGELOG.md together; a merge to main
# notifies every deployer.
FROM node:24.19.0-bookworm-slim@sha256:a9f5f7c91a432850b2a8a7797adf5eadb6c733ceed61167806cee7ea7fbc29df

ARG CCCC_VERSION=0.4.60
ARG CCCC_SHA256=2a57d0341e8a92c79cdc230fba1eac7b14a24521811c502ec15525727358a709
ARG CLAUDE_CODE_VERSION=2.1.325
ARG CODEX_VERSION=0.172.0
ARG PI_VERSION=1.6.0

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl git bash tini procps less openssh-client ripgrep jq; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL -o /tmp/cccc.tgz "https://github.com/ChesterRa/cccc/releases/download/v${CCCC_VERSION}/cccc-v${CCCC_VERSION}-x86_64-unknown-linux-gnu.tar.gz"; \
    echo "${CCCC_SHA256}  /tmp/cccc.tgz" | sha256sum -c -; \
    tar -xzf /tmp/cccc.tgz -C /tmp; \
    install -m 0755 "/tmp/cccc-v${CCCC_VERSION}-x86_64-unknown-linux-gnu/cccc" /usr/local/bin/cccc; \
    rm -rf /tmp/cccc.tgz "/tmp/cccc-v${CCCC_VERSION}-x86_64-unknown-linux-gnu"; \
    cccc --version

RUN set -eux; \
    npm install -g --no-fund --no-audit \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "@openai/codex@${CODEX_VERSION}" \
      "@earendil-works/pi-coding-agent@${PI_VERSION}"; \
    npm cache clean --force; \
    rm -rf /root/.npm /tmp/*; \
    claude --version; codex --version; pi --version

COPY start.sh /usr/local/bin/cccc-railway-start
RUN chmod 0755 /usr/local/bin/cccc-railway-start

# Everything lives on one Railway volume at /data:
#   /data/cccc       CCCC_HOME (Groups, ledgers, access tokens, settings)
#   /data/home       the agents' HOME (Claude Code, Codex and Pi logins/config)
#   /data/workspace  project directories for your Groups
ENV PORT=8848 \
    CCCC_HOME=/data/cccc \
    CCCC_WEB_HOST=0.0.0.0 \
    CCCC_WEB_TRUST_PROXY_HEADERS=1 \
    DISABLE_AUTOUPDATER=1 \
    DISABLE_TELEMETRY=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

WORKDIR /data/workspace
EXPOSE 8848
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/cccc-railway-start"]
