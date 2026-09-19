-include .env
export

IMAGE_NAME=datuak-workspace
AWS_PROFILE ?= default
IDEAS_DIR=$(HOME)/Documents/Ideas
TOOLS_CODE_DIR=$(HOME)/Development/tools-code

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
DOCKER_RUN_RM := docker run --rm $(IMAGE_NAME)

build:
	docker build -t $(IMAGE_NAME) .

rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .

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

claude: ensure-sso
	@$(call _run-with-creds,claude)

antigravity agy: ensure-sso
	@$(call _run-with-creds,agy)

kiro: ensure-sso
	@$(call _run-with-creds,kiro-cli)

shell: ensure-sso
	@$(call _run-with-creds,/bin/bash)

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

test:
	@echo "=== Building test image with generated configurations ===" && \
	docker build -t $(IMAGE_NAME)-test . || { echo "❌ Build failed"; exit 1; } && echo "✅ Build successful"
	@echo ""
	@echo "=== Testing Claude configuration ===" && \
	docker run --rm $(IMAGE_NAME)-test test -f /home/devuser/.claude/settings.json && echo "✅ Claude settings.json exists" || { echo "❌ Claude settings.json missing"; exit 1; } && \
	docker run --rm $(IMAGE_NAME)-test cat /home/devuser/.claude/settings.json 2>/dev/null | python3 -m json.tool >/dev/null && echo "✅ Claude config is valid JSON" || { echo "❌ Claude config invalid"; exit 1; }
	@echo ""
	@echo "=== Testing Gemini/AGY configuration ===" && \
	docker run --rm $(IMAGE_NAME)-test test -f /home/devuser/.gemini/config/mcp_config.json && echo "✅ AGY mcp_config.json exists" || { echo "❌ AGY mcp_config.json missing"; exit 1; } && \
	docker run --rm $(IMAGE_NAME)-test cat /home/devuser/.gemini/config/mcp_config.json 2>/dev/null | python3 -m json.tool >/dev/null && echo "✅ AGY config is valid JSON" || { echo "❌ AGY config invalid"; exit 1; }
	@echo ""
	@echo "=== Verifying AWS MCP server configuration ===" && \
	docker run --rm $(IMAGE_NAME)-test grep -q "mcp-proxy-for-aws" /home/devuser/.claude/settings.json && echo "✅ AWS MCP in Claude" || { echo "❌ AWS MCP missing in Claude"; exit 1; } && \
	docker run --rm $(IMAGE_NAME)-test grep -q "mcp-proxy-for-aws" /home/devuser/.gemini/config/mcp_config.json && echo "✅ AWS MCP in AGY" || { echo "❌ AWS MCP missing in AGY"; exit 1; }
	@echo ""
	@echo "✅ All tests passed" && \
	docker rmi $(IMAGE_NAME)-test 2>/dev/null || true

.PHONY: build rebuild sso-login export-credentials ensure-sso claude antigravity agy kiro shell save load ps list-containers clean verify-aws-toolkit inspect-config test
