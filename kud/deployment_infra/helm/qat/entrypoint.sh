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
QAT_DRIVER_VERSION="${QAT_DRIVER_VERSION:-1.7.l.4.6.0-00025}"
QAT_DRIVER_DOWNLOAD_URL_DEFAULT="https://01.org/sites/default/files/downloads/qat${QAT_DRIVER_VERSION}.tar.gz"
QAT_DRIVER_DOWNLOAD_URL="${QAT_DRIVER_DOWNLOAD_URL:-$QAT_DRIVER_DOWNLOAD_URL_DEFAULT}"
QAT_INSTALL_DIR_HOST="${QAT_INSTALL_DIR_HOST:-/opt/qat}"
QAT_INSTALL_DIR_CONTAINER="${QAT_INSTALL_DIR_CONTAINER:-/usr/local/qat}"
QAT_DRIVER_ARCHIVE="$(basename "${QAT_DRIVER_DOWNLOAD_URL}")"
ROOT_MOUNT_DIR="${ROOT_MOUNT_DIR:-/root}"
CACHE_FILE="${QAT_INSTALL_DIR_CONTAINER}/.cache"
INSTALL_DIR_HOST="${INSTALL_DIR_HOST:-/usr/local}"
set +x

# Device information variables
INTEL_VENDORID="8086"
DH895_DEVICE_NUMBER="0435"
DH895_DEVICE_NUMBER_VM="0443"
C62X_DEVICE_NUMBER="37c8"
C62X_DEVICE_NUMBER_VM="37c9"
D15XX_DEVICE_NUMBER="6f54"
D15XX_DEVICE_NUMBER_VM="6f55"
C3XXX_DEVICE_NUMBER="19e2"
C3XXX_DEVICE_NUMBER_VM="19e3"

QAT_DH895XCC_NUM_VFS=32
QAT_DHC62X_NUM_VFS=16
QAT_DHD15XX_NUM_VFS=16
QAT_DHC3XXX_NUM_VFS=16

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
        error "File ${ROOT_OS_RELEASE} not found, /etc/os-release from host must be mounted"
        exit ${RETCODE_ERROR}
    fi
    . "${ROOT_OS_RELEASE}"
    info "Running on ${NAME} kernel version $(uname -r)"
}

# TODO
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
        info "Cache file ${CACHE_FILE} not found"
        return ${RETCODE_ERROR}
    fi

    # Source the cache file and check if the cached driver matches
    # currently running kernel and driver versions.
    . "${CACHE_FILE}"
    if [[ "$(uname -r)" == "${CACHE_KERNEL_VERSION}" ]]; then
        if [[ "${QAT_DRIVER_VERSION}" == "${CACHE_QAT_DRIVER_VERSION}" ]]; then
            info "Found existing driver installation for kernel version $(uname -r) and driver version ${QAT_DRIVER_VERSION}"
            return ${RETCODE_SUCCESS}
        fi
    fi
    # TODO
    # if [[ -d "${ROOT_MOUNT_DIR}${QAT_INSTALL_DIR_HOST}" ]]; then
    #     unload_modules
    #     info "Removing existing driver installation from ${ROOT_MOUNT_DIR}${QAT_INSTALL_DIR_HOST}"
    #     rm -rf "${ROOT_MOUNT_DIR}${QAT_INSTALL_DIR_HOST}"
    # fi
    # return ${RETCODE_ERROR}
}

update_cached_version() {
    cat >"${CACHE_FILE}"<<__EOF__
CACHE_KERNEL_VERSION=$(uname -r)
CACHE_QAT_DRIVER_VERSION=${QAT_DRIVER_VERSION}
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
    local -r kernel_version_src="$(awk '{ print $3 }' include/generated/utsrelease.h | tr -d '"')"
    if [[ "${kernel_version_uname}" != "${kernel_version_src}" ]]; then
        info "Modifying kernel version magic string in source files"
        sed -i "s|${kernel_version_src}|${kernel_version_uname}|g" "include/generated/utsrelease.h"
    fi
    popd
}

download_qat_src() {
    info "Downloading QAT source ... "
    mkdir -p "${QAT_INSTALL_DIR_CONTAINER}"
    pushd "${QAT_INSTALL_DIR_CONTAINER}"
    curl -L -sS "${QAT_DRIVER_DOWNLOAD_URL}" -o "${QAT_DRIVER_ARCHIVE}"
    popd
    pushd "${QAT_INSTALL_DIR_CONTAINER}"
    tar xf "${QAT_DRIVER_ARCHIVE}"
    popd
}

