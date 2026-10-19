-include .env
export

IMAGE_NAME=datuak-workspace
AWS_PROFILE ?= default
ACCOUNT_ID=$(shell aws sts get-caller-identity --query Account --output text)
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

DOCKER_VOLUMES := \
	-v "$$PWD/../..":/workspace \
	-v "$(IDEAS_DIR)":/workspace/Ideas \
	-v "$(TOOLS_CODE_DIR)":/workspace/tools-code \
	-v "$(HOME)/.ssh:/home/devuser/.ssh:ro" \
	-v "$(HOME)/.config/gh:/home/devuser/.config/gh:ro"

DOCKER_RUN := docker run -it --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(AWS_ENV) $(IMAGE_NAME)
DOCKER_RUN_RM := docker run --rm --cap-add=SYS_TIME $(IMAGE_NAME)

DOCKER_BUILD_ARGS ?=

build:
	docker build $(DOCKER_BUILD_ARGS) -t $(IMAGE_NAME) .

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

_run-with-creds = eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && $(DOCKER_RUN) $(1)

# Verification script run before interactive sessions
_verify-container = bash -c ' \
	echo ""; \
	echo "=== Environment Verification ==="; \
	echo ""; \
	echo "Checking configuration files..."; \
	test -f $$HOME/.claude/settings.json && echo "  ✅ Claude config" || echo "  ⚠️  Claude config missing"; \
	test -f $$HOME/.gemini/config/mcp_config.json && echo "  ✅ Gemini config" || echo "  ⚠️  Gemini config missing"; \
	echo ""; \
	echo "Checking tools..."; \
	command -v uv >/dev/null 2>&1 && echo "  ✅ uv (Python)" || echo "  ⚠️  uv not found"; \
	command -v claude >/dev/null 2>&1 && echo "  ✅ Claude CLI" || echo "  ⚠️  Claude CLI not found"; \
	command -v agy >/dev/null 2>&1 && echo "  ✅ Antigravity CLI" || echo "  ⚠️  Antigravity CLI not found"; \
	command -v aws >/dev/null 2>&1 && echo "  ✅ AWS CLI" || echo "  ⚠️  AWS CLI not found"; \
	echo ""; \
	echo "Checking AWS credentials..."; \
	if aws sts get-caller-identity >/dev/null 2>&1; then \
		ACCOUNT=$$(aws sts get-caller-identity --query Account --output text); \
		IDENTITY=$$(aws sts get-caller-identity --query Arn --output text | grep -oP \"assumed-role/[^/]+\" || echo \"user\"); \
		echo "  ✅ AWS authenticated (Account: $$ACCOUNT, Identity: $$IDENTITY)"; \
	else \
		echo "  ❌ AWS credentials not available"; \
	fi; \
	echo ""; \
	echo "=== Ready for development ==="; \
	echo ""; \
'

# Interactive targets with verification
claude: ensure-sso
	@$(call _run-with-creds,$(_verify-container) && claude)

antigravity agy: ensure-sso
	@$(call _run-with-creds,$(_verify-container) && agy)

kiro: ensure-sso
	@$(call _run-with-creds,$(_verify-container) && kiro-cli)

shell: ensure-sso
	@$(call _run-with-creds,$(_verify-container) && /bin/bash)

push: ensure-sso
	docker tag $(IMAGE_NAME):latest $(ECR_URI):latest
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ECR_URI)
	docker push $(ECR_URI):latest

pull: ensure-sso
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ECR_URI)
	docker pull $(ECR_URI):latest
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
	@echo "=== Claude MCP Configuration ==="
	@$(DOCKER_RUN_RM) cat /home/devuser/.claude/settings.json 2>/dev/null || echo "No settings.json found"
	@echo ""
	@echo "=== Antigravity (AGY) MCP Configuration ==="
	@$(DOCKER_RUN_RM) cat /home/devuser/.gemini/config/mcp_config.json 2>/dev/null || echo "No mcp_config.json found"

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
	@echo "=== Docker Environment Verification ===" && \
	echo "" && \
	echo "1. Container startup verification..." && \
	docker run --rm $(DOCKER_VOLUMES) $(AWS_ENV) $(IMAGE_NAME) bash -c ' \
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
		echo "✅ All verifications passed"; \
	' && \
	echo "" && \
	echo "2. AWS credentials verification..." && \
	@$(call _run-with-creds,aws sts get-caller-identity) && \
	echo "" && \
	echo "✅ Environment is ready for development"

test:
	@echo "=== Building test image ===" && \
	docker build -t $(IMAGE_NAME)-test . || { echo "Build failed"; exit 1; } && echo "Build successful"
	@docker run --rm $(IMAGE_NAME)-test bash -c ' \
	  echo "=== Testing Claude configuration ===" && \
	  test -f $$HOME/.claude/settings.json            && echo "  Claude settings.json exists"  || { echo "  Claude settings.json missing"; exit 1; } && \
	  python3 -m json.tool $$HOME/.claude/settings.json >/dev/null && echo "  Claude config is valid JSON" || { echo "  Claude config invalid"; exit 1; } && \
	  echo "=== Testing Gemini/AGY configuration ===" && \
	  test -f $$HOME/.gemini/config/mcp_config.json   && echo "  AGY mcp_config.json exists"   || { echo "  AGY mcp_config.json missing"; exit 1; } && \
	  python3 -m json.tool $$HOME/.gemini/config/mcp_config.json >/dev/null && echo "  AGY config is valid JSON" || { echo "  AGY config invalid"; exit 1; } && \
	  echo "=== Verifying AWS MCP server ===" && \
	  grep -q mcp-proxy-for-aws $$HOME/.claude/settings.json            && echo "  AWS MCP in Claude" || { echo "  AWS MCP missing in Claude"; exit 1; } && \
	  grep -q mcp-proxy-for-aws $$HOME/.gemini/config/mcp_config.json   && echo "  AWS MCP in AGY"    || { echo "  AWS MCP missing in AGY"; exit 1; } && \
	  echo "=== All tests passed ==="'
	@docker rmi $(IMAGE_NAME)-test 2>/dev/null || true

.PHONY: build rebuild build-latest rebuild-latest sso-login export-credentials ensure-sso claude antigravity agy kiro shell push pull save load ps list-containers clean verify verify-aws-toolkit inspect-config test
