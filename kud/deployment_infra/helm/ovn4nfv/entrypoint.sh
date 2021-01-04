#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o pipefail
set -u

set -x

WAND_APT_REPOSITORY_URL="https://packages.wand.net.nz"
OVS_VERSION="${OVS_VERSION:-2.10}"
ROOT_MOUNT_DIR="${ROOT_MOUNT_DIR:-/root}"
ROOT_OS_RELEASE="${ROOT_OS_RELEASE:-$ROOT_MOUNT_DIR/etc/os-release}"
# TODO set +x

RETCODE_SUCCESS=0
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

warn() {
    _log "WARNING " "$*"
}

error() {
    _log "ERROR   " "$*"
}

load_etc_os_release() {
    if [[ ! -f "${ROOT_OS_RELEASE}" ]]; then
        error "File ${ROOT_OS_RELEASE} not found, /etc/os-release from host must be mounted."
        exit ${RETCODE_ERROR}
    fi
    . "${ROOT_OS_RELEASE}"
    info "Running on ${NAME} ${VERSION}"
}

# TODO central and controller
add_wand_apt_repository() {
    local -r repository="deb ${WAND_APT_REPOSITORY_URL} ${VERSION_CODENAME} ovs-${OVS_VERSION}"
    if ! grep -qs -F "${repository}" "${ROOT_MOUNT_DIR}/etc/apt/sources.list.d/ovs-dpdk.list"; then
	echo "${repository}" | tee "${ROOT_MOUNT_DIR}/etc/apt/sources.list.d/ovs-dpdk.list"
    fi
    curl -L -sS "${WAND_APT_REPOSITORY_URL}/keyring.gpg" -o "${ROOT_MOUNT_DIR}/etc/apt/trusted.gpg.d/wand.gpg"
    apt -o RootDir="${ROOT_MOUNT_DIR}" update
    # TODO apt-config dump to see variables: why is the container apt not picking up host apt conf, specifically the pkgcache ones?
    # Update: in container, /etc/apt.conf.d/docker-clean messes with the Dir::Cache variables above
    # chroot, then apt?
}

install_ovs_packages() {
    apt -o RootDir="${ROOT_MOUNT_DIR}" install -y \
	openvswitch-common \
	openvswitch-switch
}

install_ovn_packages() {
    apt -o RootDir="${ROOT_MOUNT_DIR}" install -y \
	ovn-common \
	ovn-host
}

# start_ovs_service() {
#      openvswitch-switch
# }

# # TODO central
install_ovn_central_packages() {
    apt -o RootDir="${ROOT_MOUNT_DIR}" install -y \
	ovn-central
}

# enable_remote_connections_to_southbound_and_northbound_db() {
# }

# start_ovn_northbound_db_service() {
# }

# # TODO controller
# stop_ovn_controller_service() {
# }

# configure_ovs_db() {
# }

# enable_overlay_network_protocols() {
# }

# configure_overlay_local_endpoint_address() {
# }

# start_ovn_controller_service() {
# }

# ensure_br_int_bridge_exists() {
# }

main() {
    load_etc_os_release

    add_wand_apt_repository    
    install_ovs_packages
    install_ovn_packages

    # if check_cached_version; then
    #     configure_cached_installation
    #     info "Found cached version, NOT building the drivers."
    # else
    #     info "Did not find cached version, building the drivers..."
    #     download_kernel_src
    #     download_iavf_src
    #     configure_kernel_src
    #     build_iavf_src
    #     configure_iavf_installation
    #     update_cached_version
    #     info "Finished installing the drivers."
    # fi
}

main "$@"
