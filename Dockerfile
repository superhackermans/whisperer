FROM node:22-slim

# Install git (needed by Claude Code)
RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user (required for --dangerously-skip-permissions)
RUN useradd -m -s /bin/bash claude
USER claude

WORKDIR /app

ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
