-include .env
export

IMAGE_NAME=datuak-workspace-llm
AWS_PROFILE ?= default

AWS_ENV := \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e AWS_SESSION_TOKEN \
	-e AWS_REGION \
	-e AWS_ACCOUNT

build:
	docker build -t $(IMAGE_NAME) .

sso-login:
	aws sso login --profile $(AWS_PROFILE)

IDEAS_DIR=$(HOME)/Documents/Ideas

claude: sso-login
	eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	docker run -it --rm -v "$$PWD/../..":/workspace -v "$(IDEAS_DIR)":/workspace/Ideas $(AWS_ENV) $(IMAGE_NAME) claude

gemini: sso-login
	eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	docker run -it --rm -v "$$PWD/../..":/workspace -v "$(IDEAS_DIR)":/workspace/Ideas $(AWS_ENV) $(IMAGE_NAME) gemini

shell: sso-login
	eval $$(aws configure export-credentials --profile $(AWS_PROFILE) --format env) && \
	docker run -it --rm -v "$$PWD/../..":/workspace -v "$(IDEAS_DIR)":/workspace/Ideas $(AWS_ENV) $(IMAGE_NAME) /bin/bash

save:
	docker save $(IMAGE_NAME) | gzip > $(IMAGE_NAME).tar.gz

load:
	gunzip -c $(IMAGE_NAME).tar.gz | docker load

list-containers:
	docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

clean-stopped:
	docker container prune -f

.PHONY: build sso-login claude gemini shell save load list-containers clean-stopped