configure_qat_installation() {
    # TODO need to track side effects and be able to
    # 1. unload/uninstall 2. determine what is persistent and what is
    # not
    pushd "${QAT_INSTALL_DIR_CONTAINER}/build"

    info "Loading kernel module vfio-pci"
    modprobe -C "${ROOT_MOUNT_DIR}/etc/modprobe.d" -d "${ROOT_MOUNT_DIR}" vfio-pci # TODO runtime, idempotent

    info "Installing kernel modules"
    local -r modules="intel_qat.ko qat_c62x.ko qat_c62xvf.ko \
        qat_d15xx.ko qat_d15xxvf.ko qat_c3xxx.ko qat_c3xxxvf.ko \
        qat_dh895xcc.ko qat_dh895xccvf.ko"
    for module in $modules; do
        install -D -m 644 "${module}" "${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/updates/${module}"
    done

    info "Installing adf_ctl"
    install -D -m 750 adf_ctl "${ROOT_MOUNT_DIR}${INSTALL_DIR_HOST}/bin/adf_ctl"

    info "Installing firmware"
    local -r firmwares="qat_c3xxx.bin qat_c3xxx_mmp.bin qat_c62x.bin \
        qat_c62x_mmp.bin qat_mmp.bin qat_d15xx.bin qat_d15xx_mmp.bin \
        qat_895xcc.bin qat_895xcc_mmp.bin"
    mkdir -p "${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup"
    for fw in $firmwares; do
        if [[ -e ${ROOT_MOUNT_DIR}/lib/firmware/${fw} ]]; then
            mv "${ROOT_MOUNT_DIR}/lib/firmware/${fw}" "${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup/${fw}"
        fi
        if [[ -e $fw ]]; then
            install -D -m 750 "${fw}" "${ROOT_MOUNT_DIR}/lib/firmware/${fw}"
        fi
    done

    info "Installing service"
    mkdir -p "${ROOT_MOUNT_DIR}/etc/qat_conf_backup"
    mv -f "${ROOT_MOUNT_DIR}/etc/dh895xcc*.conf" "${ROOT_MOUNT_DIR}/etc/qat_conf_backup" 2>/dev/null || true
    mv -f "${ROOT_MOUNT_DIR}/etc/c6xx*.conf" "${ROOT_MOUNT_DIR}/etc/qat_conf_backup" 2>/dev/null || true
    mv -f "${ROOT_MOUNT_DIR}/etc/d15xx*.conf" "${ROOT_MOUNT_DIR}/etc/qat_conf_backup" 2>/dev/null || true
    mv -f "${ROOT_MOUNT_DIR}/etc/c3xxx*.conf" "${ROOT_MOUNT_DIR}/etc/qat_conf_backup" 2>/dev/null || true

    local -r dh895x_num_phys_devices=$(lspci -n | egrep -c "${INTEL_VENDORID}:${DH895_DEVICE_NUMBER}")
    for ((dev=0; dev<dh895x_num_phys_devices; dev++)); do
        install -D -m 640 dh895xcc_dev0.conf "${ROOT_MOUNT_DIR}/etc/dh895xcc_dev${dev}.conf"
        for ((vf_dev=0; vf_dev<QAT_DH895XCC_NUM_VFS; vf_dev++)); do
            local -r vf_dev_num=$((dev * QAT_DH895XCC_NUM_VFS + vf_dev))
            install -D -m 640 dh895xccvf_dev0.conf.vm "${ROOT_MOUNT_DIR}/etc/dh895xccvf_dev${vf_dev_num}.conf"
        done
    done

    local -r c62x_num_phys_devices=$(lspci -n | egrep -c "${INTEL_VENDORID}:${C62X_DEVICE_NUMBER}")
    for ((dev=0; dev<c62x_num_phys_devices; dev++)); do
        install -D -m 640 c6xx_dev$((dev%3)).conf "${ROOT_MOUNT_DIR}/etc/c6xx_dev${dev}.conf"
        for ((vf_dev=0; vf_dev<QAT_DHC62X_NUM_VFS; vf_dev++)); do
            local -r vf_dev_num=$((dev * QAT_DHC62X_NUM_VFS + vf_dev))
            install -D -m 640 c6xxvf_dev0.conf.vm "${ROOT_MOUNT_DIR}/etc/c6xxvf_dev${vf_dev_num}.conf"
        done
    done

    local -r d15xx_num_phys_devices=$(lspci -n | egrep -c "${INTEL_VENDORID}:${D15XX_DEVICE_NUMBER}")
    for ((dev=0; dev<d15xx_num_phys_devices; dev++)); do
        install -D -m 640 d15xx_dev$((dev%3)).conf "${ROOT_MOUNT_DIR}/etc/d15xx_dev${dev}.conf"
        for ((vf_dev=0; vf_dev<QAT_DHD15XX_NUM_VFS; vf_dev++)); do
            local -r vf_dev_num=$((dev * QAT_DHD15XX_NUM_VFS + vf_dev))
            install -D -m 640 d15xxvf_dev0.conf.vm "${ROOT_MOUNT_DIR}/etc/d15xxvf_dev${vf_dev_num}.conf"
        done
    done

    local -r c3xxx_num_phys_devices=$(lspci -n | egrep -c "${INTEL_VENDORID}:${C3XXX_DEVICE_NUMBER}")
    for ((dev=0; dev<c3xxx_num_phys_devices; dev++)); do
        install -D -m 640 c3xxx_dev0.conf "${ROOT_MOUNT_DIR}/etc/c3xxx_dev${dev}.conf"
        for ((vf_dev=0; vf_dev<QAT_DHC3XXX_NUM_VFS; vf_dev++)); do
            local -r vf_dev_num=$((dev * QAT_DHC3XXX_NUM_VFS + vf_dev))
            install -D -m 640 c3xxxvf_dev0.conf.vm "${ROOT_MOUNT_DIR}/etc/c3xxxvf_dev${vf_dev_num}.conf"
        done
    done

    install -D -m 750 qat_service "${ROOT_MOUNT_DIR}/etc/init.d/qat_service"
    install -D -m 750 qat_service_vfs "${ROOT_MOUNT_DIR}/etc/init.d/qat_service_vfs"

    local -r modprobe_blacklist_file="${ROOT_MOUNT_DIR}/etc/modprobe.d/blacklist-qat-vfs.conf"
    mkdir -p "$(dirname "${modprobe_blacklist_file}")"
    if [[ -e "${modprobe_blacklist_file}" ]]; then
        rm "${modprobe_blacklist_file}"
    fi
    if [[ $dh895x_num_phys_devices != 0 ]]; then
        echo "blacklist qat_dh895xccvf" >> "${modprobe_blacklist_file}"
    fi
    if [[ $c3xxx_num_phys_devices != 0 ]]; then
        echo "blacklist qat_c3xxxvf" >> "${modprobe_blacklist_file}"
    fi
    if [[ $c62x_num_phys_devices != 0 ]]; then
        echo "blacklist qat_c62xvf" >> "${modprobe_blacklist_file}"
    fi
    if [[ $d15xx_num_phys_devices != 0 ]]; then
        echo "blacklist qat_d15xxvf" >> "${modprobe_blacklist_file}"
    fi

    info "Installing libraries usdm and qat"
    install -D -m 755 libqat_s.so "${ROOT_MOUNT_DIR}${INSTALL_DIR_HOST}/lib/libqat_s.so"
    install -D -m 755 libusdm_drv_s.so "${ROOT_MOUNT_DIR}${INSTALL_DIR_HOST}/lib/libusdm_drv_s.so"
    echo "${INSTALL_DIR_HOST}/lib" > "${ROOT_MOUNT_DIR}/etc/ld.so.conf.d/qat.conf"
    ldconfig -r "${ROOT_MOUNT_DIR}" # TODO runtime, rewrites files

    info "Installing kernel modules usdm and qat"
    install -D -m 644 usdm_drv.ko "${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/kernel/drivers"
    install -D -m 644 qat_api.ko  "${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/kernel/drivers"

    info "Creating udev rules"
    mkdir -p "${ROOT_MOUNT_DIR}/etc/udev/rules.d"
    local -r qat_rules_file="${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules"
    if [[ ! -e "${qat_rules_file}" ]]; then
        { echo 'KERNEL=="qat_adf_ctl" MODE="0660" GROUP="qat"';
          echo 'KERNEL=="qat_dev_processes" MODE="0660" GROUP="qat"';
          echo 'KERNEL=="usdm_drv" MODE="0660" GROUP="qat"';
          echo 'KERNEL=="uio*" MODE="0660" GROUP="qat"';
          echo 'KERNEL=="hugepages" MODE="0660" GROUP="qat"'; } > "${qat_rules_file}"
    fi
    info "Updating kernel module dependencies"
    depmod -a -b "${ROOT_MOUNT_DIR}" -C "${ROOT_MOUNT_DIR}/etc/depmod.d" # TODO runtime, rewrites files
    if [[ $(lsmod | grep -c "usdm_drv") != "0" ]]; then
        rmmod usdm_drv # TODO runtime
    fi

    if [[ -e ${ROOT_MOUNT_DIR}/usr/sbin/update-rc.d ]]; then
        info "Updating init script links"
        chroot "${ROOT_MOUNT_DIR}" update-rc.d qat_service defaults # TODO runtime, rewrites symlinks and ?
    fi

    info "Starting service"
    chroot "${ROOT_MOUNT_DIR}" /etc/init.d/qat_service shutdown # TODO runtime
    sleep 3
    chroot "${ROOT_MOUNT_DIR}" /etc/init.d/qat_service start # TODO runtime
    chroot "${ROOT_MOUNT_DIR}" /etc/init.d/qat_service_vfs start # TODO runtime

    if [[ $(lspci -n | egrep -c "$INTEL_VENDORID:$C62X_DEVICE_NUMBER_VM") != 0 ]]; then
        info "Loading kernel module qat_c62xvf"
        modprobe -C "${ROOT_MOUNT_DIR}/etc/modprobe.d" -d "${ROOT_MOUNT_DIR}" qat_c62xvf # TODO runtime, idempotent
    fi
    if [[ $(lspci -n | egrep -c "$INTEL_VENDORID:$C3XXX_DEVICE_NUMBER_VM") != 0 ]]; then
        info "Loading kernel module qat_c3xxxvf"
        modprobe -C "${ROOT_MOUNT_DIR}/etc/modprobe.d" -d "${ROOT_MOUNT_DIR}" qat_c3xxxvf # TODO runtime, idempotent
    fi
    if [[ $(lspci -n | egrep -c "$INTEL_VENDORID:$D15XX_DEVICE_NUMBER_VM") != 0 ]]; then
        info "Loading kernel module qat_d15xxvf"
        modprobe -C "${ROOT_MOUNT_DIR}/etc/modprobe.d" -d "${ROOT_MOUNT_DIR}" qat_d15xxvf # TODO runtime, idempotent
    fi
    # TODO DH85_DEVICE_NUMBER_VM ?

    popd
}

