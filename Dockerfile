FROM node:22-slim

# Install git (needed by Claude Code)
RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user with configurable UID to match host (default 501 for macOS)
ARG USER_UID=501
RUN useradd -m -s /bin/bash -u ${USER_UID} claude

USER claude

WORKDIR /app

ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
