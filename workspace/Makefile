-include .env
export

# Enable Docker BuildKit for better caching and performance
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

# Configuration: AWS account ID + derived WIF role (see .env to override ACCOUNT_ID)
IMAGE_NAME=datuak-workspace
ACCOUNT_ID ?= 539247495490
AWS_PROFILE ?= AdministratorAccess-$(ACCOUNT_ID)
REGION ?= us-east-1
AWS_ROLE_ARN=arn:aws:iam::$(ACCOUNT_ID):role/anthropic-workload-identity
ECR_URI=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com/$(IMAGE_NAME)
CLAUDE_CONTEXT_BUCKET ?= claude-context-$(ACCOUNT_ID)
IDEAS_DIR=$(HOME)/Documents/Ideas
TOOLS_CODE_DIR=$(HOME)/Development/tools-code
LATEST_PYTHON ?= 3.12
LATEST_NODE   ?= 22

# Claude provider: 0 = first-party Anthropic API via WIF (default), 1 = AWS Bedrock.
# Model names live in the Dockerfile; the entrypoint adds the Bedrock prefix when this is 1.
# Switch per run with `make claude CLAUDE_CODE_USE_BEDROCK=1`, or set it in .env.
CLAUDE_CODE_USE_BEDROCK ?= 0
WIF_TOKEN_ROOT ?= $(HOME)/.cache/datuak-wif

# Resolve GitHub token from host's gh CLI (reads macOS Keychain when needed).
# Must be defined before DEV_ENV since := is an immediate assignment.
# On a new host: run `gh auth login` once so the Keychain (macOS) or token file (Linux) is populated,
# or export GH_TOKEN before running make.
_gh_token     := $(shell x=$$(gh auth token 2>/dev/null) && echo $$x)
$(if $(_gh_token),,$(warning GH_TOKEN could not be resolved — run `gh auth login` or export GH_TOKEN. GitHub operations inside the container will fail.))

DEV_ENV := \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e AWS_SESSION_TOKEN \
	-e AWS_REGION \
	-e AWS_ACCOUNT \
	-e AWS_ROLE_ARN=$(AWS_ROLE_ARN) \
	-e CLAUDE_CODE_USE_BEDROCK=$(CLAUDE_CODE_USE_BEDROCK) \
	-e KIRO_API_KEY \
	-e GH_TOKEN \
	$(if $(_gh_token),-e GH_TOKEN=$(_gh_token)) \
	-e GITHUB_TOKEN

_vol_ideas    := $(if $(wildcard $(IDEAS_DIR)),-v "$(IDEAS_DIR)":/workspace/Ideas)
_vol_tools    := $(if $(wildcard $(TOOLS_CODE_DIR)),-v "$(TOOLS_CODE_DIR)":/workspace/tools-code)
_vol_ssh      := $(if $(wildcard $(HOME)/.ssh),-v "$(HOME)/.ssh:/home/devuser/.ssh:ro")

# SSH agent forwarding: macOS uses Docker Desktop's built-in proxy; Linux forwards the host socket
ifeq ($(shell uname),Darwin)
_env_ssh_agent := -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
else
_vol_ssh_agent := $(if $(SSH_AUTH_SOCK),-v "$(SSH_AUTH_SOCK):/ssh-agent")
_env_ssh_agent := $(if $(SSH_AUTH_SOCK),-e SSH_AUTH_SOCK=/ssh-agent)
endif

DOCKER_VOLUMES := \
	-v "$$PWD/../..":/workspace \
	-v "$(HOME)/.claude:/home/devuser/.claude" \
	-v "$(HOME)/.gemini:/home/devuser/.gemini" \
	-v "$(HOME)/.config/gh:/home/devuser/.config/gh:ro" \
	$(_vol_ideas) \
	$(_vol_tools) \
	$(_vol_ssh) \
	$(_vol_ssh_agent)

