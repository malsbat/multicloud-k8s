TAG?=latest
REGISTRY?=malsbat
IMAGE=ovn4nfv-installer

container:
	docker build --pull -t ${REGISTRY}/${IMAGE}:${TAG} .

push:
	docker push ${REGISTRY}/${IMAGE}:${TAG}

run:
# TODO	docker run --rm -it --privileged -v /:/root ${REGISTRY}/${IMAGE}:${TAG}
# TODO mounting /etc/apt means it will read the correct apt config values from the host, so update works
# TODO but install still doesn't work: wants to unlink root, plus post-install scripts will run in container, not host
	docker run --rm -it --privileged -v /:/root -v /etc/apt:/etc/apt --entrypoint /bin/bash ${REGISTRY}/${IMAGE}:${TAG}

.PHONY: container push run
