#!/bin/bash
#================================================================================================
#
# MicroSLAM Image Package Script
# 镜像打包脚本，合并U-Boot+Kernel+RootFS，直接复制.ko文件到rootfs的/usr/lib/modules/目录
# 参考 amlogic-s9xxx-armbian-new/rebuild 的 replace_kernel 函数
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 路径配置
UBOOT_OUTPUT="${PROJECT_ROOT}/output/uboot"
KERNEL_OUTPUT="${PROJECT_ROOT}/output/kernel"
ROOTFS_OUTPUT="${PROJECT_ROOT}/output/rootfs"
IMAGES_OUTPUT="${PROJECT_ROOT}/output/images"
CONFIGS_DIR="${PROJECT_ROOT}/configs"
TMP_DIR="${PROJECT_ROOT}/.tmp"

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

# 默认参数
BOOT_MB="${BOOT_MB:-512}"
ROOT_MB="${ROOT_MB:-3000}"
SKIP_MB="${SKIP_MB:-16}"
ROOTFS_TYPE="${ROOTFS_TYPE:-ext4}"

echo -e "${STEPS} 开始打包MicroSLAM镜像..."

# 1. 检查必要的输出文件
echo -e "${INFO} 检查必要的输出文件..."

# 检查U-Boot输出
if [ ! -f "${UBOOT_OUTPUT}/u-boot.itb" ]; then
    echo -e "${ERROR} 未找到U-Boot输出: ${UBOOT_OUTPUT}/u-boot.itb"
    echo -e "${INFO} 请先运行 ./scripts/build-uboot.sh"
    exit 1
fi

# 检查Kernel输出
if [ ! -f "${KERNEL_OUTPUT}/boot/Image" ]; then
    echo -e "${ERROR} 未找到Kernel输出: ${KERNEL_OUTPUT}/boot/Image"
    echo -e "${INFO} 请先运行 ./scripts/build-kernel.sh"
    exit 1
fi

# 检查RootFS输出
ROOTFS_TAR=$(find "${ROOTFS_OUTPUT}" -name "*rootfs*.tar*" -type f | head -1)
if [ -z "${ROOTFS_TAR}" ]; then
    echo -e "${ERROR} 未找到RootFS输出: ${ROOTFS_OUTPUT}/*rootfs*.tar*"
    echo -e "${INFO} 请先运行 ./scripts/build-rootfs.sh"
    exit 1
fi

echo -e "${SUCCESS} 所有必要的输出文件已找到"

# 2. 创建临时目录
echo -e "${INFO} 创建临时目录..."
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"/{image,bootfs,rootfs}

# 3. 解压RootFS
echo -e "${INFO} 解压RootFS..."
ROOTFS_TMP="${TMP_DIR}/rootfs"
if [[ "${ROOTFS_TAR}" == *.tar.xz ]]; then
    tar -xJf "${ROOTFS_TAR}" -C "${ROOTFS_TMP}" --numeric-owner
elif [[ "${ROOTFS_TAR}" == *.tar.gz ]]; then
    tar -xzf "${ROOTFS_TAR}" -C "${ROOTFS_TMP}" --numeric-owner
else
    tar -xf "${ROOTFS_TAR}" -C "${ROOTFS_TMP}" --numeric-owner
fi

