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
	$(_vol_ideas) \
	$(_vol_tools) \
	$(_vol_ssh) \
	$(_vol_ssh_agent)

DOCKER_RUN := docker run -it --rm --cap-add=SYS_TIME $(DOCKER_VOLUMES) $(DEV_ENV) \
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

ensure-buildx:
	@if ! docker buildx ls 2>/dev/null | grep -q "buildkit-builder"; then \
		echo "buildkit-builder not found — creating with docker-container driver..."; \
		docker buildx create --name buildkit-builder --driver docker-container --use; \
	else \
		docker buildx use buildkit-builder; \
	fi
	@docker buildx inspect --bootstrap >/dev/null

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
		chk "AWS MCP → Claude"           grep -q mcp-proxy-for-aws $$HOME/.claude/settings.json; \
		chk "AWS MCP → AGY"              grep -q mcp-proxy-for-aws $$HOME/.gemini/config/mcp_config.json; \
		chk "AWS MCP → Kiro"             grep -q mcp-proxy-for-aws $$HOME/.kiro/settings/mcp.json; \
		chk "USAFacts → Claude"          grep -q usafacts $$HOME/.claude/settings.json; \
		chk "USAFacts → Kiro"            grep -q usafacts $$HOME/.kiro/settings/mcp.json; \
		echo "Model config:"; \
		chk "Haiku 5.5 default"          grep -q us.anthropic.claude-haiku-5-5 $$HOME/.claude/settings.json; \
		chk "Sonnet 5.5"                 grep -q us.anthropic.claude-sonnet-5-5 $$HOME/.claude/settings.json; \
		chk "Opus 5.5"                   grep -q us.anthropic.claude-opus-5-5 $$HOME/.claude/settings.json; \
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

.PHONY: build build-cached rebuild build-latest rebuild-latest sso-login ensure-sso ensure-buildx claude antigravity agy kiro shell debug-shell push pull save load ps list-containers clean verify
