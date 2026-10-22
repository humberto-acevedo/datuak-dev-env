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
      python3-dnf \
      sudo \
      shadow-utils \
      util-linux-user && \
    dnf clean all

# Build arguments for flexible version management
ARG PYTHON_VERSION=3.9
ARG NODEJS_MAJOR=20

# Warn if a newer Python is available in the repo
RUN python3 - << 'PYVERCHECK'
import os, re, subprocess
requested = os.environ.get("PYTHON_VERSION", "3.9")
try:
    out = subprocess.check_output(["dnf", "search", "python3", "--available"],
                                  stderr=subprocess.DEVNULL, text=True)
    minors = [int(m) for m in re.findall(r'^python3\.(\d+)', out, re.MULTILINE)]
    req_minor = int(requested.split('.')[1])
    if minors and max(minors) > req_minor:
        print(f"WARNING: Python 3.{max(minors)} available, installing {requested} as specified")
except Exception:
    pass
PYVERCHECK

RUN if [ "$PYTHON_VERSION" != "3.9" ]; then \
      dnf install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-pip && \
      update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 && \
      update-alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip${PYTHON_VERSION} 1 && \
      # dnf's shebang uses /usr/bin/python3; pin it to 3.9 so dnf keeps working
      sed -i '1s|#!/usr/bin/python3|#!/usr/bin/python3.9|' /usr/bin/dnf /usr/bin/dnf-3 /usr/bin/aws /usr/bin/aws_completer; \
      # Reinstall awscli for the pinned Python 3.9 to ensure dependencies are available
      /usr/bin/pip3.9 install --upgrade awscli; \
    fi

RUN pip3 install --upgrade uv skills

# Warn if a newer Node.js major version is available
RUN python3 - << 'NODEVERCHECK'
import json, os, subprocess
requested = os.environ.get("NODEJS_MAJOR", "20")
if requested != "current":
    try:
        data = subprocess.check_output(["curl", "-s", "https://nodejs.org/dist/index.json"], text=True)
        latest = int(json.loads(data)[0]["version"].lstrip("v").split(".")[0])
        if latest > int(requested):
            print(f"WARNING: Node.js {latest} available, installing {requested} as specified")
    except Exception:
        pass
NODEVERCHECK

# Install specified Node.js version
RUN if [ "$NODEJS_MAJOR" = "current" ]; then \
      dnf install -y nodejs; \
    else \
      curl -fsSL https://rpm.nodesource.com/setup_${NODEJS_MAJOR}.x | bash - && \
      dnf install -y nodejs; \
    fi

# Install Rust (system-wide so devuser can use cargo)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y --no-modify-path && \
    cp -r /root/.cargo /usr/local/cargo && \
    chmod -R a+rx /usr/local/cargo/bin && \
    ln -sf /usr/local/cargo/bin/cargo  /usr/local/bin/cargo  && \
    ln -sf /usr/local/cargo/bin/rustc  /usr/local/bin/rustc  && \
    ln -sf /usr/local/cargo/bin/rustup /usr/local/bin/rustup

# Create non-root user early so configs go directly into their home
RUN useradd -m -s /bin/bash devuser && \
    mkdir -p /workspace && \
    chown -R devuser:devuser /workspace && \
    echo "devuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/devuser && \
    chmod 440 /etc/sudoers.d/devuser

# Install AWS CDK
RUN npm install -g aws-cdk

# Install React, Amplify, and Terraform
RUN npm install -g create-react-app react react-dom && \
    npm install -g @aws-amplify/cli && \
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y terraform || \
    curl -fsSL https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip -o /tmp/terraform.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin && rm /tmp/terraform.zip && \
    chmod +x /usr/local/bin/terraform

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

# Configure git credential store and SSH options
RUN git config --global credential.helper store && \
    git config --global core.sshCommand "ssh -o StrictHostKeyChecking=accept-new"