# 查找实际的rootfs目录（可能解压后有一个子目录）
ROOTFS_ACTUAL=$(find "${ROOTFS_TMP}" -maxdepth 1 -type d ! -path "${ROOTFS_TMP}" | head -1)
if [ -n "${ROOTFS_ACTUAL}" ] && [ -d "${ROOTFS_ACTUAL}" ]; then
    # 将子目录内容移动到根目录
    mv "${ROOTFS_ACTUAL}"/* "${ROOTFS_TMP}"/ 2>/dev/null || true
    rmdir "${ROOTFS_ACTUAL}" 2>/dev/null || true
fi

echo -e "${SUCCESS} RootFS解压完成"

# 4. 复制Kernel模块到RootFS（参考 amlogic-s9xxx-armbian-new/rebuild 的 replace_kernel 函数）
echo -e "${INFO} 复制Kernel模块到RootFS..."

# 获取内核版本名称
KERNEL_MODULES_DIR=$(find "${KERNEL_OUTPUT}/modules/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "${KERNEL_MODULES_DIR}" ]; then
    echo -e "${ERROR} 未找到内核模块目录: ${KERNEL_OUTPUT}/modules/lib/modules"
    exit 1
fi

KERNEL_NAME=$(basename "${KERNEL_MODULES_DIR}")
echo -e "${INFO} 内核版本名称: ${KERNEL_NAME}"

# 复制模块目录到rootfs（参考 rebuild 第877行）
ROOTFS_MODULES_DIR="${ROOTFS_TMP}/usr/lib/modules"
mkdir -p "${ROOTFS_MODULES_DIR}"

# 如果模块已打包成tar.gz，解压它
if [ -f "${KERNEL_OUTPUT}/modules-${KERNEL_NAME}.tar.gz" ]; then
    echo -e "${INFO} 从tar.gz解压模块..."
    tar -xzf "${KERNEL_OUTPUT}/modules-${KERNEL_NAME}.tar.gz" -C "${ROOTFS_MODULES_DIR}"
else
    # 直接复制模块目录
    echo -e "${INFO} 直接复制模块目录..."
    cp -rf "${KERNEL_MODULES_DIR}" "${ROOTFS_MODULES_DIR}/"
fi

# 创建符号链接（参考 rebuild 第878行）
if [ -d "${ROOTFS_MODULES_DIR}/${KERNEL_NAME}" ]; then
    cd "${ROOTFS_MODULES_DIR}/${KERNEL_NAME}"
    rm -f build source 2>/dev/null || true
    
    # 查找内核头文件目录
    HEADER_PATH="linux-headers-${KERNEL_NAME}"
    if [ -d "${ROOTFS_TMP}/usr/src/${HEADER_PATH}" ]; then
        ln -sf "/usr/src/${HEADER_PATH}" build
        ln -sf "/usr/src/${HEADER_PATH}" source
        echo -e "${SUCCESS} 创建符号链接: build -> /usr/src/${HEADER_PATH}"
    fi
    cd - > /dev/null
fi

echo -e "${SUCCESS} Kernel模块复制完成"

# 5. 准备boot分区内容
echo -e "${INFO} 准备boot分区内容..."
BOOTFS_TMP="${TMP_DIR}/bootfs"
mkdir -p "${BOOTFS_TMP}"/{dtb/rockchip,overlay-user}

# 复制内核镜像
cp -f "${KERNEL_OUTPUT}/boot/Image" "${BOOTFS_TMP}/Image"
cp -f "${KERNEL_OUTPUT}/boot/Image" "${BOOTFS_TMP}/vmlinuz-${KERNEL_NAME}"

# 复制设备树文件
if [ -d "${KERNEL_OUTPUT}/dtb/rockchip" ]; then
    cp -f "${KERNEL_OUTPUT}/dtb/rockchip"/*.dtb "${BOOTFS_TMP}/dtb/rockchip/" 2>/dev/null || true
    if [ -d "${KERNEL_OUTPUT}/dtb/rockchip/overlay" ]; then
        mkdir -p "${BOOTFS_TMP}/dtb/rockchip/overlay"
        cp -f "${KERNEL_OUTPUT}/dtb/rockchip/overlay"/*.dtbo "${BOOTFS_TMP}/dtb/rockchip/overlay/" 2>/dev/null || true
    fi
    # 创建符号链接（参考 rebuild 第867行）
    ln -sf dtb "${BOOTFS_TMP}/dtb-${KERNEL_NAME}"
fi

# 复制boot配置文件
if [ -f "${CONFIGS_DIR}/bootfs/armbianEnv.txt" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/armbianEnv.txt" "${BOOTFS_TMP}/"
fi

if [ -f "${CONFIGS_DIR}/bootfs/boot.scr" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/boot.scr" "${BOOTFS_TMP}/"
fi

if [ -f "${CONFIGS_DIR}/bootfs/boot.cmd" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/boot.cmd" "${BOOTFS_TMP}/"
fi

echo -e "${SUCCESS} Boot分区内容准备完成"

# 6. 创建镜像文件
echo -e "${INFO} 创建镜像文件..."
IMG_SIZE=$((SKIP_MB + BOOT_MB + ROOT_MB))
IMG_FILE="${IMAGES_OUTPUT}/MicroSLAM-${KERNEL_NAME}-$(date +%Y.%m.%d).img"
mkdir -p "${IMAGES_OUTPUT}"

# 计算实际需要的rootfs大小（MB）
ROOTFS_SIZE_MB=$(du -sm "${ROOTFS_TMP}" | cut -f1)
# 增加20%的余量
ROOTFS_SIZE_MB=$((ROOTFS_SIZE_MB + ROOTFS_SIZE_MB / 5))
if [ ${ROOTFS_SIZE_MB} -lt ${ROOT_MB} ]; then
    ROOTFS_SIZE_MB=${ROOT_MB}
fi

# 重新计算镜像大小
IMG_SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_SIZE_MB))

echo -e "${INFO} 镜像大小: ${IMG_SIZE}MB (skip:${SKIP_MB}MB + boot:${BOOT_MB}MB + rootfs:${ROOTFS_SIZE_MB}MB)"

# 创建空镜像文件
dd if=/dev/zero of="${IMG_FILE}" bs=1M count=${IMG_SIZE} status=progress
if [ $? -ne 0 ]; then
    echo -e "${ERROR} 创建镜像文件失败"
    exit 1
fi

# 7. 分区和格式化
echo -e "${INFO} 创建分区表..."
LOOP_DEV=$(losetup -f)
losetup -P "${LOOP_DEV}" "${IMG_FILE}"

# 创建GPT分区表
parted -s "${LOOP_DEV}" mklabel gpt
parted -s "${LOOP_DEV}" unit MiB mkpart primary ${SKIP_MB} $((SKIP_MB + BOOT_MB))
parted -s "${LOOP_DEV}" unit MiB mkpart primary $((SKIP_MB + BOOT_MB)) 100%

# 等待分区设备就绪
sleep 2
partprobe "${LOOP_DEV}" || true
sleep 1

# 格式化boot分区（ext4）
echo -e "${INFO} 格式化boot分区..."
mkfs.ext4 -F -L "BOOT" "${LOOP_DEV}p1"

# 格式化rootfs分区
echo -e "${INFO} 格式化rootfs分区..."
if [ "${ROOTFS_TYPE}" = "btrfs" ]; then
    mkfs.btrfs -f -L "ROOTFS" "${LOOP_DEV}p2"
else
    mkfs.ext4 -F -L "ROOTFS" "${LOOP_DEV}p2"
fi

# 8. 挂载分区并复制文件
echo -e "${INFO} 挂载分区..."

# 挂载boot分区
BOOT_MOUNT="${TMP_DIR}/boot_mount"
mkdir -p "${BOOT_MOUNT}"
mount "${LOOP_DEV}p1" "${BOOT_MOUNT}"

# 挂载rootfs分区
ROOT_MOUNT="${TMP_DIR}/root_mount"
mkdir -p "${ROOT_MOUNT}"
if [ "${ROOTFS_TYPE}" = "btrfs" ]; then
    mount -t btrfs -o compress=zstd:6 "${LOOP_DEV}p2" "${ROOT_MOUNT}"
else
    mount "${LOOP_DEV}p2" "${ROOT_MOUNT}"
fi

# 复制boot分区内容
echo -e "${INFO} 复制boot分区内容..."
cp -rf "${BOOTFS_TMP}"/* "${BOOT_MOUNT}/"

# 复制rootfs内容
echo -e "${INFO} 复制rootfs内容..."
cp -a "${ROOTFS_TMP}"/* "${ROOT_MOUNT}/"

# 9. 写入U-Boot到镜像开头
echo -e "${INFO} 写入U-Boot到镜像开头..."
if [ -f "${UBOOT_OUTPUT}/idbloader.img" ]; then
    dd if="${UBOOT_OUTPUT}/idbloader.img" of="${LOOP_DEV}" bs=512 seek=64 conv=notrunc status=progress
fi

if [ -f "${UBOOT_OUTPUT}/u-boot.itb" ]; then
    # 查找u-boot.itb的写入位置（通常是在idbloader之后）
    dd if="${UBOOT_OUTPUT}/u-boot.itb" of="${LOOP_DEV}" bs=512 seek=16384 conv=notrunc status=progress
fi

# 10. 卸载分区
echo -e "${INFO} 卸载分区..."
sync
umount "${BOOT_MOUNT}" || true
umount "${ROOT_MOUNT}" || true
losetup -d "${LOOP_DEV}" || true

# 11. 清理临时文件
echo -e "${INFO} 清理临时文件..."
rm -rf "${TMP_DIR}"

# 12. 检查输出
if [ -f "${IMG_FILE}" ]; then
    IMG_SIZE_ACTUAL=$(du -h "${IMG_FILE}" | cut -f1)
    echo -e "${SUCCESS} 镜像打包完成！"
    echo -e "${INFO} 镜像文件: ${IMG_FILE}"
    echo -e "${INFO} 镜像大小: ${IMG_SIZE_ACTUAL}"
    ls -lh "${IMG_FILE}"
else
    echo -e "${ERROR} 镜像文件未生成"
    exit 1
fi

echo -e "${SUCCESS} 镜像打包流程完成"
