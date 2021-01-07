TAG?=latest
REGISTRY?=malsbat
IMAGE=qat-driver-installer

container:
	docker build --pull -t ${REGISTRY}/${IMAGE}:${TAG} .

push:
	docker push ${REGISTRY}/${IMAGE}:${TAG}

run:
	docker run --rm -it --privileged --pid=host -v /opt/qat:/usr/local/qat -v /:/root -v /run/systemd/system:/root/run/systemd/system --entrypoint /bin/bash ${REGISTRY}/${IMAGE}:${TAG}
#	docker run --rm -it --privileged --pid=host -v /opt/qat:/usr/local/qat -v /:/root -v /run/systemd/system:/root/run/systemd/system ${REGISTRY}/${IMAGE}:${TAG}

.PHONY: container push run
