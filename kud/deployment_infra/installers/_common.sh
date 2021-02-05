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

KERNEL_SRC_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x"
KERNEL_SRC_ARCHIVE="linux-$(uname -r | cut -d- -f1 | sed -e 's/\.0$//').tar.xz"
KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-/usr/src/linux}"
ROOT_MOUNT_DIR="${ROOT_MOUNT_DIR:-/root}"
ROOT_OS_RELEASE="${ROOT_OS_RELEASE:-$ROOT_MOUNT_DIR/etc/os-release}"

RETCODE_SUCCESS=0
RETCODE_ERROR=1

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
        error "File ${ROOT_OS_RELEASE} not found, /etc/os-release from host must be mounted"
        exit ${RETCODE_ERROR}
    fi
    . "${ROOT_OS_RELEASE}"
    info "Running on ${NAME} kernel version $(uname -r)"
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
            error "Could not download kernel sources from ${download_url}, giving up"
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
        error "Kernel config not found"
        exit ${RETCODE_ERROR}
    fi
    make olddefconfig
    make modules_prepare
    # modules_prepare does not build Modules.symver
    if [[ -f "/proc/config.gz" ]]; then
        zcat "${ROOT_MOUNT_DIR}/boot/symvers-$(uname -r).gz" > "${KERNEL_SRC_DIR}/Module.symvers"
    elif [[ -f "${ROOT_MOUNT_DIR}/usr/src/linux-headers-$(uname -r)/Module.symvers" ]]; then
        cp "${ROOT_MOUNT_DIR}/usr/src/linux-headers-$(uname -r)/Module.symvers" "${KERNEL_SRC_DIR}"
    else
        error "Module.symvers not found"
        exit ${RETCODE_ERROR}
    fi

    # TODO: Figure out why the kernel magic version hack is required.
    # insmod fails without this, see dmesg for the specific error message.
    local -r kernel_version_uname="$(uname -r)"
    local -r kernel_versionutsrelease="$(awk '{ print $3 }' include/generated/utsrelease.h | tr -d '"')"
    if [[ "${kernel_version_uname}" != "${kernel_versionutsrelease}" ]]; then
        info "Modifying kernel version magic string in utsrelease.h"
        sed -i "s|${kernel_versionutsrelease}|${kernel_version_uname}|g" "include/generated/utsrelease.h"
    fi

    # This is necessary for modules_install to use the correct host path
    local -r kernel_version_src="$(cat include/config/kernel.release)"
    if [[ "${kernel_version_uname}" != "${kernel_version_src}" ]]; then
        info "Modifying kernel version magic string in kernel.release"
        sed -i "s|${kernel_version_src}|${kernel_version_uname}|g" "include/config/kernel.release"
    fi
    popd

    # TODO Not sure if this is necessary
    #   not necessary for qat-driver-install
    # local -r modules_build_dir="$(readlink -f ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/build)"
    # if [[ -e "${modules_build_dir}" ]]; then
    #   error "Unexpected ${modules_build_dir} in container image"
    #   exit ${RETCODE_ERROR}
    # fi
    # ln -s "${KERNEL_SRC_DIR}" "${modules_build_dir}"
}
