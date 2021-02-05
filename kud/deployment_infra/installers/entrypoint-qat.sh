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

#set -x
source _common.sh

QAT_DRIVER_VERSION="${QAT_DRIVER_VERSION:-1.7.l.4.6.0-00025}"
QAT_DRIVER_DOWNLOAD_URL_DEFAULT="https://01.org/sites/default/files/downloads/qat${QAT_DRIVER_VERSION}.tar.gz"
QAT_DRIVER_DOWNLOAD_URL="${QAT_DRIVER_DOWNLOAD_URL:-$QAT_DRIVER_DOWNLOAD_URL_DEFAULT}"
QAT_INSTALL_DIR_HOST="${QAT_INSTALL_DIR_HOST:-/opt/qat}"
QAT_INSTALL_DIR_CONTAINER="${QAT_INSTALL_DIR_CONTAINER:-/usr/local/qat}"
QAT_DRIVER_ARCHIVE="$(basename "${QAT_DRIVER_DOWNLOAD_URL}")"
CACHE_FILE="${QAT_INSTALL_DIR_CONTAINER}/.cache"

BIN_LIST="qat_c3xxx.bin qat_c3xxx_mmp.bin qat_c62x.bin \
        qat_c62x_mmp.bin qat_mmp.bin qat_d15xx.bin qat_d15xx_mmp.bin \
        qat_895xcc.bin qat_895xcc_mmp.bin"

QAT_DH895XCC_NUM_VFS=32
QAT_DHC62X_NUM_VFS=16
QAT_DHD15XX_NUM_VFS=16
QAT_DHC3XXX_NUM_VFS=16

INTEL_VENDORID="8086"
DH895_DEVICE_NUMBER="0435"
DH895_DEVICE_NUMBER_VM="0443"
C62X_DEVICE_NUMBER="37c8"
C62X_DEVICE_NUMBER_VM="37c9"
D15XX_DEVICE_NUMBER="6f54"
D15XX_DEVICE_NUMBER_VM="6f55"
C3XXX_DEVICE_NUMBER="19e2"
C3XXX_DEVICE_NUMBER_VM="19e3"

numDh895xDevicesP=$(lspci -n | egrep -c "${INTEL_VENDORID}:${DH895_DEVICE_NUMBER}") || true
numDh895xDevicesV=$(lspci -n | egrep -c "${INTEL_VENDORID}:${DH895_DEVICE_NUMBER_VM}") || true
numC62xDevicesP=$(lspci -n | egrep -c "${INTEL_VENDORID}:${C62X_DEVICE_NUMBER}") || true
numC62xDevicesV=$(lspci -n | egrep -c "${INTEL_VENDORID}:${C62X_DEVICE_NUMBER_VM}") || true
numD15xxDevicesP=$(lspci -n | egrep -c "${INTEL_VENDORID}:${D15XX_DEVICE_NUMBER}") || true
numD15xxDevicesV=$(lspci -n | egrep -c "${INTEL_VENDORID}:${D15XX_DEVICE_NUMBER_VM}") || true
numC3xxxDevicesP=$(lspci -n | egrep -c "${INTEL_VENDORID}:${C3XXX_DEVICE_NUMBER}") || true
numC3xxxDevicesV=$(lspci -n | egrep -c "${INTEL_VENDORID}:${C3XXX_DEVICE_NUMBER_VM}") || true

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

build_qat_src() {
    info "Building QAT source ... "
    pushd "${QAT_INSTALL_DIR_CONTAINER}"
    KERNEL_SOURCE_ROOT="${KERNEL_SRC_DIR}" ./configure --enable-icp-sriov=host
    make
    popd
}

#
# qat_driver_install, adf_ctl_install, qat_service_install, and
# qat_service_uninstall are captured from the Makefile targets.  They
# cannot be run in a container as-is due to absolute paths, so they
# are recreated here.
#

qat_driver_install() {
    pushd "${QAT_INSTALL_DIR_CONTAINER}"
    INSTALL_MOD_PATH="${ROOT_MOUNT_DIR}" make qat-driver-install
    popd
}

adf_ctl_install() {
    pushd "${QAT_INSTALL_DIR_CONTAINER}"
    install -D -m 750 quickassist/utilities/adf_ctl/adf_ctl ${ROOT_MOUNT_DIR}/usr/local/bin/adf_ctl
    popd
}

