FROM amazonlinux:2023

RUN dnf update -y && \
    dnf install -y --allowerasing \
      awscli \
      gcc \
      git \
      tig \
      jq \
      make \
      tar \
      zip \
      curl \
      vim \
      unzip \
      tmux \
      python3 \
      python3-pip \
      shadow-utils \
      util-linux-user && \
    dnf clean all

# Install uv (Python package manager) for AWS MCP proxy
RUN pip3 install --upgrade uv

# Install AWS toolkit skills CLI
RUN pip3 install skills

# Install Node.js 20
RUN curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - && \
    dnf install -y nodejs

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y && \
    echo 'source /root/.cargo/env' >> /root/.bashrc

# Install AWS CDK
RUN npm install -g aws-cdk

# Install gcloud CLI
RUN tee /etc/yum.repos.d/google-cloud-cli.repo << EOM
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
RUN rpm -qa gpg-pubkey* | grep -i google | xargs -r rpm -e || true && \
    dnf clean all && \
    dnf install -y libxcrypt-compat.x86_64 google-cloud-cli
RUN $(gcloud info --format="value(basic.python_location)") -m pip install numpy
ENV CLOUDSDK_PYTHON_SITEPACKAGES=1

# Install GitHub CLI (gh)
RUN dnf install -y 'dnf-command(config-manager)' && \
    dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && \
    dnf install -y gh && \
    dnf clean all

# Install Antigravity CLI (agy)
RUN curl --proto '=https' --tlsv1.2 -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy-install.sh && \
    cat /tmp/agy-install.sh | bash && \
    rm /tmp/agy-install.sh

# Install Claude Code CLI
RUN curl --proto '=https' --tlsv1.2 -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
    sh /tmp/claude-install.sh && \
    rm /tmp/claude-install.sh && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc

# Claude Bedrock config
ENV ANTHROPIC_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
ENV ANTHROPIC_SMALL_FAST_MODEL=global.anthropic.claude-sonnet-4-5-20250929-v1:0
ENV ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION=us-east-1
ENV CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096
ENV CLAUDE_CODE_ENTRYPOINT=cli
ENV CLAUDE_CODE_USE_BEDROCK=1
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# Install Kiro CLI
RUN curl --proto '=https' --tlsv1.2 -sSf \
      'https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip' \
      -o /tmp/kirocli.zip && \
    unzip /tmp/kirocli.zip -d /tmp/kirocli && \
    /tmp/kirocli/kirocli/install.sh --force --no-confirm && \
    rm -rf /tmp/kirocli.zip /tmp/kirocli

# MCP server configuration variables
ARG MCP_AWS_ENDPOINT=https://aws-mcp.us-east-1.api.aws/mcp
ARG MCP_AWS_VERSION=1.6.3
ARG AWS_REGION=us-east-1

# Generate Claude MCP configuration at build time
RUN mkdir -p /root/.claude && \
    cat > /root/.claude/settings.json << 'EOF'
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "transport": "stdio",
      "args": [
        "mcp-proxy-for-aws@1.6.3",
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--metadata",
        "AWS_REGION=us-east-1"
      ]
    }
  },
  "permissions": {
    "aws:*": "allow"
  },
  "modelSettings": {
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "smallFastModel": "global.anthropic.claude-sonnet-4-5-20250929-v1:0",
    "maxOutputTokens": 4096
  }
}
EOF

# Generate Gemini/Antigravity MCP configuration at build time
RUN mkdir -p /root/.gemini/config && \
    cat > /root/.gemini/config/mcp_config.json << 'EOF'
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "transport": "stdio",
      "args": [
        "mcp-proxy-for-aws@1.6.3",
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--metadata",
        "AWS_REGION=us-east-1"
      ],
      "env": {
        "AWS_REGION": "us-east-1"
      }
    }
  }
}
EOF

# Bake sync-time utility script into image at build time
RUN cat > /usr/local/bin/sync-time << 'SCRIPT'
#!/bin/bash
echo "==> Synchronizing system clock with AWS..."
REMOTE_DATE=$(curl -sI --max-time 4 https://aws.amazon.com 2>/dev/null | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r')
if [[ -z "$REMOTE_DATE" ]]; then
  echo "Warning: Could not fetch AWS server time to sync clock." >&2
  exit 1
fi
echo "Time before sync: $(date -u)"
if date -s "$REMOTE_DATE" >/dev/null 2>&1; then
  echo "Time after sync : $(date -u)"
  echo "✅ Clock successfully synchronized."
else
  echo "⚠️  Failed to set clock. (Did you run container with --cap-add=SYS_TIME?)" >&2
fi
SCRIPT
RUN chmod +x /usr/local/bin/sync-time && \
    ln -sf /usr/local/bin/sync-time /usr/local/bin/sync-clock

# Create non-root user for development
RUN useradd -m -s /bin/bash devuser && \
    mkdir -p /workspace && \
    chown -R devuser:devuser /workspace

# Copy entrypoint script and set as executable
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
