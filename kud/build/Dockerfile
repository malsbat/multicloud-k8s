FROM ubuntu:18.04 as base
ARG KUD_ENABLE_TESTS=false
ARG KUD_PLUGIN_ENABLED=false
ENV http_proxy=$http_proxy
ENV HTTP_PROXY=$HTTP_PROXY
ENV https_proxy=$https_proxy
ENV HTTPS_PROXY=$HTTPS_PROXY
ENV no_proxy=$no_proxy
ENV NO_PROXY=$NO_PROXY
ENV KUD_ENABLE_TESTS=$KUD_ENABLE_TESTS
ENV KUD_PLUGIN_ENABLED=$KUD_PLUGIN_ENABLED
ADD . /usr/src/multicloud-k8s
RUN /usr/src/multicloud-k8s/kud/build/acquire-apt-proxy.sh
USER root
SHELL ["/bin/bash", "-c"]
WORKDIR /usr/src/multicloud-k8s/kud/hosting_providers/containerized
RUN ./installer --install_pkg
ENTRYPOINT ["tail -f /dev/null"]
