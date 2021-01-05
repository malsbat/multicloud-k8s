#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2018
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o errexit
set -o pipefail
set -u

set -x
KUBERNETES_SERVICE_HOST="${KUBERNETES_SERVICE_HOST:-localhost}"
KUBERNETES_SERVICE_PORT="${KUBERNETES_SERVICE_PORT:-8080}"
POD_NAME="${POD_NAME:-nfd-pod}"
set +x
export KUBERNETES_SERVICE_HOST KUBERNETES_SERVICE_PORT

RETCODE_ERROR=1
RETRY_COUNT=5

_log() {
    local -r prefix="$1"
    shift
    echo "[${prefix}$(date -u "+%Y-%m-%d %H:%M:%S %Z")] ""$*" >&2
}

info() {
    _log "INFO    " "$*"
}

error() {
    _log "ERROR   " "$*"
}

create_pod_yaml_with_affinity() {
    cat << POD > "${POD_NAME}-affinity.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: "feature.node.kubernetes.io/kernel-version.major"
            operator: Gt
            values:
            - '3'
        - matchExpressions:
          - key: "feature.node.kubernetes.io/kernel-version.major"
            operator: Lt
            values:
            - '20'
        - matchExpressions:
          - key: "feature.node.kubernetes.io/kernel-version.major"
            operator: In
            values:
            - '3'
            - '4'
            - '5'
        - matchExpressions:
          - key: "feature.node.kubernetes.io/kernel-version.major"
            operator: NotIn
            values:
            - '1'
        - matchExpressions:
          - key: "feature.node.kubernetes.io/kernel-version.major"
            operator: Exists
        - matchExpressions:
          - key: "feature.node.kubernetes.io/label_does_not_exist"
            operator: DoesNotExist
  containers:
  - name: with-node-affinity
    image: gcr.io/google_containers/pause:2.0
POD
}

create_pod_yaml_with_nodeSelector() {
    cat << POD > "${POD_NAME}-nodeSelector.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  nodeSelector:
    feature.node.kubernetes.io/kernel-version.major: '4'
  containers:
  - name: with-node-affinity
    image: gcr.io/google_containers/pause:2.0
POD
}

test() {
    if ! kubectl version &>/dev/null; then
        error "Missing kubectl, test not run."
        exit ${RETCODE_ERROR}
    fi

    local -r labels=$(kubectl get nodes -o json | jq .items[].metadata.labels)
    info "$labels"
    if [[ "$labels" != *"kubernetes.io"* ]]; then
        exit ${RETCODE_ERROR}
    fi

    create_pod_yaml_with_affinity
    create_pod_yaml_with_nodeSelector

    for pod_type in ${POD_TYPE:-nodeSelector affinity}; do

        kubectl delete pod "${POD_NAME}" --ignore-not-found=true --now
        local attempts=0
        while kubectl get pod "${POD_NAME}" &>/dev/null; do
            attempts=$(( attempts + 1 ))
            if (( "${attempts}" >= "${RETRY_COUNT}" )); then
                error "Timed out waiting for pod ${POD_NAME} to exit, giving up."
                exit ${RETCODE_ERROR}
            fi
            sleep 5
        done

        kubectl create -f "${POD_NAME}-${pod_type}.yaml" --validate=false

        for pod in ${POD_NAME}; do
            local status_phase=""
            while [[ "${status_phase}" != "Running" ]]; do
                local new_phase
                new_phase=$(kubectl get pods "${pod}" | awk 'NR==2{print $3}')
                if [[ "${new_phase}" != "${status_phase}" ]]; then
                    info "${pod}-${pod_type} : ${new_phase}"
                    status_phase=${new_phase}
                fi

                if [[ ${new_phase} == "Running" ]]; then
                    info "${pod_type} test is complete."
                fi
                if [[ ${new_phase} == "Err"* ]]; then
                    exit ${RETCODE_ERROR}
                fi
            done
        done
        kubectl delete pod "${POD_NAME}"
        local attempts=0
        while kubectl get pod "${POD_NAME}" &>/dev/null; do
            attempts=$(( attempts + 1 ))
            if (( "${attempts}" >= "${RETRY_COUNT}" )); then
                error "Timed out waiting for pod ${POD_NAME} to exit, giving up."
                exit ${RETCODE_ERROR}
            fi
            sleep 5
        done

    done
    info "Test is complete."
}

test