# First-party API: pass the WIF IDs, and mount the identity token the host mints into a
# per-run directory (WIF_TOKEN_DIR, set by _run-with-creds). Bedrock gets neither, since
# Claude Code would otherwise try federation instead of Bedrock.
ifeq ($(CLAUDE_CODE_USE_BEDROCK),1)
_wif_run_args :=
else
_wif_run_args := \
	-e ANTHROPIC_ORGANIZATION_ID \
	-e ANTHROPIC_FEDERATION_RULE_ID \
	-e ANTHROPIC_SERVICE_ACCOUNT_ID \
	-e ANTHROPIC_WORKSPACE_ID \
	-v "$$WIF_TOKEN_DIR":/run/anthropic-wif:ro \
	-e ANTHROPIC_IDENTITY_TOKEN_FILE=/run/anthropic-wif/token
endif

# Interactive TTY only when make runs in a terminal, so wif-test also works from scripts
DOCKER_TTY := $(shell [ -t 0 ] && echo -it || echo -i)

DOCKER_RUN := docker run $(DOCKER_TTY) --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(DEV_ENV) \
	$(_wif_run_args) \
	$(_env_ssh_agent) \
	-e GIT_CONFIG_COUNT=1 \
	-e GIT_CONFIG_KEY_0=safe.directory \
	-e "GIT_CONFIG_VALUE_0=*" \
	$(IMAGE_NAME)

DOCKER_BUILD_ARGS ?=

build:
	docker build $(DOCKER_BUILD_ARGS) -t $(IMAGE_NAME) .

build-cached: ensure-sso ensure-buildx
	@echo "Logging into ECR..."
	@aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ECR_URI)
	@echo "Building with ECR layer cache (BuildKit registry backend)..."
	docker buildx build \
		--cache-from type=registry,ref=$(ECR_URI):latest \
		--cache-to type=registry,ref=$(ECR_URI):latest,mode=max \
		--load \
		$(DOCKER_BUILD_ARGS) \
		-t $(IMAGE_NAME) .


rebuild:
	docker build --no-cache $(DOCKER_BUILD_ARGS) -t $(IMAGE_NAME) .

build-latest: DOCKER_BUILD_ARGS = --build-arg PYTHON_VERSION=$(LATEST_PYTHON) --build-arg NODEJS_MAJOR=$(LATEST_NODE)
build-latest: build

rebuild-latest: DOCKER_BUILD_ARGS = --build-arg PYTHON_VERSION=$(LATEST_PYTHON) --build-arg NODEJS_MAJOR=$(LATEST_NODE)
rebuild-latest: rebuild

sso-login:
	@if [ "$$(uname -s)" = "Darwin" ]; then \
		aws sso login --profile $(AWS_PROFILE); \
	else \
		aws sso login --profile $(AWS_PROFILE) --no-browser --use-device-code; \
	fi

ensure-sso:
	@if ! aws sts get-caller-identity --profile $(AWS_PROFILE) >/dev/null 2>&1; then \
		echo "AWS credentials expired or not present. Refreshing SSO session for profile $(AWS_PROFILE)..."; \
		$(MAKE) --no-print-directory sso-login; \
	fi

secrets-setup: ensure-sso
	@echo "=== Setting up AWS Secrets Manager for persistent credentials ==="
	@echo "Create secrets for:"
	@echo "  - KIRO_API_KEY (if using Kiro)"
	@echo "  - GH_TOKEN (GitHub personal access token, if not using gh cli)"
	@echo ""
	@echo "Example: aws secretsmanager create-secret --name kiro-api-key --secret-string 'sk-...'"
	@echo ""
	@echo "Note: Anthropic authentication uses Workload Identity Federation (WIF)."
	@echo "      No API key storage needed — AWS STS credentials exchange for tokens."

ensure-buildx:
	@if ! docker buildx ls 2>/dev/null | grep -q "buildkit-builder"; then \
		echo "buildkit-builder not found — creating with docker-container driver..."; \
		docker buildx create --name buildkit-builder --driver docker-container --use; \
	else \
		docker buildx use buildkit-builder; \
	fi
	@docker buildx inspect --bootstrap >/dev/null

