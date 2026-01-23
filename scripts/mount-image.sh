#!/bin/bash
#================================================================================================
#
# MicroSLAM Image Mount Script
# 镜像挂载脚本，用于临时挂载 img 文件并手动检查其目录结构
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

# 全局变量
LOOP_DEV=""
BOOT_MOUNT=""
ROOT_MOUNT=""
IMG_FILE=""
TMP_DIR="${PROJECT_ROOT}/.tmp"

# 清理函数：卸载分区和删除 loop 设备
cleanup_mounts() {
    echo ""
    echo -e "${INFO} 清理挂载点..."
    
    # 卸载 boot 分区
    if [ -n "${BOOT_MOUNT}" ] && mountpoint -q "${BOOT_MOUNT}" 2>/dev/null; then
        echo -e "${INFO} 卸载 boot 分区: ${BOOT_MOUNT}"
        umount "${BOOT_MOUNT}" 2>/dev/null || true
    fi
    
    # 卸载 rootfs 分区
    if [ -n "${ROOT_MOUNT}" ] && mountpoint -q "${ROOT_MOUNT}" 2>/dev/null; then
        echo -e "${INFO} 卸载 rootfs 分区: ${ROOT_MOUNT}"
        umount "${ROOT_MOUNT}" 2>/dev/null || true
    fi
    
    # 删除 loop 设备
    if [ -n "${LOOP_DEV}" ] && [ -b "${LOOP_DEV}" ] 2>/dev/null; then
        echo -e "${INFO} 删除 loop 设备: ${LOOP_DEV}"
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi
    
    # 清理临时目录（如果为空）
    if [ -d "${BOOT_MOUNT}" ] && [ -z "$(ls -A "${BOOT_MOUNT}" 2>/dev/null)" ]; then
        rmdir "${BOOT_MOUNT}" 2>/dev/null || true
    fi
    if [ -d "${ROOT_MOUNT}" ] && [ -z "$(ls -A "${ROOT_MOUNT}" 2>/dev/null)" ]; then
        rmdir "${ROOT_MOUNT}" 2>/dev/null || true
    fi
    
    echo -e "${SUCCESS} 清理完成"
}

# 设置 trap：在脚本退出时清理
trap cleanup_mounts EXIT INT TERM

# 显示帮助信息
show_help() {
    echo "MicroSLAM Image Mount Script"
    echo ""
    echo "用法: $0 <img_file>"
    echo ""
    echo "参数:"
    echo "  <img_file>    要挂载的镜像文件路径"
    echo ""
    echo "选项:"
    echo "  -h, --help    显示此帮助信息"
    echo ""
    echo "说明:"
    echo "  此脚本会临时挂载指定的 img 文件，并允许您检查其目录结构。"
    echo "  挂载点位于: ${TMP_DIR}/boot_mount 和 ${TMP_DIR}/root_mount"
    echo "  退出脚本时会自动卸载并清理。"
    echo ""
    echo "示例:"
    echo "  $0 output/images/MicroSLAM-6.1.141-2025.01.23.img"
    echo ""
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${ERROR} 此脚本需要 root 权限来挂载分区"
        echo -e "${INFO} 请使用: sudo $0 $*"
        exit 1
    fi
}

# 检查并创建 loop 设备
setup_loop_device() {
    local img_file="$1"
    
    echo -e "${INFO} 检查镜像文件: ${img_file}"
    if [ ! -f "${img_file}" ]; then
        echo -e "${ERROR} 镜像文件不存在: ${img_file}"
        exit 1
    fi
    
    if [ ! -r "${img_file}" ]; then
        echo -e "${ERROR} 镜像文件不可读: ${img_file}"
        exit 1
    fi
    
    echo -e "${INFO} 创建 loop 设备..."
    
    # 检查 sfdisk 版本
    sfdisk_version=$(sfdisk --version 2>&1 | awk '/util-linux/ {print $NF}' || echo "0.0.0")
    sfdisk_version_num=$(echo "${sfdisk_version}" | awk -F. '{printf "%d%02d%02d\n", $1, $2, $3}')
    
    # 使用 flock 锁定 loop 设备访问（参考 Armbian）
    exec {FD}> /var/lock/armbian-debootstrap-losetup 2>/dev/null || true
    if [ -n "${FD}" ]; then
        flock -x ${FD} 2>/dev/null || true
    fi
    
    # 创建 loop 设备
    if [ "${sfdisk_version_num}" -ge "24100" ]; then
        LOOP_DEV=$(losetup --show --partscan --find -b 512 "${img_file}" 2>&1) || {
            echo -e "${ERROR} 无法创建 loop 设备: ${img_file}"
            [ -n "${FD}" ] && flock -u ${FD} 2>/dev/null || true
            exit 1
        }
    else
        LOOP_DEV=$(losetup --show --partscan --find "${img_file}" 2>&1) || {
            echo -e "${ERROR} 无法创建 loop 设备: ${img_file}"
            [ -n "${FD}" ] && flock -u ${FD} 2>/dev/null || true
            exit 1
        }
    fi
    
    # 解锁
    [ -n "${FD}" ] && flock -u ${FD} 2>/dev/null || true
    
    echo -e "${SUCCESS} 分配的 loop 设备: ${LOOP_DEV}"
    
    # 运行 partprobe 识别分区
    echo -e "${INFO} 运行 partprobe 识别分区..."
    partprobe "${LOOP_DEV}" || true
    
    # 等待分区设备节点创建
    sleep 2
    
    # 检查并创建分区设备节点（Docker 容器环境问题修复）
    LOOP_BASE=$(basename "${LOOP_DEV}")
    if [ ! -b "${LOOP_DEV}p1" ] || [ ! -b "${LOOP_DEV}p2" ]; then
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
    
    # 验证分区设备存在
    if [ ! -b "${LOOP_DEV}p1" ]; then
        echo -e "${ERROR} 未找到 boot 分区设备: ${LOOP_DEV}p1"
        exit 1
    fi
    
    if [ ! -b "${LOOP_DEV}p2" ]; then
        echo -e "${ERROR} 未找到 rootfs 分区设备: ${LOOP_DEV}p2"
        exit 1
    fi
    
    echo -e "${SUCCESS} 分区设备检查完成"
    echo -e "${INFO} Boot 分区: ${LOOP_DEV}p1"
    echo -e "${INFO} Rootfs 分区: ${LOOP_DEV}p2"
}

