REGISTRY?=integratedcloudnative
TAG?=latest
IMAGES=qat-driver-installer

.PHONY: all $(IMAGES)

all: $(IMAGES)

$(IMAGES):
	docker build -t $(REGISTRY)/$@:$(TAG) -f Dockerfile.$@ .
