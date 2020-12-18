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

KERNEL_SRC_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x"
KERNEL_SRC_ARCHIVE="linux-$(uname -r | cut -d- -f1 | sed -e 's/\.0$//').tar.xz"
KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-/usr/src/linux}"
ROOT_OS_RELEASE="${ROOT_OS_RELEASE:-/root/etc/os-release}"
IAVF_DRIVER_VERSION="${IAVF_DRIVER_VERSION:-3.7.34}"
IAVF_DRIVER_DOWNLOAD_URL_DEFAULT="https://downloadmirror.intel.com/28943/eng/iavf-${IAVF_DRIVER_VERSION}.tar.gz"
IAVF_DRIVER_DOWNLOAD_URL="${IAVF_DRIVER_DOWNLOAD_URL:-$IAVF_DRIVER_DOWNLOAD_URL_DEFAULT}"
IAVF_INSTALL_DIR_HOST="${IAVF_INSTALL_DIR_HOST:-/opt/iavf}"
IAVF_INSTALL_DIR_CONTAINER="${IAVF_INSTALL_DIR_CONTAINER:-/usr/local/iavf}"
IAVF_DRIVER_ARCHIVE="$(basename "${IAVF_DRIVER_DOWNLOAD_URL}")"
ROOT_MOUNT_DIR="${ROOT_MOUNT_DIR:-/root}"
CACHE_FILE="${IAVF_INSTALL_DIR_CONTAINER}/.cache"
set +x

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
    info "Running on ${NAME} kernel version $(uname -r)"
}

unload_modules() {
    info "Unloading existing kernel module drivers"
    if grep -q -w iavf /proc/modules; then
        rmmod iavf || exit ${RETCODE_ERROR}
        info "Successfully unloaded iavf"
    fi
}

check_cached_version() {
    info "Checking cached version"
    if [[ ! -f "${CACHE_FILE}" ]]; then
        info "Cache file ${CACHE_FILE} not found."
        return ${RETCODE_ERROR}
    fi

    # Source the cache file and check if the cached driver matches
    # currently running kernel and driver versions.
    . "${CACHE_FILE}"
    if [[ "$(uname -r)" == "${CACHE_KERNEL_VERSION}" ]]; then
        if [[ "${IAVF_DRIVER_VERSION}" == \
                                         "${CACHE_IAVF_DRIVER_VERSION}" ]]; then
            info "Found existing driver installation for kernel version $(uname -r) \
          and driver version ${IAVF_DRIVER_VERSION}."
            return ${RETCODE_SUCCESS}
        fi
    fi
    if [[ -d "${ROOT_MOUNT_DIR}${IAVF_INSTALL_DIR_HOST}" ]]; then
        unload_modules
        info "Removing existing driver installation from ${ROOT_MOUNT_DIR}${IAVF_INSTALL_DIR_HOST}"
        rm -rf "${ROOT_MOUNT_DIR}${IAVF_INSTALL_DIR_HOST}"
    fi
    return ${RETCODE_ERROR}
}

update_cached_version() {
    cat >"${CACHE_FILE}"<<__EOF__
CACHE_KERNEL_VERSION=$(uname -r)
CACHE_IAVF_DRIVER_VERSION=${IAVF_DRIVER_VERSION}
__EOF__

    info "Updated cached version as:"
    cat "${CACHE_FILE}"
}

download_kernel_src_archive() {
    local -r download_url="$1"
    info "Kernel source archive download URL: ${download_url}"
    mkdir -p "${KERNEL_SRC_DIR}"
    pushd "${KERNEL_SRC_DIR}"
    local attempts=0
    until time curl -sfS "${download_url}" -o "${KERNEL_SRC_ARCHIVE}"; do
        attempts=$(( attempts + 1 ))
        if (( "${attempts}" >= "${RETRY_COUNT}" )); then
            error "Could not download kernel sources from ${download_url}, giving up."
            return ${RETCODE_ERROR}
        fi
        warn "Error fetching kernel source archive from ${download_url}, retrying"
        sleep 1
    done
    popd
}

download_kernel_src_from_git_repo() {
    # KERNEL_COMMIT_ID comes from /root/etc/os-release file.
    local -r download_url="${KERNEL_SRC_URL}/${KERNEL_SRC_ARCHIVE}"
    download_kernel_src_archive "${download_url}"
}

download_kernel_src() {
    if [[ -z "$(ls -A "${KERNEL_SRC_DIR}")" ]]; then
        info "Kernel sources not found locally, downloading"
        mkdir -p "${KERNEL_SRC_DIR}"
        if ! download_kernel_src_from_git_repo; then
            return ${RETCODE_ERROR}
        fi
    fi
    pushd "${KERNEL_SRC_DIR}"
    tar xf "${KERNEL_SRC_ARCHIVE}" --strip-components=1
    popd
}

