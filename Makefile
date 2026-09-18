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
	-v "$(HOME)/.ssh:/root/.ssh" \
	-v "$(HOME)/.config/gh:/root/.config/gh"

DOCKER_RUN := docker run -it --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(AWS_ENV) $(IMAGE_NAME)

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

claude: ensure-sso
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	$(DOCKER_RUN) claude

antigravity: ensure-sso
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	$(DOCKER_RUN) agy

kiro: ensure-sso
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	$(DOCKER_RUN) kiro-cli

shell: ensure-sso
	@eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	$(DOCKER_RUN) /bin/bash

save:
	docker save $(IMAGE_NAME) | gzip > $(IMAGE_NAME).tar.gz

load:
	gunzip -c $(IMAGE_NAME).tar.gz | docker load

list-containers:
	docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

clean-stopped:
	docker container prune -f

verify-aws-toolkit:
	@echo "=== AWS Agent Toolkit Verification ==="
	@docker run --rm $(IMAGE_NAME) bash -c "echo '1. uv (Python package manager):' && pip3 show uv && echo '2. Skills CLI:' && pip3 show skills || echo 'skills not installed'" || echo "Error running verification"
	@echo ""
	@echo "MCP Server: mcp-proxy-for-aws@1.6.3"
	@echo "Endpoint: https://aws-mcp.us-east-1.api.aws/mcp"
	@echo "Timeout: 100000ms"
	@echo ""
	@echo "=== Claude MCP Configuration ==="
	@docker run --rm $(IMAGE_NAME) cat /root/.claude/settings.json 2>/dev/null || echo "No Claude settings.json found"
	@echo ""
	@echo "=== Antigravity (AGY) MCP Configuration ==="
	@docker run --rm $(IMAGE_NAME) cat /root/.gemini/config/mcp_config.json 2>/dev/null || echo "No AGY mcp_config.json found"

inspect-claude-config:
	@echo "=== Claude MCP Configuration ==="
	@docker run --rm -v "$$PWD/.claude:/root/.claude" $(IMAGE_NAME) cat /root/.claude/settings.json 2>/dev/null || echo "No settings.json found"

inspect-agy-config:
	@echo "=== Antigravity (AGY) MCP Configuration ==="
	@docker run --rm -v "$$PWD/.gemini:/root/.gemini" $(IMAGE_NAME) cat /root/.gemini/config/mcp_config.json 2>/dev/null || echo "No mcp_config.json found"

inspect-antigravity-config: inspect-agy-config

.PHONY: build rebuild sso-login export-credentials ensure-sso claude antigravity kiro shell save load list-containers clean-stopped verify-aws-toolkit inspect-claude-config inspect-agy-config inspect-antigravity-config
