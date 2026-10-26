FROM amazonlinux:2023

# === ARGs at top (before any RUN) to enable caching ===
ARG PYTHON_VERSION=3.9
ARG NODEJS_MAJOR=20

# === Layer 1: Base system packages (rarely changes) ===
RUN dnf install -y --allowerasing \
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
      util-linux-user \
      'dnf-command(config-manager)' && \
    dnf clean all

# === Layer 2: Python version management (conditional) ===
RUN if [ "$PYTHON_VERSION" != "3.9" ]; then \
      dnf install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-pip && \
      update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 && \
      update-alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip${PYTHON_VERSION} 1 && \
      sed -i '1s|#!/usr/bin/python3|#!/usr/bin/python3.9|' /usr/bin/dnf /usr/bin/dnf-3 /usr/bin/aws /usr/bin/aws_completer && \
      /usr/bin/pip3.9 install --upgrade awscli; \
    fi && \
    dnf clean all

# === Layer 3: Python tools ===
RUN pip3 install --upgrade uv skills

# === Layer 4: Node.js (deterministic, pinned versions) ===
RUN if [ "$NODEJS_MAJOR" = "current" ]; then \
      dnf install -y nodejs && dnf clean all; \
    else \
      curl -fsSL https://rpm.nodesource.com/setup_${NODEJS_MAJOR}.x | bash - && \
      dnf install -y nodejs && \
      dnf clean all; \
    fi

# === Layer 5: Node.js global packages (pinned versions for reproducibility) ===
RUN npm install -g \
      create-react-app@5.0.1 \
      react@18.2.0 \
      react-dom@18.2.0 \
      @aws-amplify/cli@14.5.1 \
      aws-cdk@2.139.0

# === Layer 6: Rust (system-wide) ===
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y --no-modify-path && \
    cp -r /root/.cargo /usr/local/cargo && \
    chmod -R a+rx /usr/local/cargo/bin && \
    ln -sf /usr/local/cargo/bin/cargo  /usr/local/bin/cargo  && \
    ln -sf /usr/local/cargo/bin/rustc  /usr/local/bin/rustc  && \
    ln -sf /usr/local/cargo/bin/rustup /usr/local/bin/rustup

# === Layer 7: Non-root user setup ===
RUN useradd -m -s /bin/bash devuser && \
    mkdir -p /workspace && \
    chown -R devuser:devuser /workspace && \
    echo "devuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/devuser && \
    chmod 440 /etc/sudoers.d/devuser

# === Layer 8: Terraform (pinned version) ===
RUN curl -fsSL https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip -o /tmp/terraform.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin && \
    rm /tmp/terraform.zip && \
    chmod +x /usr/local/bin/terraform

# === Layer 9: Google Cloud CLI ===
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
    dnf install -y libxcrypt-compat.x86_64 google-cloud-cli && \
    dnf clean all
RUN $(gcloud info --format="value(basic.python_location)") -m pip install numpy
ENV CLOUDSDK_PYTHON_SITEPACKAGES=1

# === Layer 10: GitHub CLI ===
RUN dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && \
    dnf install -y gh && \
    dnf clean all

# === Layer 11: Git configuration ===
RUN git config --system safe.directory '*' && \
    git config --system credential.helper store && \
    git config --system core.sshCommand "ssh -o StrictHostKeyChecking=accept-new"

# === Layer 12: Claude Code CLI ===
RUN curl --proto '=https' --tlsv1.2 -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
    sh /tmp/claude-install.sh && \
    rm /tmp/claude-install.sh && \
    cp -L /root/.local/bin/claude /usr/local/bin/claude && \
    chmod a+rx /usr/local/bin/claude

# === Layer 13: Antigravity CLI (AGY) ===
RUN curl --proto '=https' --tlsv1.2 -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy-install.sh && \
    cat /tmp/agy-install.sh | bash && \
    rm /tmp/agy-install.sh && \
    cp /root/.local/bin/agy /usr/local/bin/agy && \
    chmod a+rx /usr/local/bin/agy

# === Layer 14: Kiro CLI ===
RUN curl --proto '=https' --tlsv1.2 -sSf \
      'https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip' \
      -o /tmp/kirocli.zip && \
    unzip /tmp/kirocli.zip -d /tmp/kirocli && \
    /tmp/kirocli/kirocli/install.sh --force --no-confirm && \
    rm -rf /tmp/kirocli.zip /tmp/kirocli && \
    cp /root/.local/bin/kiro-cli* /usr/local/bin/ && \
    chmod a+rx /usr/local/bin/kiro-cli*

