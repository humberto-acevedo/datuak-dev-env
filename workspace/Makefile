-include .env
export

# Enable Docker BuildKit for better caching and performance
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

IMAGE_NAME=datuak-workspace
AWS_PROFILE ?= default
ACCOUNT_ID=$(shell aws sts get-caller-identity --profile $(AWS_PROFILE) --query Account --output text 2>/dev/null)
REGION ?= us-east-1
ECR_URI=$(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com/$(IMAGE_NAME)
IDEAS_DIR=$(HOME)/Documents/Ideas
TOOLS_CODE_DIR=$(HOME)/Development/tools-code
LATEST_PYTHON ?= 3.12
LATEST_NODE   ?= 22

AWS_ENV := \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e AWS_SESSION_TOKEN \
	-e AWS_REGION \
	-e AWS_ACCOUNT \
	-e KIRO_API_KEY

_vol_ideas    := $(if $(wildcard $(IDEAS_DIR)),-v "$(IDEAS_DIR)":/workspace/Ideas)
_vol_tools    := $(if $(wildcard $(TOOLS_CODE_DIR)),-v "$(TOOLS_CODE_DIR)":/workspace/tools-code)
_vol_ssh      := $(if $(wildcard $(HOME)/.ssh),-v "$(HOME)/.ssh:/home/devuser/.ssh:ro")
_vol_gh       := $(if $(wildcard $(HOME)/.config/gh),-v "$(HOME)/.config/gh:/home/devuser/.config/gh:ro")

# SSH agent forwarding: macOS uses Docker Desktop's built-in proxy; Linux forwards the host socket
ifeq ($(shell uname),Darwin)
_env_ssh_agent := -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
else
_vol_ssh_agent := $(if $(SSH_AUTH_SOCK),-v "$(SSH_AUTH_SOCK):/ssh-agent")
_env_ssh_agent := $(if $(SSH_AUTH_SOCK),-e SSH_AUTH_SOCK=/ssh-agent)
endif

DOCKER_VOLUMES := \
	-v "$$PWD/../..":/workspace \
	$(_vol_ideas) \
	$(_vol_tools) \
	$(_vol_ssh) \
	$(_vol_gh) \
	$(_vol_ssh_agent)

# Use -t only when stdin is a real TTY (fails silently otherwise on some terminals)
DOCKER_TTY := $(shell test -t 0 && echo -t || true)

DOCKER_RUN := docker run -i $(DOCKER_TTY) --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(AWS_ENV) \
	$(_env_ssh_agent) \
	$(IMAGE_NAME)
DOCKER_RUN_RM := docker run --rm --cap-add=SYS_TIME $(IMAGE_NAME)

DOCKER_BUILD_ARGS ?=

build:
	docker build $(DOCKER_BUILD_ARGS) -t $(IMAGE_NAME) .

build-cached: ensure-sso
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
	@aws sso login --profile $(AWS_PROFILE)
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env)

export-credentials:
	@aws configure export-credentials --profile $(AWS_PROFILE) --format env

ensure-sso:
	@if ! aws sts get-caller-identity --profile $(AWS_PROFILE) >/dev/null 2>&1; then \
		echo "AWS credentials expired or not present. Refreshing SSO session for profile $(AWS_PROFILE)..."; \
		aws sso login --profile $(AWS_PROFILE); \
	fi

_run-with-creds = @eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && $(DOCKER_RUN) $(1)


# Interactive targets
claude: ensure-sso
	@$(call _run-with-creds,claude)

antigravity agy: ensure-sso
	@$(call _run-with-creds,agy)

kiro: ensure-sso
	@$(call _run-with-creds,kiro-cli)

shell: ensure-sso
	@$(call _run-with-creds,/bin/bash)

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

inspect-config:
	@echo "=== MCP Registry (canonical source) ==="
	@$(DOCKER_RUN_RM) cat /home/devuser/.mcp/registry.json 2>/dev/null || echo "No registry.json found"
	@echo ""
	@echo "=== Claude MCP Configuration ==="
	@$(DOCKER_RUN_RM) cat /home/devuser/.claude/settings.json 2>/dev/null || echo "No settings.json found"
	@echo ""
	@echo "=== Antigravity (AGY) MCP Configuration ==="
	@$(DOCKER_RUN_RM) cat /home/devuser/.gemini/config/mcp_config.json 2>/dev/null || echo "No mcp_config.json found"
	@echo ""
	@echo "=== Kiro MCP Configuration ==="
	@$(DOCKER_RUN_RM) cat /home/devuser/.kiro/settings/mcp.json 2>/dev/null || echo "No mcp.json found"

verify-aws-toolkit:
	@echo "=== AWS Agent Toolkit Verification ==="
	@$(DOCKER_RUN_RM) bash -c "echo '1. uv (Python package manager):' && pip3 show uv && echo '2. Skills CLI:' && pip3 show skills || echo 'skills not installed'" || echo "Error running verification"
	@echo ""
	@echo "MCP Server: mcp-proxy-for-aws@1.6.3"
	@echo "Endpoint: https://aws-mcp.us-east-1.api.aws/mcp"
	@echo "Timeout: 100000ms"
	@echo ""
	@$(MAKE) inspect-config

