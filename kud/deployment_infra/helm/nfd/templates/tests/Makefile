TAG?=latest
REGISTRY?=malsbat
IMAGE=nfd-test

container:
	docker build --pull -t ${REGISTRY}/${IMAGE}:${TAG} .

push:
	docker push ${REGISTRY}/${IMAGE}:${TAG}

run:
	docker run --rm -it -v TODO:/var/run/secrets/kubernetes.io/serviceaccount ${REGISTRY}/${IMAGE}:${TAG}

.PHONY: container push run