# === Anthropic Workload Identity Federation (WIF) Setup ===

wif-deploy: ensure-sso
	@echo "🔐 Deploying Anthropic WIF infrastructure with CDK..."
	@cd ../infra && npx cdk deploy AnthropicWIFStack --require-approval never

wif-describe: ensure-sso
	@echo "🔍 Getting WIF role information..."
	@aws cloudformation describe-stacks --stack-name AnthropicWIFStack --region $(REGION) --query 'Stacks[0].Outputs' --output table 2>/dev/null || echo "❌ Stack not found. Run 'make wif-deploy' first."

# End-to-end check: Claude Code in the container must answer without a login prompt
wif-test: ensure-sso
	@echo "🧪 Testing Claude Code auth in the container (CLAUDE_CODE_USE_BEDROCK=$(CLAUDE_CODE_USE_BEDROCK))..."
	$(call _run-with-creds,claude -p "Reply with exactly: AUTH OK")

wif-setup: ensure-sso
	@bash scripts/setup-anthropic-wif.sh $(ARGS)

wif-docs:
	@echo "📖 Anthropic WIF Documentation: see docs/ANTHROPIC_WIF_SETUP.md"
	@cat docs/ANTHROPIC_WIF_SETUP.md | head -50

# === Multi-host Context Sync (Phase 1: One-way S3 master) ===

sync-setup: ensure-sso
	@echo "🔧 Setting up multi-host Claude context sync..."
	@bash scripts/sync-setup.sh $(AWS_PROFILE)

sync-to-s3: ensure-sso
	@if [ ! -d "$(HOME)/.claude" ]; then \
		echo "⚠️  ~/.claude does not exist — nothing to sync"; \
		exit 0; \
	fi
	@echo "📤 Uploading ~/.claude to S3 (shared master)..."
	@find -L $(HOME)/.claude -maxdepth 3 -type l -delete 2>/dev/null || true
	@aws s3 sync \
		$(HOME)/.claude \
		s3://$(CLAUDE_CONTEXT_BUCKET)/.claude \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--delete \
		--sse AES256 \
		--exclude "*.tmp" \
		--exclude ".git/*" \
		--exclude "*.lock" \
		--exclude ".DS_Store" \
		--exclude "debug/*"
	@echo "✅ Context synced to S3"

sync-from-s3: ensure-sso
	@echo "📥 Downloading ~/.claude from S3 (shared master)..."
	@mkdir -p $(HOME)/.claude
	@find -L $(HOME)/.claude -maxdepth 3 -type l -delete 2>/dev/null || true
	@aws s3 sync \
		s3://$(CLAUDE_CONTEXT_BUCKET)/.claude \
		$(HOME)/.claude \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--sse AES256 \
		--exclude "*.tmp" \
		--exclude ".git/*" \
		--exclude "*.lock" \
		--exclude "debug/*"
	@echo "✅ Context synced from S3"

list-remote-contexts:
	@echo "📋 Remote Claude contexts in S3:"
	@aws s3 ls s3://$(CLAUDE_CONTEXT_BUCKET)/ --region $(REGION) --profile $(AWS_PROFILE) --recursive | grep -E "(sessions|skills|memory|settings)" || echo "  (none found)"

ifeq ($(CLAUDE_CODE_USE_BEDROCK),1)
_run-with-creds = @eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && $(DOCKER_RUN) $(1)
else
_run-with-creds = @eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	mkdir -p "$(WIF_TOKEN_ROOT)" && export WIF_TOKEN_DIR=$$(mktemp -d "$(WIF_TOKEN_ROOT)/run.XXXXXX") && \
	bash scripts/with-wif-token.sh $(DOCKER_RUN) $(1)
endif


# Interactive targets (all fetch temporary AWS STS credentials via SSO)
# WIF is default for Anthropic authentication
claude: ensure-sso sync-from-s3
	@echo "🚀 Launching Claude Code (using Anthropic WIF)..."
	@$(call _run-with-creds,claude)
	@echo "📤 Syncing context back to S3..."
	@$(call _run-with-creds,$(MAKE) --no-print-directory sync-to-s3)