configure_kernel_src() {
    info "Configuring kernel sources"
    pushd "${KERNEL_SRC_DIR}"
    if [[ -f "/proc/config.gz" ]]; then
        zcat /proc/config.gz > .config
    elif [[ -f "${ROOT_MOUNT_DIR}/boot/config-$(uname -r)" ]]; then
        cat "${ROOT_MOUNT_DIR}/boot/config-$(uname -r)" > .config
    else
        error "Kernel config not found."
        exit ${RETCODE_ERROR}
    fi
    make olddefconfig
    make modules_prepare

    # TODO: Figure out why the kernel magic version hack is required.
    # insmod fails without this, see dmesg for the specific error message.
    local -r kernel_version_uname="$(uname -r)"
    local -r kernel_version_src="$(awk '{ print $3 }' include/generated/utsrelease.h | tr -d '"')"
    if [[ "${kernel_version_uname}" != "${kernel_version_src}" ]]; then
        info "Modifying kernel version magic string in source files"
        sed -i "s|${kernel_version_src}|${kernel_version_uname}|g" "include/generated/utsrelease.h"
    fi
    popd
}

download_iavf_src() {
    info "Downloading IAVF source ... "
    mkdir -p "${IAVF_INSTALL_DIR_CONTAINER}"
    pushd "${IAVF_INSTALL_DIR_CONTAINER}"
    curl -L -sS "${IAVF_DRIVER_DOWNLOAD_URL}" -o "${IAVF_DRIVER_ARCHIVE}"
    popd
    pushd "${IAVF_INSTALL_DIR_CONTAINER}"
    tar xf "${IAVF_DRIVER_ARCHIVE}" --strip-components=1
    popd
}

is_not_used() {
    local -r ifname=$1
    local -r route_info=$(ip route show | grep "$ifname")
    if [[ -z "$route_info" ]]; then
        return 1
    else
        return 0
    fi
}

is_driver_match() {
    local -r ifname=$1
    local -r driver=$(grep DRIVER "/sys/class/net/$ifname/device/uevent" | cut -f2 -d "=")
    if [[ ! -z "$driver" ]]; then
        local -r nic_drivers=(i40e)
        for nic_driver in "${nic_drivers[@]}"; do
            if [[ "$driver" = "$nic_driver" ]]; then
                return 1
            fi
        done
    fi
    return 0
}

is_model_match() {
    local -r ifname=$1
    local -r pci_addr=$(grep PCI_SLOT_NAME "/sys/class/net/$ifname/device/uevent" | cut -f2 -d "=" | cut -f2,3 -d ":")
    if [[ ! -z "$pci_addr" ]]; then
        local -r nic_models=(XL710 X722)
        for nic_model in "${nic_models[@]}"; do
            model_match=$(lspci | grep "$pci_addr" | grep "$nic_model")
            if [[ ! -z "$model_match" ]]; then
                return 1
            fi
        done
    fi
    return 0
}

get_sriov_ifname() {
    local -r device_checkers=(is_not_used is_driver_match is_model_match)
    for net_device in /sys/class/net/*/ ; do
        if [[ -e "$net_device/device/sriov_numvfs" ]]; then
            local ifname;
            ifname=$(basename "$net_device")
            for device_checker in "${device_checkers[@]}"; do
                eval "$device_checker" "$ifname"
                if [[ "$?" = "0" ]]; then
                    ifname=""
                    break
                fi
            done
            if [[ ! -z "$ifname" ]]; then
                echo $ifname
                return
            fi
        fi
    done
    echo ""
}

configure_iavf_installation() {
    info "Installing i40evf blacklist file"
    mkdir -p "${ROOT_MOUNT_DIR}/etc/modprobe.d/"
    echo "blacklist i40evf" > "${ROOT_MOUNT_DIR}/etc/modprobe.d/iavf-blacklist-i40evf.conf"

    if grep -q -w i40evf /proc/modules; then
        rmmod i40evf || exit ${RETCODE_ERROR}
        info "Successfully unloaded i40evf"
    fi

    info "Installing kernel module iavf"
    insmod "${IAVF_INSTALL_DIR_CONTAINER}/src/iavf.ko"

    # TODO only the first interface?  i.e. ens801f0 and ens801f1
    local -r ifname=$(get_sriov_ifname)
    if [[ ! -z "$ifname" ]]; then
        info "Enabling VF on interface $ifname"
        echo "/sys/class/net/$ifname/device/sriov_numvfs"
        echo "8" > "/sys/class/net/$ifname/device/sriov_numvfs"
    fi
}

build_iavf_src() {
    info "Building IAVF source ... "
    pushd "${IAVF_INSTALL_DIR_CONTAINER}"
    make -C src
    popd
}

configure_cached_installation() {
    info "Configuring cached driver installation"
    if ! grep -q -w iavf /proc/modules; then
        configure_iavf_installation
    fi
}

main() {
    load_etc_os_release
    if check_cached_version; then
        configure_cached_installation
        info "Found cached version, NOT building the drivers."
    else
        info "Did not find cached version, building the drivers..."
        download_kernel_src
        download_iavf_src
        configure_kernel_src
        build_iavf_src
        configure_iavf_installation
        update_cached_version
        info "Finished installing the drivers."
    fi
}

main "$@"
