IMAGE_NAME=datuak-workspace-llm

AWS_ENV := \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e AWS_SESSION_TOKEN \
	-e AWS_REGION

build:
	docker build -t $(IMAGE_NAME) .

claude:
	docker run -it --rm -v "$$PWD/..":/workspace $(AWS_ENV) $(IMAGE_NAME) claude

gemini:
	docker run -it --rm -v "$$PWD/..":/workspace $(AWS_ENV) $(IMAGE_NAME) gemini

shell:
	docker run -it --rm -v "$$PWD/..":/workspace $(AWS_ENV) $(IMAGE_NAME) /bin/bash

save:
	docker save $(IMAGE_NAME) | gzip > $(IMAGE_NAME).tar.gz

load:
	gunzip -c $(IMAGE_NAME).tar.gz | docker load

list-containers:
	docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

clean-stopped:
	docker container prune -f

.PHONY: build claude gemini shell save load list-containers clean-stopped
