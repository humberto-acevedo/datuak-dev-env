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

# Install Rust (system-wide so devuser can use cargo)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y --no-modify-path && \
    cp -r /root/.cargo /usr/local/cargo && \
    chmod -R a+rx /usr/local/cargo/bin && \
    ln -sf /usr/local/cargo/bin/cargo  /usr/local/bin/cargo  && \
    ln -sf /usr/local/cargo/bin/rustc  /usr/local/bin/rustc  && \
    ln -sf /usr/local/cargo/bin/rustup /usr/local/bin/rustup

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

# Install Antigravity CLI (agy) and expose globally
RUN curl --proto '=https' --tlsv1.2 -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy-install.sh && \
    cat /tmp/agy-install.sh | bash && \
    rm /tmp/agy-install.sh && \
    cp /root/.local/bin/agy /usr/local/bin/agy && \
    chmod a+rx /usr/local/bin/agy

# Install Claude Code CLI and expose globally
RUN curl --proto '=https' --tlsv1.2 -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
    sh /tmp/claude-install.sh && \
    rm /tmp/claude-install.sh && \
    cp -L /root/.local/bin/claude /usr/local/bin/claude && \
    chmod a+rx /usr/local/bin/claude

# Claude model configuration - hybrid-ready (Global by default, Bedrock on demand)
# Set CLAUDE_ENVIRONMENT=production to use Bedrock endpoints for VPC isolation
# Default: Global endpoints (cost-efficient, lower latency, access to all models including Fable)
# Production: Bedrock endpoints (VPC isolated, compliance-ready, 10% cost premium, no Fable 5.1)
# Pricing: Anthropic API Global = Bedrock Global; Regional adds 10% surcharge
ENV CLAUDE_ENVIRONMENT=development
ENV ANTHROPIC_MODEL=global.anthropic.claude-haiku-4-5-20251001-v1:0
ENV ANTHROPIC_SMALL_FAST_MODEL=global.anthropic.claude-sonnet-4-5-20250929-v1:0
ENV ANTHROPIC_LARGE_MODEL=global.anthropic.claude-opus-5-20250514-v1:0
ENV ANTHROPIC_ULTRA_FAST_MODEL=global.anthropic.claude-fable-5-1-20250514-v1:0
ENV ANTHROPIC_BEDROCK_HAIKU=us.anthropic.claude-haiku-4-5-20251001-v1:0
ENV ANTHROPIC_BEDROCK_SONNET=us.anthropic.claude-sonnet-4-5-20250929-v1:0
ENV ANTHROPIC_BEDROCK_OPUS=us.anthropic.claude-opus-5-20250514-v1:0
ENV ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION=us-east-1
ENV CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096
ENV CLAUDE_CODE_ENTRYPOINT=cli
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# Install Kiro CLI and expose globally
RUN curl --proto '=https' --tlsv1.2 -sSf \
      'https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip' \
      -o /tmp/kirocli.zip && \
    unzip /tmp/kirocli.zip -d /tmp/kirocli && \
    /tmp/kirocli/kirocli/install.sh --force --no-confirm && \
    rm -rf /tmp/kirocli.zip /tmp/kirocli && \
    cp /root/.local/bin/kiro-cli /usr/local/bin/kiro && \
    chmod a+rx /usr/local/bin/kiro

# Create non-root user early so configs go directly into their home
RUN useradd -m -s /bin/bash devuser && \
    mkdir -p /workspace && \
    chown -R devuser:devuser /workspace && \
    dnf install -y sudo && \
    echo "devuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/devuser && \
    chmod 440 /etc/sudoers.d/devuser

# MCP server configuration variables
ARG MCP_AWS_ENDPOINT=https://aws-mcp.us-east-1.api.aws/mcp
ARG MCP_AWS_VERSION=1.6.3
ARG AWS_REGION=us-east-1

# Generate both MCP configurations from shared ARG values (single source of truth)
RUN python3 - << 'PYEOF'
import json, os

endpoint = os.environ.get("MCP_AWS_ENDPOINT", "https://aws-mcp.us-east-1.api.aws/mcp")
version  = os.environ.get("MCP_AWS_VERSION",  "1.6.3")
region   = os.environ.get("AWS_REGION",        "us-east-1")

proxy_args = [
    f"mcp-proxy-for-aws@{version}",
    endpoint,
    "--metadata",
    f"AWS_REGION={region}",
]
proxy_base = {"command": "uvx", "timeout": 100000, "transport": "stdio", "args": proxy_args}

# Determine which endpoint tier to use based on CLAUDE_ENVIRONMENT
env_mode = os.environ.get("CLAUDE_ENVIRONMENT", "development").lower()
use_bedrock = env_mode == "production"

# Select model endpoints based on environment
if use_bedrock:
    model = os.environ.get("ANTHROPIC_BEDROCK_HAIKU", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
    small_fast = os.environ.get("ANTHROPIC_BEDROCK_SONNET", "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    large = os.environ.get("ANTHROPIC_BEDROCK_OPUS", "us.anthropic.claude-opus-5-20250514-v1:0")
else:
    model = os.environ.get("ANTHROPIC_MODEL", "global.anthropic.claude-haiku-4-5-20251001-v1:0")
    small_fast = os.environ.get("ANTHROPIC_SMALL_FAST_MODEL", "global.anthropic.claude-sonnet-4-5-20250929-v1:0")
    large = os.environ.get("ANTHROPIC_LARGE_MODEL", "global.anthropic.claude-opus-5-20250514-v1:0")

claude_cfg = {
    "mcpServers": {"aws-mcp": proxy_base},
    "permissions": {"aws:*": "allow"},
    "modelSettings": {
        "model": model,
        "smallFastModel": small_fast,
        "maxOutputTokens": 4096,
    },
}
agy_cfg = {
    "mcpServers": {"aws-mcp": {**proxy_base, "env": {"AWS_REGION": region}}},
}

os.makedirs("/home/devuser/.claude",        exist_ok=True)
os.makedirs("/home/devuser/.gemini/config", exist_ok=True)

with open("/home/devuser/.claude/settings.json",        "w") as f:
    json.dump(claude_cfg, f, indent=2)
with open("/home/devuser/.gemini/config/mcp_config.json", "w") as f:
    json.dump(agy_cfg, f, indent=2)

os.system("chown -R devuser:devuser /home/devuser/.claude /home/devuser/.gemini")
print("✅ MCP configurations generated")
PYEOF

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
if sudo date -s "$REMOTE_DATE" >/dev/null 2>&1; then
  echo "Time after sync : $(date -u)"
  echo "✅ Clock successfully synchronized."
else
  echo "⚠️  Failed to set clock. (Did you run container with --cap-add=SYS_TIME?)" >&2
fi
SCRIPT
RUN chmod +x /usr/local/bin/sync-time && \
    ln -sf /usr/local/bin/sync-time /usr/local/bin/sync-clock

# Copy entrypoint script and set as executable
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to non-root user for runtime
ENV HOME=/home/devuser
USER devuser
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