antigravity agy: ensure-sso sync-from-s3
	@echo "🚀 Launching Antigravity..."
	@$(call _run-with-creds,agy)
	@echo "📤 Syncing context back to S3..."
	@$(call _run-with-creds,$(MAKE) --no-print-directory sync-to-s3)

kiro: ensure-sso sync-from-s3
	@echo "🚀 Launching Kiro..."
	@$(call _run-with-creds,kiro-cli)
	@echo "📤 Syncing context back to S3..."
	@$(call _run-with-creds,$(MAKE) --no-print-directory sync-to-s3)

shell: ensure-sso sync-from-s3
	@echo "🚀 Launching shell..."
	@$(call _run-with-creds,/bin/bash)
	@echo "📤 Syncing context back to S3..."
	@$(call _run-with-creds,$(MAKE) --no-print-directory sync-to-s3)

debug-shell: ensure-sso
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	docker run --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(DEV_ENV) \
	  --entrypoint bash $(IMAGE_NAME) \
	  -x /usr/local/bin/entrypoint.sh /bin/bash 2>&1

# Shared ECR login session used by push and pull.
# Expands inline so TMPDIR, DOCKER_HOST_VAL, and the trap all share one shell invocation.
#   trap:            guarantees temp dir cleanup even on failure — do not remove
#   DOCKER_HOST_VAL: Docker Desktop uses a non-standard socket; reading the active context
#                    avoids hardcoding /var/run/docker.sock which does not exist there
#   isolated config: keeps the short-lived ECR token out of ~/.docker/config.json
define ecr-session
set -e; \
TMPDIR=$$(mktemp -d); \
trap "rm -rf $$TMPDIR" EXIT; \
DOCKER_HOST_VAL=$$(docker context inspect $$(docker context show) --format '{{.Endpoints.docker.Host}}' 2>/dev/null); \
echo '{"auths":{}}' > $$TMPDIR/config.json; \
aws ecr get-login-password --profile $(AWS_PROFILE) --region $(REGION) | \
	DOCKER_HOST=$$DOCKER_HOST_VAL docker --config $$TMPDIR login --username AWS --password-stdin $(ECR_URI)
endef

# Detect platform architecture and map to Docker format
define get-platform
uname -m | sed 's/x86_64/linux\/amd64/; s/aarch64/linux\/arm64/; s/arm64/linux\/arm64/'
endef

push: ensure-sso
	@echo "Rebuilding image without BuildKit cache metadata before push..."
	docker build -t $(IMAGE_NAME):latest . >/dev/null 2>&1
	docker tag $(IMAGE_NAME):latest $(ECR_URI):latest
	@$(ecr-session); \
	DOCKER_HOST=$$DOCKER_HOST_VAL docker --config $$TMPDIR push $(ECR_URI):latest

pull: ensure-sso
	@$(ecr-session); \
	DOCKER_HOST=$$DOCKER_HOST_VAL docker --config $$TMPDIR pull --platform $(shell $(get-platform)) $(ECR_URI):latest; \
	docker tag $(ECR_URI):latest $(IMAGE_NAME):latest

save:
	docker save $(IMAGE_NAME) | gzip > $(IMAGE_NAME).tar.gz

load:
	gunzip -c $(IMAGE_NAME).tar.gz | docker load

ps list-containers:
	docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

clean:
	docker container prune -f