build_qat_src() {
    info "Building QAT source ... "
    pushd "${QAT_INSTALL_DIR_CONTAINER}"
    KERNEL_SOURCE_ROOT="${KERNEL_SRC_DIR}" ./configure --enable-icp-sriov=host
    make
    popd
}

# TODO
configure_cached_installation() {
    info "Configuring cached driver installation"
    if ! grep -q -w iavf /proc/modules; then
        configure_qat_installation
    fi
}

check_qat_device() {
    local -r qat_device=$(for i in 0434 0435 37c8 6f54 19e2; do lspci -d 8086:$i -m; done \
                          | grep -i "Quick.*" | head -n 1 | cut -d " " -f 5)
    if [[ -z "$qat_device" ]]; then
        return ${RETCODE_ERROR}
    else
        return ${RETCODE_SUCCESS}
    fi
}

main() {
    # TODO add this back in
    # if ! check_qat_device; then
    #     info "Did not find QAT device, skipping configuration"
    #     exit ${RETCODE_SUCCESS}
    # fi
    # info "Found QAT device"

    load_etc_os_release
    if check_cached_version; then
        # TODO configure_cached_installation
        info "Found cached version, NOT building the drivers"
    else
        info "Did not find cached version, building the drivers ... "
        download_kernel_src
        download_qat_src
        configure_kernel_src
        build_qat_src
        configure_qat_installation
        update_cached_version
        info "Finished installing the drivers"
    fi
}

main "$@"
