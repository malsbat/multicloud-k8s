#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2020
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

proxy_conf="/etc/apt/apt.conf.d/01proxy"

if [[ -n "${http_proxy+x}" ]]; then
    echo "Acquire::http::Proxy \"$http_proxy\";" >> $proxy_conf
elif [[ -n "${HTTP_PROXY+x}" ]]; then
    echo "Acquire::http::Proxy \"$HTTP_PROXY\";" >> $proxy_conf
fi

if [[ -n "${https_proxy+x}" ]]; then
    echo "Acquire::https::Proxy \"$https_proxy\";" >> $proxy_conf
elif [[ -n "${HTTPS_PROXY+x}" ]]; then
    echo "Acquire::https::Proxy \"$HTTPS_PROXY\";" >> $proxy_conf
fi