verify: ensure-sso
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	docker run --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(DEV_ENV) $(IMAGE_NAME) bash -c '\
		FAIL=0; \
		chk() { local label=$$1; shift; "$$@" >/dev/null 2>&1 && echo "  ✅ $$label" || { echo "  ❌ $$label"; FAIL=1; }; }; \
		aws sts get-caller-identity >/tmp/_aws 2>&1 & \
		if [ -n "$${GH_TOKEN}" ]; then gh auth status >/tmp/_gh 2>&1 & fi; \
		echo "Configuration:"; \
		chk "Claude settings.json"       python3 -m json.tool $$HOME/.claude/settings.json; \
		chk "AGY mcp_config.json"        python3 -m json.tool $$HOME/.gemini/config/mcp_config.json; \
		chk "Kiro mcp.json"              test -f $$HOME/.kiro/settings/mcp.json; \
		chk "MCP registry"               test -f $$HOME/.mcp/registry.json; \
		echo "MCP servers:"; \
		chk "AWS MCP → Claude"           grep -q mcp-proxy-for-aws $$HOME/.claude.json; \
		chk "AWS MCP → AGY"              grep -q mcp-proxy-for-aws $$HOME/.gemini/config/mcp_config.json; \
		chk "AWS MCP → Kiro"             grep -q mcp-proxy-for-aws $$HOME/.kiro/settings/mcp.json; \
		chk "USAFacts → Claude"          grep -q usafacts $$HOME/.claude.json; \
		chk "USAFacts → Kiro"            grep -q usafacts $$HOME/.kiro/settings/mcp.json; \
		echo "Model config (CLAUDE_CODE_USE_BEDROCK=$$CLAUDE_CODE_USE_BEDROCK):"; \
		chk "ANTHROPIC_MODEL=$$ANTHROPIC_MODEL"   test -n "$$ANTHROPIC_MODEL"; \
		if [ "$$CLAUDE_CODE_USE_BEDROCK" = 1 ]; then \
			chk "Bedrock model IDs"      test "$${ANTHROPIC_MODEL#us.anthropic.}" != "$$ANTHROPIC_MODEL"; \
		else \
			chk "First-party model IDs"  test "$${ANTHROPIC_MODEL#us.anthropic.}" = "$$ANTHROPIC_MODEL"; \
			chk "WIF federation IDs"     test -n "$$ANTHROPIC_FEDERATION_RULE_ID" -a -n "$$ANTHROPIC_SERVICE_ACCOUNT_ID" -a -n "$$ANTHROPIC_ORGANIZATION_ID"; \
		fi; \
		echo "Tools:"; \
		chk "claude"    command -v claude; \
		chk "agy"       command -v agy; \
		chk "kiro-cli"  command -v kiro-cli; \
		chk "uv"        command -v uv; \
		chk "gh"        command -v gh; \
		chk "aws"       command -v aws; \
		chk "git"       command -v git; \
		chk "python3"   command -v python3; \
		chk "node"      command -v node; \
		echo "SSH:"; \
		chk "~/.ssh directory"   test -d $$HOME/.ssh; \
		chk "GitHub host key"    grep -q github.com $$HOME/.ssh/known_hosts; \
		wait; \
		echo "AWS credentials:"; \
		grep -q Account /tmp/_aws 2>/dev/null \
			&& echo "  ✅ AWS credentials valid" \
			|| { echo "  ❌ AWS credentials failed"; FAIL=1; }; \
		echo "GitHub authentication:"; \
		if [ -z "$${GH_TOKEN}" ]; then \
			echo "  ❌ GH_TOKEN not set"; FAIL=1; \
		elif grep -q "Active account: true" /tmp/_gh 2>/dev/null; then \
			echo "  ✅ gh CLI authenticated"; \
		else \
			echo "  ❌ gh CLI not authenticated"; FAIL=1; \
		fi; \
		echo ""; \
		[ $$FAIL -eq 0 ] && echo "✅ All checks passed" || { echo "❌ Some checks failed"; exit 1; }; \
	'