# === Layer 15: MCP configuration (ARG-driven, regenerates only on config changes) ===
ARG MCP_AWS_ENDPOINT=https://aws-mcp.us-east-1.api.aws/mcp
ARG MCP_AWS_VERSION=1.6.3
ARG AWS_REGION=us-east-1

RUN python3 - << 'PYEOF'
import json, os

endpoint   = os.environ["MCP_AWS_ENDPOINT"]
version    = os.environ["MCP_AWS_VERSION"]
region     = os.environ["AWS_REGION"]

registry = {
    "version": "1",
    "servers": {
        "aws-mcp": {
            "description": "AWS services via AWS MCP proxy",
            "auto_load": ["claude", "agy", "kiro"],
            "config": {
                "command": "uvx",
                "timeout": 100000,
                "transport": "stdio",
                "args": [
                    f"mcp-proxy-for-aws@{version}",
                    endpoint,
                    "--metadata",
                    f"AWS_REGION={region}",
                ],
            },
            "overrides": {
                "agy":  {"env": {"AWS_REGION": region}},
                "kiro": {"env": {"AWS_REGION": region}},
            },
        },
        "usafacts": {
            "description": "USAFacts public data and statistics",
            "auto_load": ["claude", "kiro"],
            "config": {
                "transport": "http",
                "url": "https://data.mcp.usafacts.org/mcp",
            },
        },
    },
}

def build_server_config(srv, tool):
    cfg = dict(srv["config"])
    cfg.update(srv.get("overrides", {}).get(tool, {}))
    return cfg

def build_mcp_servers(registry, tool):
    return {
        name: build_server_config(srv, tool)
        for name, srv in registry["servers"].items()
        if tool in srv.get("auto_load", [])
    }

claude_servers = build_mcp_servers(registry, "claude")
agy_servers    = build_mcp_servers(registry, "agy")
kiro_servers   = build_mcp_servers(registry, "kiro")

claude_settings_cfg = {
    "permissions": {"aws:*": "allow"},
    "env": {
        "CLAUDE_CODE_USE_BEDROCK": "1",
        "AWS_REGION": region,
    },
}
claude_state_cfg = {
    "mcpServers": claude_servers,
}
agy_cfg = {
    "mcpServers": agy_servers,
}
kiro_cfg = {
    "mcpServers": kiro_servers,
}

os.makedirs("/home/devuser/.mcp",                  exist_ok=True)
os.makedirs("/home/devuser/.claude",               exist_ok=True)
os.makedirs("/home/devuser/.gemini/config",        exist_ok=True)
os.makedirs("/home/devuser/.kiro/settings",        exist_ok=True)

with open("/home/devuser/.mcp/registry.json",             "w") as f:
    json.dump(registry, f, indent=2)
# mcpServers must live in ~/.claude.json (user state); settings.json does not expose MCP servers to /mcp
with open("/home/devuser/.claude.json",                   "w") as f:
    json.dump(claude_state_cfg, f, indent=2)
with open("/home/devuser/.claude/settings.json",          "w") as f:
    json.dump(claude_settings_cfg, f, indent=2)
with open("/home/devuser/.gemini/config/mcp_config.json", "w") as f:
    json.dump(agy_cfg, f, indent=2)
with open("/home/devuser/.kiro/settings/mcp.json",        "w") as f:
    json.dump(kiro_cfg, f, indent=2)

os.system("chown -R devuser:devuser /home/devuser/.mcp /home/devuser/.claude /home/devuser/.gemini /home/devuser/.kiro")
print(f"✅ MCP registry written  ({len(registry['servers'])} servers)")
print(f"   Claude: {list(claude_servers.keys())}")
print(f"   AGY:    {list(agy_servers.keys())}")
print(f"   Kiro:   {list(kiro_servers.keys())}")
PYEOF

# === Layer 16: Environment variables (Bedrock, Claude models, SDK config) ===
ENV ANTHROPIC_MODEL=us.anthropic.claude-haiku-5-5
ENV ANTHROPIC_SMALL_FAST_MODEL=us.anthropic.claude-sonnet-5-5
ENV ANTHROPIC_LARGE_MODEL=us.anthropic.claude-opus-5-5
ENV ANTHROPIC_ULTRA_FAST_MODEL=us.anthropic.claude-haiku-5-5
ENV AWS_REGION=us-east-1
ENV CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384
ENV CLAUDE_CODE_ENTRYPOINT=cli
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# === Layer 17: Sync-time utility ===
RUN cat > /usr/local/bin/sync-time << 'SCRIPT'
#!/bin/bash
echo "==> Synchronizing system clock with AWS..."
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

# === Layer 18: Entrypoint (final COPY layer) ===
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# === Layer 19: Runtime setup (non-root user, workdir) ===
ENV HOME=/home/devuser
USER devuser
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
