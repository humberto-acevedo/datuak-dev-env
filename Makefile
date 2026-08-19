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

DOCKER_RUN := docker run -it --rm $(DOCKER_VOLUMES) $(AWS_ENV) $(IMAGE_NAME)

build:
	docker build -t $(IMAGE_NAME) .

rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .

sso-login:
	aws sso login --profile $(AWS_PROFILE)

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

.PHONY: build rebuild sso-login ensure-sso claude antigravity kiro shell save load list-containers clean-stopped
