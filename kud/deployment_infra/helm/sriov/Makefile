TAG?=latest
REGISTRY?=malsbat
IMAGE=iavf-driver-installer

container:
	docker build --pull -t ${REGISTRY}/${IMAGE}:${TAG} .

push:
	docker push ${REGISTRY}/${IMAGE}:${TAG}

run:
	docker run --rm -it --privileged -v /opt/iavf:/usr/local/iavf -v /:/root ${REGISTRY}/${IMAGE}:${TAG}

.PHONY: container push run
