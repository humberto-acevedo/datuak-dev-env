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
      python3 \
      python3-pip \
      shadow-utils \
      util-linux-user && \
    dnf clean all

# Install Node.js 20
RUN curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - && \
    dnf install -y nodejs

# Install Rust
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y && \
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

# Install Gemini CLI
RUN rm -f /usr/bin/gemini || true && \
    npm install -g @google/gemini-cli

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | sh && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc

# Claude Bedrock config
ENV ANTHROPIC_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
ENV ANTHROPIC_SMALL_FAST_MODEL=global.anthropic.claude-sonnet-4-5-20250929-v1:0
ENV ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION=us-east-1
ENV CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096
ENV CLAUDE_CODE_ENTRYPOINT=cli
ENV CLAUDE_CODE_USE_BEDROCK=1

# Copy Claude settings and startup script
COPY .claude/ /root/.claude/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