verify: ensure-sso
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	echo "=== Docker Environment Verification ===" && \
	docker run --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(AWS_ENV) $(IMAGE_NAME) bash -c ' \
		echo ""; \
		echo "Configuration Files:"; \
		test -f $$HOME/.claude/settings.json && echo "  ✅ Claude config exists" || echo "  ❌ Claude config missing"; \
		test -f $$HOME/.gemini/config/mcp_config.json && echo "  ✅ Gemini config exists" || echo "  ❌ Gemini config missing"; \
		echo ""; \
		echo "Global Tools:"; \
		command -v claude >/dev/null 2>&1 && echo "  ✅ Claude CLI installed" || echo "  ❌ Claude CLI missing"; \
		command -v agy >/dev/null 2>&1 && echo "  ✅ Antigravity CLI installed" || echo "  ❌ Antigravity CLI missing"; \
		command -v kiro-cli >/dev/null 2>&1 && echo "  ✅ Kiro CLI installed" || echo "  ❌ Kiro CLI missing"; \
		command -v uv >/dev/null 2>&1 && echo "  ✅ uv package manager installed" || echo "  ❌ uv missing"; \
		echo ""; \
		echo "System Tools:"; \
		aws --version && echo "  ✅ AWS CLI available" || echo "  ❌ AWS CLI error"; \
		git --version && echo "  ✅ Git available" || echo "  ❌ Git error"; \
		python3 --version && echo "  ✅ Python 3 available" || echo "  ❌ Python 3 error"; \
		node --version && echo "  ✅ Node.js available" || echo "  ❌ Node.js error"; \
		echo ""; \
		echo "SSH Configuration:"; \
		test -d $$HOME/.ssh && echo "  ✅ SSH directory exists" || echo "  ⚠️  SSH directory missing"; \
		test -f $$HOME/.ssh/known_hosts && grep -q github.com $$HOME/.ssh/known_hosts && echo "  ✅ GitHub host key found" || echo "  ⚠️  GitHub host key missing"; \
		echo ""; \
		echo "AWS Credentials:"; \
		aws sts get-caller-identity; \
	' && \
	echo "" && \
	echo "✅ Environment is ready for development"

test:
	@echo "=== Building test image ===" && \
	docker build -t $(IMAGE_NAME)-test . || { echo "Build failed"; exit 1; } && echo "Build successful"
	@docker run --rm $(IMAGE_NAME)-test bash -c ' \
	  echo "=== Testing Claude configuration ===" && \
	  test -f $$HOME/.claude/settings.json            && echo "  ✓ Claude settings.json exists"  || { echo "  ✗ Claude settings.json missing"; exit 1; } && \
	  python3 -m json.tool $$HOME/.claude/settings.json >/dev/null && echo "  ✓ Claude config is valid JSON" || { echo "  ✗ Claude config invalid"; exit 1; } && \
	  echo "=== Testing Gemini/AGY configuration ===" && \
	  test -f $$HOME/.gemini/config/mcp_config.json   && echo "  ✓ AGY mcp_config.json exists"   || { echo "  ✗ AGY mcp_config.json missing"; exit 1; } && \
	  python3 -m json.tool $$HOME/.gemini/config/mcp_config.json >/dev/null && echo "  ✓ AGY config is valid JSON" || { echo "  ✗ AGY config invalid"; exit 1; } && \
	  echo "=== Verifying AWS MCP server ===" && \
	  grep -q mcp-proxy-for-aws $$HOME/.claude/settings.json            && echo "  ✓ AWS MCP in Claude" || { echo "  ✗ AWS MCP missing in Claude"; exit 1; } && \
	  grep -q mcp-proxy-for-aws $$HOME/.gemini/config/mcp_config.json   && echo "  ✓ AWS MCP in AGY"    || { echo "  ✗ AWS MCP missing in AGY"; exit 1; } && \
	  grep -q mcp-proxy-for-aws $$HOME/.kiro/settings/mcp.json           && echo "  ✓ AWS MCP in Kiro"   || { echo "  ✗ AWS MCP missing in Kiro"; exit 1; } && \
	  grep -q usafacts $$HOME/.claude/settings.json                       && echo "  ✓ USAFacts in Claude" || { echo "  ✗ USAFacts missing in Claude"; exit 1; } && \
	  grep -q usafacts $$HOME/.kiro/settings/mcp.json                     && echo "  ✓ USAFacts in Kiro"  || { echo "  ✗ USAFacts missing in Kiro"; exit 1; } && \
	  test -f $$HOME/.mcp/registry.json                                   && echo "  ✓ MCP registry exists" || { echo "  ✗ MCP registry missing"; exit 1; } && \
	  echo "=== Verifying Claude Model Configuration ===" && \
	  grep -q "us.anthropic.claude-haiku-5-5" $$HOME/.claude/settings.json && echo "  ✓ Haiku 5.5 set as default model" || { echo "  ✗ Haiku 5.5 not configured"; exit 1; } && \
	  grep -q "us.anthropic.claude-sonnet-5-5" $$HOME/.claude/settings.json && echo "  ✓ Sonnet 5.5 configured" || { echo "  ✗ Sonnet 5.5 not configured"; exit 1; } && \
	  grep -q "us.anthropic.claude-opus-5-5" $$HOME/.claude/settings.json && echo "  ✓ Opus 5.5 configured" || { echo "  ✗ Opus 5.5 not configured"; exit 1; } && \
	  echo "=== All tests passed ==="'
	@docker rmi $(IMAGE_NAME)-test 2>/dev/null || true

.PHONY: build build-cached rebuild build-latest rebuild-latest sso-login export-credentials ensure-sso claude antigravity agy kiro shell push pull save load ps list-containers clean verify verify-aws-toolkit inspect-config test
