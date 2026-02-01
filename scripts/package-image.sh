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

# 清理函数：卸载分区和删除 loop 设备
cleanup_loop_device() {
    if [ -n "${LOOP_DEV}" ] && [ -b "${LOOP_DEV}" ] 2>/dev/null; then
        echo -e "${INFO} 清理 loop 设备: ${LOOP_DEV}"
        # 尝试卸载所有挂载点
        if [ -n "${BOOT_MOUNT}" ] && mountpoint -q "${BOOT_MOUNT}" 2>/dev/null; then
            umount "${BOOT_MOUNT}" 2>/dev/null || true
        fi
        if [ -n "${ROOT_MOUNT}" ] && mountpoint -q "${ROOT_MOUNT}" 2>/dev/null; then
            umount "${ROOT_MOUNT}" 2>/dev/null || true
        fi
        # 删除 loop 设备
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi
}

# 设置 trap：在脚本退出时清理
trap cleanup_loop_device EXIT INT TERM

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
    # 将子目录内容移动到根目录（使用 shopt dotglob 确保包含隐藏文件和空目录）
    shopt -s dotglob
    mv "${ROOTFS_ACTUAL}"/* "${ROOTFS_TMP}"/ 2>/dev/null || true
    shopt -u dotglob
    rmdir "${ROOTFS_ACTUAL}" 2>/dev/null || true
fi

# 确保关键目录存在（/dev 等空目录可能在解压时丢失）
echo -e "${INFO} 确保关键系统目录存在..."
for dir in dev proc sys run tmp mnt media; do
    mkdir -p "${ROOTFS_TMP}/${dir}"
done
chmod 1777 "${ROOTFS_TMP}/tmp"

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
mkdir -p "${BOOTFS_TMP}"/{dtb/rockchip,overlay-user,extlinux}

# 5.1. 复制内核文件（参考 rebuild 第857行）
echo -e "${INFO} 复制内核文件..."
# 复制内核镜像
if [ -f "${KERNEL_OUTPUT}/boot/Image" ]; then
    cp -f "${KERNEL_OUTPUT}/boot/Image" "${BOOTFS_TMP}/vmlinuz-${KERNEL_NAME}"
    # 创建符号链接（参考 rebuild 第860行，rockchip 平台使用符号链接）
    ln -sf "vmlinuz-${KERNEL_NAME}" "${BOOTFS_TMP}/Image"
    echo -e "${SUCCESS} 内核镜像已复制: vmlinuz-${KERNEL_NAME} -> Image"
else
    echo -e "${ERROR} 未找到内核镜像: ${KERNEL_OUTPUT}/boot/Image"
    exit 1
fi

# 复制 System.map
if [ -f "${KERNEL_OUTPUT}/boot/System.map-${KERNEL_NAME}" ]; then
    cp -f "${KERNEL_OUTPUT}/boot/System.map-${KERNEL_NAME}" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} System.map 已复制"
fi

# 复制内核配置文件
if [ -f "${KERNEL_OUTPUT}/boot/config-${KERNEL_NAME}" ]; then
    cp -f "${KERNEL_OUTPUT}/boot/config-${KERNEL_NAME}" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} 内核配置文件已复制"
fi

# 复制 initrd.img
if [ -f "${KERNEL_OUTPUT}/boot/initrd.img-${KERNEL_NAME}" ]; then
    cp -f "${KERNEL_OUTPUT}/boot/initrd.img-${KERNEL_NAME}" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} initrd.img 已复制"
fi

# 复制 uInitrd 并创建符号链接（参考 rebuild 第860行）
if [ -f "${KERNEL_OUTPUT}/boot/uInitrd-${KERNEL_NAME}" ]; then
    cp -f "${KERNEL_OUTPUT}/boot/uInitrd-${KERNEL_NAME}" "${BOOTFS_TMP}/"
    # 创建符号链接（参考 rebuild 第860行）
    ln -sf "uInitrd-${KERNEL_NAME}" "${BOOTFS_TMP}/uInitrd"
    echo -e "${SUCCESS} uInitrd 已复制并创建符号链接"
elif [ -f "${KERNEL_OUTPUT}/boot/uInitrd" ]; then
    cp -f "${KERNEL_OUTPUT}/boot/uInitrd" "${BOOTFS_TMP}/uInitrd-${KERNEL_NAME}"
    ln -sf "uInitrd-${KERNEL_NAME}" "${BOOTFS_TMP}/uInitrd"
    echo -e "${SUCCESS} uInitrd 已复制并创建符号链接"
else
    echo -e "${WARNING} 未找到 uInitrd 文件，boot.cmd 已支持可选加载"
fi

# 5.2. 复制设备树文件
echo -e "${INFO} 复制设备树文件..."
if [ -d "${KERNEL_OUTPUT}/dtb/rockchip" ]; then
    cp -f "${KERNEL_OUTPUT}/dtb/rockchip"/*.dtb "${BOOTFS_TMP}/dtb/rockchip/" 2>/dev/null || true
    if [ -d "${KERNEL_OUTPUT}/dtb/rockchip/overlay" ]; then
        mkdir -p "${BOOTFS_TMP}/dtb/rockchip/overlay"
        cp -f "${KERNEL_OUTPUT}/dtb/rockchip/overlay"/*.dtbo "${BOOTFS_TMP}/dtb/rockchip/overlay/" 2>/dev/null || true
    fi
    # 创建符号链接（参考 rebuild 第867行）
    ln -sf dtb "${BOOTFS_TMP}/dtb-${KERNEL_NAME}"
    echo -e "${SUCCESS} 设备树文件已复制"
else
    echo -e "${WARNING} 未找到设备树文件目录"
fi

# 5.3. 复制 boot 配置文件
echo -e "${INFO} 复制 boot 配置文件..."
if [ -f "${CONFIGS_DIR}/bootfs/armbianEnv.txt" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/armbianEnv.txt" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} armbianEnv.txt 已复制"
fi

# 编译 boot.cmd 为 boot.scr（如果 boot.cmd 存在且比 boot.scr 新，或 boot.scr 不存在）
if [ -f "${CONFIGS_DIR}/bootfs/boot.cmd" ]; then
    if [ ! -f "${CONFIGS_DIR}/bootfs/boot.scr" ] || [ "${CONFIGS_DIR}/bootfs/boot.cmd" -nt "${CONFIGS_DIR}/bootfs/boot.scr" ]; then
        if command -v mkimage >/dev/null 2>&1; then
            echo -e "${INFO} 编译 boot.cmd 为 boot.scr..."
            mkimage -C none -A arm -T script -n 'flatmax load script' -d "${CONFIGS_DIR}/bootfs/boot.cmd" "${CONFIGS_DIR}/bootfs/boot.scr" || {
                echo -e "${WARNING} 编译 boot.scr 失败，将使用现有的 boot.scr（如果存在）"
            }
        else
            echo -e "${WARNING} mkimage 未找到，无法编译 boot.scr，将使用现有的 boot.scr（如果存在）"
        fi
    fi
    # 复制 boot.cmd（用于调试）
    cp -f "${CONFIGS_DIR}/bootfs/boot.cmd" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} boot.cmd 已复制"
fi

# 复制 boot.scr（如果存在）
if [ -f "${CONFIGS_DIR}/bootfs/boot.scr" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/boot.scr" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} boot.scr 已复制"
fi

# 5.4. 复制 platform 文件（参考 rebuild 第822行）
echo -e "${INFO} 复制 platform 文件..."
# 复制 boot.bmp（如果存在）
if [ -f "${CONFIGS_DIR}/bootfs/boot.bmp" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/boot.bmp" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} boot.bmp 已复制"
fi

# 复制 boot-desktop.png（如果存在）
if [ -f "${CONFIGS_DIR}/bootfs/boot-desktop.png" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/boot-desktop.png" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} boot-desktop.png 已复制"
fi

# 复制 armbian_first_run.txt.template（如果存在）
if [ -f "${CONFIGS_DIR}/bootfs/armbian_first_run.txt.template" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/armbian_first_run.txt.template" "${BOOTFS_TMP}/"
    echo -e "${SUCCESS} armbian_first_run.txt.template 已复制"
fi

# 复制 extlinux/extlinux.conf.bak（如果存在）
if [ -f "${CONFIGS_DIR}/bootfs/extlinux/extlinux.conf.bak" ]; then
    cp -f "${CONFIGS_DIR}/bootfs/extlinux/extlinux.conf.bak" "${BOOTFS_TMP}/extlinux/"
    echo -e "${SUCCESS} extlinux.conf.bak 已复制"
fi

# 5.5. 复制 mkimage 工具（如果存在，用于调试）
if command -v mkimage >/dev/null 2>&1; then
    mkimage_path=$(which mkimage)
    if [ -f "${mkimage_path}" ]; then
        cp -f "${mkimage_path}" "${BOOTFS_TMP}/mkimage" 2>/dev/null || true
        echo -e "${INFO} mkimage 工具已复制（可选）"
    fi
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

# 确保使用绝对路径（参考 Armbian，直接使用变量，但确保是绝对路径）
if [[ "${IMG_FILE}" != /* ]]; then
    IMG_FILE="$(cd "$(dirname "${IMG_FILE}")" && pwd)/$(basename "${IMG_FILE}")"
fi

# 检查文件是否存在
if [ ! -f "${IMG_FILE}" ]; then
    echo -e "${ERROR} 镜像文件不存在: ${IMG_FILE}"
    exit 1
fi

# 验证文件可读
if [ ! -r "${IMG_FILE}" ]; then
    echo -e "${ERROR} 镜像文件不可读: ${IMG_FILE}"
    exit 1
fi

# wait_for_disk_sync 函数（参考 Armbian）
wait_for_disk_sync() {
    local timeout_seconds=30
    local sync_worked=0
    local sync_timeout_count=0
    local total_wait=0

    while [ ${sync_worked} -eq 0 ]; do
        local sync_timeout=0
        if bash -c "timeout --signal=9 ${timeout_seconds} sync &> /dev/null" &> /dev/null; then
            sync_worked=1
        else
            sync_timeout=1
        fi
        
        if [ ${sync_timeout} -eq 1 ]; then
            total_wait=$((total_wait + timeout_seconds))
            sync_timeout_count=$((sync_timeout_count + 1))
            echo -e "${WARNING} 等待磁盘同步 $* (已等待 ${total_wait} 秒)..."
        fi
    done
}

# 同步文件系统，确保文件完全写入（参考 Armbian）
wait_for_disk_sync "after creating image file"

# 7. 分区和格式化
echo -e "${INFO} 创建分区表..."
# 参考 Armbian: 先在镜像文件上创建分区表，然后使用 losetup --partscan 创建 loop 设备
# 使用 sfdisk 直接在镜像文件上创建分区表（更可靠）
{
    echo "label: gpt"
    echo "1 : start=${SKIP_MB}MiB, size=${BOOT_MB}MiB, type=BC13C2FF-59E6-4262-A352-B275FD6F7172, name=\"bootfs\""
    echo "2 : start=$((SKIP_MB + BOOT_MB))MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"rootfs\""
} | sfdisk "${IMG_FILE}" || {
    echo -e "${ERROR} 创建分区表失败"
    exit 1
}

# 等待磁盘同步（参考 Armbian，在创建分区表后）
wait_for_disk_sync "after creating partition table"

# 使用 --partscan 创建 loop 设备，强制内核扫描分区表
# 参考 Armbian: 使用 flock 锁定 loop 设备访问
exec {FD}> /var/lock/armbian-debootstrap-losetup 2>/dev/null || true
if [ -n "${FD}" ]; then
    flock -x ${FD} 2>/dev/null || true
fi

# 检查 sfdisk 版本（参考 Armbian）
sfdisk_version=$(sfdisk --version 2>&1 | awk '/util-linux/ {print $NF}' || echo "0.0.0")
sfdisk_version_num=$(echo "${sfdisk_version}" | awk -F. '{printf "%d%02d%02d\n", $1, $2, $3}')

# 确保有足够的 loop 设备节点（Docker 容器环境修复）
# 在容器中，宿主机后创建的 loop 设备节点不会自动出现
echo -e "${INFO} 检查并创建 loop 设备节点..."
NEXT_LOOP=$(losetup -f 2>/dev/null | grep -oE '[0-9]+$')
if [ -n "${NEXT_LOOP}" ]; then
    # 确保从 loop0 到 NEXT_LOOP+2 的设备节点都存在
    for i in $(seq 0 $((NEXT_LOOP + 2))); do
        if [ ! -e "/dev/loop${i}" ]; then
            mknod "/dev/loop${i}" b 7 "${i}" 2>/dev/null || true
            echo -e "${INFO} 创建 loop 设备节点: /dev/loop${i}"
        fi
    done
fi

# 创建 loop 设备（参考 Armbian 的实现）
declare LOOP_DEV
if [ "${sfdisk_version_num}" -ge "24100" ]; then
    # 使用 -b 参数指定扇区大小（如果支持）
    LOOP_DEV=$(losetup --show --partscan --find -b 512 "${IMG_FILE}" 2>&1) || {
        echo -e "${ERROR} 无法创建 loop 设备: ${IMG_FILE}"
        echo -e "${INFO} losetup 错误: $(losetup --show --partscan --find -b 512 "${IMG_FILE}" 2>&1)"
        [ -n "${FD}" ] && flock -u ${FD} 2>/dev/null || true
        exit 1
    }
else
    LOOP_DEV=$(losetup --show --partscan --find "${IMG_FILE}" 2>&1) || {
        echo -e "${ERROR} 无法创建 loop 设备: ${IMG_FILE}"
        echo -e "${INFO} losetup 错误: $(losetup --show --partscan --find "${IMG_FILE}" 2>&1)"
        [ -n "${FD}" ] && flock -u ${FD} 2>/dev/null || true
        exit 1
    }
fi

# 解锁
[ -n "${FD}" ] && flock -u ${FD} 2>/dev/null || true

echo -e "${INFO} 分配的 loop 设备: ${LOOP_DEV}"

# 运行 partprobe（参考 Armbian）
echo -e "${INFO} 运行 partprobe 识别分区..."
partprobe "${LOOP_DEV}" || true

# 等待分区设备节点创建（Docker 容器环境可能需要手动创建）
sleep 2

# 检查并创建分区设备节点（Docker 容器环境问题修复）
LOOP_BASE=$(basename "${LOOP_DEV}")
if [ ! -b "${LOOP_DEV}p1" ] || [ ! -b "${LOOP_DEV}p2" ]; then
    # 从 /proc/partitions 读取主次设备号并创建分区设备节点
    for part in p1 p2; do
        if [ ! -b "${LOOP_DEV}${part}" ]; then
            PART_INFO=$(grep "${LOOP_BASE}${part}" /proc/partitions 2>/dev/null | awk '{print $1, $2}')
            if [ -n "${PART_INFO}" ]; then
                MAJOR=$(echo "${PART_INFO}" | awk '{print $1}')
                MINOR=$(echo "${PART_INFO}" | awk '{print $2}')
                if [ -n "${MAJOR}" ] && [ -n "${MINOR}" ]; then
                    mknod "${LOOP_DEV}${part}" b "${MAJOR}" "${MINOR}" 2>/dev/null || true
                fi
            fi
        fi
    done
fi

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

# 8. 写入U-Boot到镜像开头（在挂载分区之前，参考 amlogic-s9xxx-armbian-new/rebuild）
# 参考 rebuild 脚本的 Rockchip 平台写入逻辑
echo -e "${INFO} 写入U-Boot到镜像开头..."
BOOTLOADER_IMG="idbloader.img"
MAINLINE_UBOOT="u-boot.itb"
TRUST_IMG=""

# 检查文件是否存在
if [ -f "${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" ] && [ -f "${UBOOT_OUTPUT}/${MAINLINE_UBOOT}" ] && [ -n "${TRUST_IMG}" ] && [ -f "${UBOOT_OUTPUT}/${TRUST_IMG}" ]; then
    # 情况1: 有 BOOTLOADER_IMG、MAINLINE_UBOOT 和 TRUST_IMG
    echo -e "${INFO} 写入 bootloader: ${BOOTLOADER_IMG}, ${MAINLINE_UBOOT}, ${TRUST_IMG}"
    dd if="${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" of="${LOOP_DEV}" conv=fsync,notrunc bs=512 seek=64 2>/dev/null
    dd if="${UBOOT_OUTPUT}/${MAINLINE_UBOOT}" of="${LOOP_DEV}" conv=fsync,notrunc bs=512 seek=16384 2>/dev/null
    dd if="${UBOOT_OUTPUT}/${TRUST_IMG}" of="${LOOP_DEV}" conv=fsync,notrunc bs=512 seek=24576 2>/dev/null
    echo -e "${SUCCESS} bootloader 写入成功（idbloader: 64, u-boot: 16384, trust: 24576 扇区）"
elif [ -f "${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" ] && [ -f "${UBOOT_OUTPUT}/${MAINLINE_UBOOT}" ]; then
    # 情况2: 有 BOOTLOADER_IMG 和 MAINLINE_UBOOT（microslam 使用此情况）
    echo -e "${INFO} 写入 bootloader: ${BOOTLOADER_IMG}, ${MAINLINE_UBOOT}"
    dd if="${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" of="${LOOP_DEV}" conv=fsync,notrunc bs=512 seek=64 2>/dev/null
    dd if="${UBOOT_OUTPUT}/${MAINLINE_UBOOT}" of="${LOOP_DEV}" conv=fsync,notrunc bs=512 seek=16384 2>/dev/null
    echo -e "${SUCCESS} bootloader 写入成功（idbloader: 64, u-boot: 16384 扇区）"
elif [ "${BOOTLOADER_IMG}" == "u-boot-rockchip.bin" ] && [ -f "${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" ]; then
    # 情况3: BOOTLOADER_IMG 是 u-boot-rockchip.bin
    echo -e "${INFO} 写入 bootloader: ${BOOTLOADER_IMG}"
    dd if="${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" of="${LOOP_DEV}" conv=fsync,notrunc bs=512 seek=64 2>/dev/null
    echo -e "${SUCCESS} bootloader 写入成功（偏移 64 扇区）"
elif [ -f "${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" ]; then
    # 情况4: 只有 BOOTLOADER_IMG
    echo -e "${INFO} 写入 bootloader: ${BOOTLOADER_IMG} (skip=64)"
    dd if="${UBOOT_OUTPUT}/${BOOTLOADER_IMG}" of="${LOOP_DEV}" conv=fsync,notrunc bs=512 skip=64 seek=64 2>/dev/null
    echo -e "${SUCCESS} bootloader 写入成功（skip=64, seek=64 扇区）"
else
    echo -e "${ERROR} 未找到 bootloader 文件: ${UBOOT_OUTPUT}/${BOOTLOADER_IMG}"
    exit 1
fi

# 9. 挂载分区并复制文件
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

# 复制rootfs内容（使用 /. 语法确保复制所有内容包括隐藏文件和空目录）
echo -e "${INFO} 复制rootfs内容..."
cp -a "${ROOTFS_TMP}/." "${ROOT_MOUNT}/"

# 10. 卸载分区
echo -e "${INFO} 卸载分区..."
sync
umount "${BOOT_MOUNT}" || true
umount "${ROOT_MOUNT}" || true

# 清理 loop 设备（trap 也会处理，但这里显式清理以确保顺序）
cleanup_loop_device

# 移除 trap，因为已经清理完成
trap - EXIT INT TERM

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