# Claude model configuration - AWS Bedrock cross-region inference profiles (us.)
# Latest Claude 5 family models: Haiku 5.5 (default), Sonnet 5.5, Opus 5.5
# Verified available in AWS Bedrock US region
# See docs/BEDROCK_MODEL_ACCESS.md for account-level access status
ENV ANTHROPIC_MODEL=us.anthropic.claude-haiku-5-5
ENV ANTHROPIC_SMALL_FAST_MODEL=us.anthropic.claude-sonnet-5-5
ENV ANTHROPIC_LARGE_MODEL=us.anthropic.claude-opus-5-5
ENV ANTHROPIC_ULTRA_FAST_MODEL=us.anthropic.claude-haiku-5-5
ENV AWS_REGION=us-east-1
ENV CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384
ENV CLAUDE_CODE_ENTRYPOINT=cli
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

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

# Install Kiro CLI and expose globally (preserving original binary names)
RUN curl --proto '=https' --tlsv1.2 -sSf \
      'https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip' \
      -o /tmp/kirocli.zip && \
    unzip /tmp/kirocli.zip -d /tmp/kirocli && \
    /tmp/kirocli/kirocli/install.sh --force --no-confirm && \
    rm -rf /tmp/kirocli.zip /tmp/kirocli && \
    cp /root/.local/bin/kiro-cli* /usr/local/bin/ && \
    chmod a+rx /usr/local/bin/kiro-cli*

# MCP server configuration variables
ARG MCP_AWS_ENDPOINT=https://aws-mcp.us-east-1.api.aws/mcp
ARG MCP_AWS_VERSION=1.6.3
ARG AWS_REGION=us-east-1

# Generate MCP configurations (Bedrock cross-region inference profiles, AWS auth)
RUN python3 - << 'PYEOF'
import json, os

endpoint = os.environ["MCP_AWS_ENDPOINT"]
version  = os.environ["MCP_AWS_VERSION"]
region   = os.environ["AWS_REGION"]

proxy_args = [
    f"mcp-proxy-for-aws@{version}",
    endpoint,
    "--metadata",
    f"AWS_REGION={region}",
]
proxy_base = {"command": "uvx", "timeout": 100000, "transport": "stdio", "args": proxy_args}

model      = os.environ["ANTHROPIC_MODEL"]
small_fast = os.environ["ANTHROPIC_SMALL_FAST_MODEL"]
large      = os.environ["ANTHROPIC_LARGE_MODEL"]
ultra_fast = os.environ["ANTHROPIC_ULTRA_FAST_MODEL"]

claude_cfg = {
    "mcpServers": {"aws-mcp": proxy_base},
    "permissions": {"aws:*": "allow"},
    "env": {
        "CLAUDE_CODE_USE_BEDROCK": "1",
        "AWS_REGION": region,
    },
    "modelSettings": {
        "model": model,
        "smallFastModel": small_fast,
        "largeModel": large,
        "ultraFastModel": ultra_fast,
        "maxOutputTokens": 16384,
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
print("✅ Bedrock regional MCP configurations generated")
PYEOF

# Bake sync-time utility script into image at build time
RUN cat > /usr/local/bin/sync-time << 'SCRIPT'
#!/bin/bash
echo "==> Synchronizing system clock with AWS..."
# Try multiple sources with staggered timeouts; allow graceful degradation
REMOTE_DATE=""
for url in https://aws.amazon.com https://www.google.com https://www.github.com; do
  if REMOTE_DATE=$(curl -sI --max-time 8 "$url" 2>/dev/null | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r'); then
    [[ -n "$REMOTE_DATE" ]] && break
  fi
done
if [[ -z "$REMOTE_DATE" ]]; then
  echo "Warning: Could not fetch remote server time (network/DNS timeout)." >&2
  exit 0
fi
echo "Time before sync: $(date -u)"
# Use a wrapper to prevent hang: if date hangs, kill it after 3 seconds
if /usr/bin/timeout 3 sudo date -s "$REMOTE_DATE" >/dev/null 2>&1; then
  echo "Time after sync : $(date -u)"
  echo "✅ Clock successfully synchronized."
else
  echo "⚠️  Clock sync skipped (try running with --cap-add=SYS_TIME)." >&2
fi
exit 0
SCRIPT
RUN chmod +x /usr/local/bin/sync-time && \
    ln -sf /usr/local/bin/sync-time /usr/local/bin/sync-clock

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Switch to non-root user for runtime
ENV HOME=/home/devuser
USER devuser
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