# 挂载分区
mount_partitions() {
    # 创建临时挂载点
    mkdir -p "${TMP_DIR}"
    BOOT_MOUNT="${TMP_DIR}/boot_mount"
    ROOT_MOUNT="${TMP_DIR}/root_mount"
    
    mkdir -p "${BOOT_MOUNT}" "${ROOT_MOUNT}"
    
    # 挂载 boot 分区
    echo -e "${INFO} 挂载 boot 分区..."
    mount "${LOOP_DEV}p1" "${BOOT_MOUNT}" || {
        echo -e "${ERROR} 挂载 boot 分区失败"
        exit 1
    }
    echo -e "${SUCCESS} Boot 分区已挂载: ${BOOT_MOUNT}"
    
    # 检测 rootfs 文件系统类型
    ROOTFS_TYPE=$(blkid -s TYPE -o value "${LOOP_DEV}p2" 2>/dev/null || echo "ext4")
    echo -e "${INFO} Rootfs 文件系统类型: ${ROOTFS_TYPE}"
    
    # 挂载 rootfs 分区
    echo -e "${INFO} 挂载 rootfs 分区..."
    if [ "${ROOTFS_TYPE}" = "btrfs" ]; then
        mount -t btrfs "${LOOP_DEV}p2" "${ROOT_MOUNT}" || {
            echo -e "${ERROR} 挂载 rootfs 分区失败"
            exit 1
        }
    else
        mount "${LOOP_DEV}p2" "${ROOT_MOUNT}" || {
            echo -e "${ERROR} 挂载 rootfs 分区失败"
            exit 1
        }
    fi
    echo -e "${SUCCESS} Rootfs 分区已挂载: ${ROOT_MOUNT}"
}

# 显示目录结构
show_directory_structure() {
    echo ""
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 目录结构"
    echo -e "${STEPS} ========================================"
    echo ""
    
    echo -e "${INFO} Boot 分区 (${BOOT_MOUNT}):"
    echo "----------------------------------------"
    if [ -d "${BOOT_MOUNT}" ] && [ "$(ls -A "${BOOT_MOUNT}" 2>/dev/null)" ]; then
        ls -lah "${BOOT_MOUNT}" | head -20
        echo ""
        echo -e "${INFO} Boot 分区大小:"
        du -sh "${BOOT_MOUNT}"/* 2>/dev/null | head -10 || true
    else
        echo -e "${WARNING} Boot 分区为空"
    fi
    
    echo ""
    echo -e "${INFO} Rootfs 分区 (${ROOT_MOUNT}):"
    echo "----------------------------------------"
    if [ -d "${ROOT_MOUNT}" ] && [ "$(ls -A "${ROOT_MOUNT}" 2>/dev/null)" ]; then
        ls -lah "${ROOT_MOUNT}" | head -20
        echo ""
        echo -e "${INFO} Rootfs 分区主要目录大小:"
        du -sh "${ROOT_MOUNT}"/* 2>/dev/null | head -15 || true
    else
        echo -e "${WARNING} Rootfs 分区为空"
    fi
    
    echo ""
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 挂载信息"
    echo -e "${STEPS} ========================================"
    echo ""
    echo -e "${INFO} 镜像文件: ${IMG_FILE}"
    echo -e "${INFO} Loop 设备: ${LOOP_DEV}"
    echo -e "${INFO} Boot 挂载点: ${BOOT_MOUNT}"
    echo -e "${INFO} Rootfs 挂载点: ${ROOT_MOUNT}"
    echo ""
    echo -e "${INFO} 您可以在以下目录中检查文件:"
    echo -e "${INFO}   - Boot: ${BOOT_MOUNT}"
    echo -e "${INFO}   - Rootfs: ${ROOT_MOUNT}"
    echo ""
    echo -e "${WARNING} 按 Enter 键退出并自动卸载..."
    read -r
}

# 主函数
main() {
    # 解析参数
    if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi
    
    IMG_FILE="$1"
    
    # 转换为绝对路径
    if [[ "${IMG_FILE}" != /* ]]; then
        IMG_FILE="$(cd "$(dirname "${IMG_FILE}")" && pwd)/$(basename "${IMG_FILE}")"
    fi
    
    # 检查 root 权限
    check_root "$@"
    
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} MicroSLAM 镜像挂载工具"
    echo -e "${STEPS} ========================================"
    echo ""
    
    # 设置 loop 设备
    setup_loop_device "${IMG_FILE}"
    
    # 挂载分区
    mount_partitions
    
    # 显示目录结构
    show_directory_structure
    
    # 清理会在 trap 中自动执行
}

# 执行主函数
main "$@"