qat_service_install() {
    pushd "${QAT_INSTALL_DIR_CONTAINER}/build"

    if [[ ! -d ${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup ]]; then
        mkdir ${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup
    fi
    for bin in ${BIN_LIST}; do
        if [[ -e ${ROOT_MOUNT_DIR}/lib/firmware/${bin} ]]; then
            mv ${ROOT_MOUNT_DIR}/lib/firmware/${bin} ${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup/${bin}
        fi
        if [[ -e ${bin} ]]; then
            install -D -m 750 ${bin} ${ROOT_MOUNT_DIR}/lib/firmware/${bin}
        fi
    done

    if [[ ! -d ${ROOT_MOUNT_DIR}/etc/qat_conf_backup ]]; then
        ${MKDIR} ${ROOT_MOUNT_DIR}/etc/qat_conf_backup
    fi
    mv ${ROOT_MOUNT_DIR}/etc/dh895xcc*.conf ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/ 2>/dev/null || true
    mv ${ROOT_MOUNT_DIR}/etc/c6xx*.conf ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/ 2>/dev/null || true
    mv ${ROOT_MOUNT_DIR}/etc/d15xx*.conf ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/ 2>/dev/null || true
    mv ${ROOT_MOUNT_DIR}/etc/c3xxx*.conf ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/ 2>/dev/null || true
    for ((dev=0; dev<${numDh895xDevicesP}; dev++)); do
        install -D -m 640 dh895xcc_dev0.conf ${ROOT_MOUNT_DIR}/etc/dh895xcc_dev${dev}.conf
    done
    for ((dev=0; dev<${numC62xDevicesP}; dev++)); do
        install -D -m 640 c6xx_dev$((dev%3)).conf ${ROOT_MOUNT_DIR}/etc/c6xx_dev${dev}.conf
    done
    for ((dev=0; dev<${numD15xxDevicesP}; dev++)); do
        install -D -m 640 d15xx_dev$((dev%3)).conf ${ROOT_MOUNT_DIR}/etc/d15xx_dev${dev}.conf
    done
    for ((dev=0; dev<${numC3xxxDevicesP}; dev++)); do
        install -D -m 640 c3xxx_dev0.conf ${ROOT_MOUNT_DIR}/etc/c3xxx_dev${dev}.conf
    done
    for ((dev=0; dev<${numDh895xDevicesP}; dev++)); do
        for ((vf_dev = 0; vf_dev<${QAT_DH895XCC_NUM_VFS}; vf_dev++)); do
            vf_dev_num=$((dev * QAT_DH895XCC_NUM_VFS + vf_dev))
            install -D -m 640 dh895xccvf_dev0.conf.vm ${ROOT_MOUNT_DIR}/etc/dh895xccvf_dev${vf_dev}_num.conf
        done
    done
    for ((dev=0; dev<${numC62xDevicesP}; dev++)); do
        for ((vf_dev = 0; vf_dev<${QAT_DHC62X_NUM_VFS}; vf_dev++)); do
            vf_dev_num=$((dev * QAT_DHC62X_NUM_VFS + vf_dev))
            install -D -m 640 c6xxvf_dev0.conf.vm ${ROOT_MOUNT_DIR}/etc/c6xxvf_dev${vf_dev}_num.conf
        done
    done
    for ((dev=0; dev<${numD15xxDevicesP}; dev++)); do
        for ((vf_dev = 0; vf_dev<${QAT_DHD15XX_NUM_VFS}; vf_dev++)); do
            vf_dev_num=$((dev * QAT_DHD15XX_NUM_VFS + vf_dev))
            install -D -m 640 d15xxvf_dev0.conf.vm ${ROOT_MOUNT_DIR}/etc/d15xxvf_dev${vf_dev}_num.conf
        done
    done
    for ((dev=0; dev<${numC3xxxDevicesP}; dev++)); do
        for ((vf_dev = 0; vf_dev<${QAT_DHC3XXX_NUM_VFS}; vf_dev++)); do
            vf_dev_num=$((dev * QAT_DHC3XXX_NUM_VFS + vf_dev))
            install -D -m 640 c3xxxvf_dev0.conf.vm ${ROOT_MOUNT_DIR}/etc/c3xxxvf_dev${vf_dev}_num.conf
        done
    done
    info "Creating startup and kill scripts"
    install -D -m 750 qat_service ${ROOT_MOUNT_DIR}/etc/init.d/qat_service
    install -D -m 750 qat_service_vfs ${ROOT_MOUNT_DIR}/etc/init.d/qat_service_vfs
    echo "# Comment or remove next line to disable sriov" > ${ROOT_MOUNT_DIR}/etc/default/qat
    echo "SRIOV_ENABLE=1" >> ${ROOT_MOUNT_DIR}/etc/default/qat
    echo "#LEGACY_LOADED=1" >> ${ROOT_MOUNT_DIR}/etc/default/qat
    rm -f ${ROOT_MOUNT_DIR}/etc/modprobe.d/blacklist-qat-vfs.conf
    if [[ ${numDh895xDevicesP} != 0 ]]; then
        echo "blacklist qat_dh895xccvf" >> ${ROOT_MOUNT_DIR}/etc/modprobe.d/blacklist-qat-vfs.conf
    fi
    if [[ ${numC3xxxDevicesP} != 0 ]]; then
        echo "blacklist qat_c3xxxvf" >> ${ROOT_MOUNT_DIR}/etc/modprobe.d/blacklist-qat-vfs.conf
    fi
    if [[ ${numC62xDevicesP} != 0 ]]; then
        echo "blacklist qat_c62xvf" >> ${ROOT_MOUNT_DIR}/etc/modprobe.d/blacklist-qat-vfs.conf
    fi
    if [[ ${numD15xxDevicesP} != 0 ]]; then
        echo "blacklist qat_d15xxvf" >> ${ROOT_MOUNT_DIR}/etc/modprobe.d/blacklist-qat-vfs.conf
    fi
    echo "#ENABLE_KAPI=1" >> ${ROOT_MOUNT_DIR}/etc/default/qat
    info "Copying libqat_s.so to ${ROOT_MOUNT_DIR}/usr/local/lib"
    install -D -m 755 libqat_s.so ${ROOT_MOUNT_DIR}/usr/local/lib/libqat_s.so
    info "Copying libusdm_drv_s.so to ${ROOT_MOUNT_DIR}/usr/local/lib"
    install -D -m 755 libusdm_drv_s.so ${ROOT_MOUNT_DIR}/usr/local/lib/libusdm_drv_s.so
    echo /usr/local/lib > ${ROOT_MOUNT_DIR}/etc/ld.so.conf.d/qat.conf
    ldconfig -r "${ROOT_MOUNT_DIR}"
    info "Copying usdm module to system drivers"
    install usdm_drv.ko ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/kernel/drivers
    install qat_api.ko ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/kernel/drivers
    info "Creating udev rules"
    if [[ ! -e ${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules ]]; then
        echo 'KERNEL=="qat_adf_ctl" MODE="0660" GROUP="qat"' > ${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules
        echo 'KERNEL=="qat_dev_processes" MODE="0660" GROUP="qat"' >> ${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules
        echo 'KERNEL=="usdm_drv" MODE="0660" GROUP="qat"' >> ${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules
        echo 'KERNEL=="uio*" MODE="0660" GROUP="qat"' >> ${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules
        echo 'KERNEL=="hugepages" MODE="0660" GROUP="qat"' >> ${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules
    fi
    info "Creating module.dep file for QAT released kernel object"
    info "This will take a few moments"
    depmod -a -b "${ROOT_MOUNT_DIR}" -C "${ROOT_MOUNT_DIR}/etc/depmod.d"

    #
    # The portions of qat-driver-install that deal with rc.d are
    # removed: they are intended to be handled by the deployed
    # DaemonSet.  The rest is contained in qat_service_start.
    #
    # The checks for loaded modules are moved to check_started.
    #
    popd
}

qat_service_start() {
    if [[ $(lsmod | grep "usdm_drv" | wc -l) != "0" ]]; then
        rmmod usdm_drv
    fi

    info "Starting QAT service"
    chroot "${ROOT_MOUNT_DIR}" /etc/init.d/qat_service shutdown || true
    sleep 3
    chroot "${ROOT_MOUNT_DIR}" /etc/init.d/qat_service start
}

qat_service_shutdown() {
    info "Stopping QAT service"
    if [[ $(lsmod | grep "qat" | wc -l) != "0" ||
          -e ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/updates/drivers/crypto/qat/qat_common/intel_qat.ko ]]; then

        if [[ $(lsmod | grep "usdm_drv" | wc -l) != "0" ]]; then
            rmmod usdm_drv
        fi

        if [ -e ${ROOT_MOUNT_DIR}/etc/init.d/qat_service_upstream ]; then
            until chroot "${ROOT_MOUNT_DIR}" /etc/init.d/qat_service_upstream shutdown; do
                sleep 1
            done
        elif [[ -e ${ROOT_MOUNT_DIR}/etc/init.d/qat_service ]]; then
            until chroot "${ROOT_MOUNT_DIR}" /etc/init.d/qat_service shutdown; do
                sleep 1
            done
        fi
    fi
}

qat_service_uninstall() {
    if [[ $(lsmod | grep "qat" | wc -l) != "0" ||
          -e ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/updates/drivers/crypto/qat/qat_common/intel_qat.ko ]]; then
        info "Removing the QAT firmware"
        for bin in ${BIN_LIST}; do
            if [[ -e ${ROOT_MOUNT_DIR}/lib/firmware/${bin} ]]; then
                rm ${ROOT_MOUNT_DIR}/lib/firmware/${bin}
            fi
            if [[ -e ${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup/${bin} ]]; then
                mv ${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup/${bin} ${ROOT_MOUNT_DIR}/lib/firmware/${bin}
            fi
        done

        if [[ -d ${ROOT_MOUNT_DIR}/lib/firmware/qat_fw ]]; then
            rm ${ROOT_MOUNT_DIR}/lib/firmware/qat_fw_backup
        fi

        if [ -e ${ROOT_MOUNT_DIR}/etc/init.d/qat_service_upstream ]; then
            rm ${ROOT_MOUNT_DIR}/etc/init.d/qat_service_upstream
            rm ${ROOT_MOUNT_DIR}/usr/local/bin/adf_ctl
        elif [[ -e ${ROOT_MOUNT_DIR}/etc/init.d/qat_service ]]; then
            rm ${ROOT_MOUNT_DIR}/etc/init.d/qat_service
            rm ${ROOT_MOUNT_DIR}/usr/local/bin/adf_ctl
        fi
        rm -f ${ROOT_MOUNT_DIR}/etc/init.d/qat_service_vfs
        rm -f ${ROOT_MOUNT_DIR}/etc/modprobe.d/blacklist-qat-vfs.conf

        rm -f ${ROOT_MOUNT_DIR}/usr/local/lib/libqat_s.so
        rm -f ${ROOT_MOUNT_DIR}/usr/local/lib/libusdm_drv_s.so
        rm -rf ${ROOT_MOUNT_DIR}/etc/ld.so.conf.d/qat.conf
        ldconfig -r "${ROOT_MOUNT_DIR}"

        info "Removing config files"
        rm -f ${ROOT_MOUNT_DIR}/etc/dh895xcc*.conf
        rm -f ${ROOT_MOUNT_DIR}/etc/c6xx*.conf
        rm -f ${ROOT_MOUNT_DIR}/etc/d15xx*.conf
        rm -f ${ROOT_MOUNT_DIR}/etc/c3xxx*.conf
        rm -f ${ROOT_MOUNT_DIR}/etc/udev/rules.d/00-qat.rules

        mv -f ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/dh895xcc*.conf ${ROOT_MOUNT_DIR}/etc/ 2>/dev/null || true
        mv -f ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/c6xx*.conf ${ROOT_MOUNT_DIR}/etc/ 2>/dev/null || true
        mv -f ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/d15xx*.conf ${ROOT_MOUNT_DIR}/etc/ 2>/dev/null || true
        mv -f ${ROOT_MOUNT_DIR}/etc/qat_conf_backup/c3xxx*.conf ${ROOT_MOUNT_DIR}/etc/ 2>/dev/null || true

        info "Removing drivers modules"
        rm -rf ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/updates/drivers/crypto/qat
        rm -f ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/kernel/drivers/usdm_drv.ko
        rm -f ${ROOT_MOUNT_DIR}/lib/modules/$(uname -r)/kernel/drivers/qat_api.ko
        info "Creating module.dep file for QAT released kernel object"
        depmod -a -b "${ROOT_MOUNT_DIR}" -C "${ROOT_MOUNT_DIR}/etc/depmod.d"

        if [[ $(lsmod |egrep -c "usdm_drv|intel_qat") != "0" ]]; then
            if [ $(modinfo intel_qat |egrep -c "updates") == "0" ]]; then
                info "In-tree driver loaded"
                info "Acceleration uninstall complete"
            else
                error "Some modules not removed properly"
                error "Acceleration uninstall failed"
            fi
        else
            info "Acceleration uninstall complete"
        fi
        if [ ${numDh895xDevicesP} != 0 ]; then
            lsmod | grep qat_dh895xcc >/dev/null 2>&1 || modprobe -b -q qat_dh895xcc >/dev/null 2>&1 || true
        fi
        if [ ${numC62xDevicesP} != 0 ]; then
            lsmod | grep qat_c62x >/dev/null 2>&1 || modprobe -b -q qat_c62x >/dev/null 2>&1 || true
        fi
        if [ ${numD15xxDevicesP} != 0 ]; then
            lsmod | grep qat_d15xx >/dev/null 2>&1 || modprobe -b -q qat_d15xx >/dev/null 2>&1 || true
        fi
        if [ ${numC3xxxDevicesP} != 0 ]; then
            lsmod | grep qat_c3xxx >/dev/null 2>&1 || modprobe -b -q qat_c3xxx >/dev/null 2>&1 || true
        fi
        if [ ${numDh895xDevicesV} != 0 ]; then
            lsmod | grep qat_dh895xccvf >/dev/null 2>&1 || modprobe -b -q qat_dh895xccvf >/dev/null 2>&1 || true
        fi
        if [ ${numC62xDevicesV} != 0 ]; then
            lsmod | grep qat_c62xvf >/dev/null 2>&1 || modprobe -b -q qat_c62xvf >/dev/null 2>&1 || true
        fi
        if [ ${numD15xxDevicesV} != 0 ]; then
            lsmod | grep qat_d15xxvf >/dev/null 2>&1 || modprobe -b -q qat_d15xxvf >/dev/null 2>&1 || true
        fi
        if [ ${numC3xxxDevicesV} != 0 ]; then
            lsmod | grep qat_c3xxxvf >/dev/null 2>&1 || modprobe -b -q qat_c3xxxvf >/dev/null 2>&1 || true
        fi
    else
        info "Acceleration package not installed"
    fi
}

install_qat() {
    download_kernel_src
    download_qat_src
    configure_kernel_src
    build_qat_src
    qat_driver_install
    adf_ctl_install
    qat_service_install
}

uninstall_qat() {
    qat_service_shutdown
    qat_service_uninstall
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
    return ${RETCODE_ERROR}
}

update_cached_version() {
    cat >"${CACHE_FILE}"<<__EOF__
CACHE_KERNEL_VERSION=$(uname -r)
CACHE_QAT_DRIVER_VERSION=${QAT_DRIVER_VERSION}
__EOF__

    info "Updated cached version as:"
    cat "${CACHE_FILE}"
}

upgrade_driver() {
    uninstall_qat
    install_qat
}

uninstall_driver() {
    uninstall_qat
    rm "${CACHE_FILE}"
}

check_driver_started() {
    if [[ $(lsmod |egrep -c "usdm_drv") == "0" ]]; then
        error "usdm_drv module not installed"
        return ${RETCODE_ERROR}
    fi
    if [[ ${numDh895xDevicesP} != 0 ]]; then
        if [[ $(lsmod |egrep -c "qat_dh895xcc") == "0" ]]; then
            error "qat_dh895xcc module not installed"
            return ${RETCODE_ERROR}
        fi
    fi
    if [[ ${numC62xDevicesP} != 0 ]]; then
        if [[ $(lsmod |egrep -c "qat_c62x") == "0" ]]; then
            error "qat_c62x module not installed"
            return ${RETCODE_ERROR}
        fi
    fi
    if [[ ${numD15xxDevicesP} != 0 ]]; then
        if [[ $(lsmod |egrep -c "qat_d15xx") == "0" ]]; then
            error "qat_d15xx module not installed"
            return ${RETCODE_ERROR}
        fi
    fi
    if [[ ${numC3xxxDevicesP} != 0 ]]; then
        if [[ $(lsmod |egrep -c "qat_c3xxx") == "0" ]]; then
            error "qat_c3xxx module not installed"
            return ${RETCODE_ERROR}
        fi
    fi
    if [[ $(${ROOT_MOUNT_DIR}/usr/local/bin/adf_ctl status | grep -c "state: down") != "0" ]]; then
        error "QAT driver not activated"
        return ${RETCODE_ERROR}
    fi
    return ${RETCODE_SUCCESS}
}

start_driver() {
    qat_service_start
    check_driver_started
}

main "$@"