help:
	@echo "=== datuak-dev-env — Claude Code development environment ==="
	@echo ""
	@echo "📋 QUICK START:"
	@echo "  make claude                  Launch Claude Code (auto-syncs context)"
	@echo "  make agy                     Launch AGY (auto-syncs context)"
	@echo "  make kiro                    Launch Kiro (auto-syncs context)"
	@echo "  make shell                   Interactive bash shell (auto-syncs context)"
	@echo ""
	@echo "🏗️  BUILD:"
	@echo "  make build                   Build image locally (no cache)"
	@echo "  make build-cached            Build with ECR layer cache (BuildKit)"
	@echo "  make rebuild                 Full rebuild without cache"
	@echo "  make build-latest            Build with latest Python/Node versions"
	@echo ""
	@echo "🔐 AWS & CREDENTIALS:"
	@echo "  make sso-login               Refresh AWS SSO session (called automatically)"
	@echo "  make ensure-sso              Check SSO session validity"
	@echo "  make secrets-setup           Show how to create AWS Secrets Manager entries"
	@echo "  make wif-setup               Configure the AWS side of Anthropic WIF (ARGS=--check: read-only)"
	@echo "  make wif-test                Check that Claude Code in the container authenticates"
	@echo ""
	@echo "⚙️  CONTEXT PERSISTENCE:"
	@echo "  ~/.claude/                   Claude Code sessions, settings, skills, memory (mounted)"
	@echo "  ~/.gemini/                   Gemini/AGY config (mounted)"
	@echo "  ~/.ssh/                      SSH keys (mounted read-only)"
	@echo "  ~/.config/gh/                GitHub CLI config (mounted read-only)"
	@echo "  /workspace                   Your code (mounted)"
	@echo ""
	@echo "  → Persists across container restarts. New container retains all context."
	@echo ""
	@echo "🔒 SECURITY:"
	@echo "  1. Never commit secrets to .env — use AWS Secrets Manager:"
	@echo "     aws secretsmanager create-secret --name claude/anthropic-api-key --secret-string 'sk-ant-v0-...'"
	@echo ""
	@echo "  2. AWS temporary credentials are auto-provided via:"
	@echo "     aws sso login --profile $(AWS_PROFILE)  # Run once per ~12 hours"
	@echo ""
	@echo "  3. .env is local-only (never committed). Temporary creds override it at runtime:"
	@echo "     make claude                  # aws configure export-credentials is called automatically"
	@echo ""
	@echo "☁️  MULTI-HOST SYNC (S3):"
	@echo "  make sync-setup              One-time: create S3 bucket, encryption, versioning"
	@echo "  make sync-from-s3            Download latest context from S3"
	@echo "  make sync-to-s3              Upload context to S3"
	@echo "  make list-remote-contexts    List all synced contexts by hostname"
	@echo ""
	@echo "  📌 Auto-sync: 'make claude' downloads before and uploads after!"
	@echo ""
	@echo "🧪 VERIFICATION:"
	@echo "  make verify                  Check all tools, credentials, and MCP servers"
	@echo ""
	@echo "📦 REGISTRY:"
	@echo "  make push                    Push image to ECR (with layer cache)"
	@echo "  make pull                    Pull latest image from ECR"
	@echo "  make save                    Save image to .tar.gz"
	@echo "  make load                    Load image from .tar.gz"
	@echo ""
	@echo "🧹 MAINTENANCE:"
	@echo "  make clean                   Prune unused containers"
	@echo "  make ps                      List running containers"
	@echo ""
	@echo "📝 ENVIRONMENT:"
	@echo "  AWS_PROFILE                  AWS SSO profile (default: $(AWS_PROFILE))"
	@echo "  REGION                       AWS region (default: $(REGION))"
	@echo "  CLAUDE_CODE_USE_BEDROCK      0 = Anthropic API via WIF, 1 = AWS Bedrock (default: $(CLAUDE_CODE_USE_BEDROCK))"
	@echo "  LATEST_PYTHON                Python version for 'build-latest' (default: $(LATEST_PYTHON))"
	@echo "  LATEST_NODE                  Node version for 'build-latest' (default: $(LATEST_NODE))"
	@echo ""

.PHONY: build build-cached rebuild build-latest rebuild-latest sso-login ensure-sso ensure-buildx secrets-setup sync-setup sync-from-s3 sync-to-s3 list-remote-contexts claude antigravity agy kiro shell debug-shell push pull save load ps list-containers clean verify help
