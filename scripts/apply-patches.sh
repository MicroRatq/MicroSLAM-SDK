#!/bin/bash
#================================================================================================
#
# MicroSLAM Unified Patch Script
# 从 configs 目录生成所有 userpatches 内容并集成到构建系统
#
# 此脚本会：
# 1. 从 configs/kernel/dts/ 集成设备树文件到内核源码树
# 2. 从 configs/uboot/ 集成 U-Boot defconfig 到 U-Boot 源码树
# 3. 从 configs/kernel/config-6.1 生成内核配置文件
# 4. 从 configs/ 生成其他必要的 userpatches 文件
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 路径配置
ARMBIAN_DIR="${PROJECT_ROOT}/repos/armbian-build"
KERNEL_DIR="${PROJECT_ROOT}/repos/linux-6.1.y-rockchip"
CONFIGS_DIR="${PROJECT_ROOT}/configs"
USERPATCHES_DIR="${PROJECT_ROOT}/userpatches"
ARMBIAN_USERPATCHES="${ARMBIAN_DIR}/userpatches"

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

# 是否在板级配置中启用 GNOME 桌面支持（需配合 build.sh --desktop 构建桌面镜像）
# 可由 --desktop 参数指定，或由 build-rootfs.sh 传入的 BUILD_DESKTOP=yes 自动同步
APPLY_DESKTOP="${APPLY_DESKTOP:-no}"
while [[ $# -gt 0 ]]; do
    case $1 in
        --desktop)
            APPLY_DESKTOP="yes"
            shift
            ;;
        *)
            echo -e "${WARNING} 未知参数: $1"
            shift
            ;;
    esac
done
# 若由 build-rootfs.sh 调用且已传 BUILD_DESKTOP=yes，则同步启用桌面配置
if [[ "${APPLY_DESKTOP}" != "yes" ]] && [[ "${BUILD_DESKTOP:-no}" == "yes" ]]; then
    APPLY_DESKTOP="yes"
fi

echo -e "${STEPS} 开始应用 MicroSLAM 补丁和配置..."
if [[ "${APPLY_DESKTOP}" == "yes" ]]; then
    echo -e "${INFO} 已启用 GNOME 桌面支持（板级配置将包含 DESKTOP_ENVIRONMENT）"
fi

# ============================================================================
# 第一部分：集成设备树文件到内核源码树
# ============================================================================
echo -e "${INFO} [1/4] 集成设备树文件到内核源码树..."

DTS_SOURCE="${CONFIGS_DIR}/kernel/dts/rk3588-microslam.dts"
DTS_TARGET="${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/rk3588-microslam.dts"
MAKEFILE_TARGET="${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/Makefile"

if [ ! -d "${KERNEL_DIR}" ]; then
    echo -e "${WARNING} 内核源码目录不存在，将在构建时集成: ${KERNEL_DIR}"
else
    if [ -f "${DTS_SOURCE}" ]; then
        # 创建目标目录
        mkdir -p "$(dirname "${DTS_TARGET}")"
        
        # 复制设备树文件
        cp -f "${DTS_SOURCE}" "${DTS_TARGET}"
        echo -e "${SUCCESS} 设备树文件已复制: ${DTS_TARGET}"
        
        # 更新 Makefile
        if [ -f "${MAKEFILE_TARGET}" ]; then
            if ! grep -q "rk3588-microslam.dtb" "${MAKEFILE_TARGET}"; then
                if grep -q "dtb-\$(CONFIG_ARCH_ROCKCHIP)" "${MAKEFILE_TARGET}"; then
                    sed -i '/dtb-\$(CONFIG_ARCH_ROCKCHIP).*rk3588-rock-5b\.dtb/a\dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-microslam.dtb' "${MAKEFILE_TARGET}"
                    echo -e "${SUCCESS} Makefile已更新，添加了rk3588-microslam.dtb规则"
                else
                    sed -i '1i# SPDX-License-Identifier: GPL-2.0\ndtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-microslam.dtb' "${MAKEFILE_TARGET}"
                    echo -e "${SUCCESS} Makefile已更新，添加了rk3588-microslam.dtb规则"
                fi
            else
                echo -e "${INFO} Makefile中已存在rk3588-microslam.dtb规则，跳过更新"
            fi
        fi
    else
        echo -e "${WARNING} 设备树源文件不存在: ${DTS_SOURCE}"
    fi
fi

# ============================================================================
# 第二部分：集成 U-Boot defconfig、头文件和 DTS 文件到 U-Boot 源码树
# ============================================================================
echo -e "${INFO} [2/4] 集成 U-Boot defconfig、头文件和 DTS 文件到 U-Boot 源码树..."

UBOOT_DEFCONFIG_SOURCE="${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig"
UBOOT_HEADER_SOURCE="${CONFIGS_DIR}/uboot/include/configs/microslam.h"
UBOOT_DTS_SOURCE="${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts"
UBOOT_POSSIBLE_DIRS=(
    "${ARMBIAN_DIR}/cache/sources/u-boot-worktree/u-boot/next-dev-v2024.10"
    "${ARMBIAN_DIR}/cache/sources/u-boot-worktree/u-boot"
    "${ARMBIAN_DIR}/cache/sources/u-boot"
)

if [ -f "${UBOOT_DEFCONFIG_SOURCE}" ]; then
    UBOOT_SRC_DIR=""
    for dir in "${UBOOT_POSSIBLE_DIRS[@]}"; do
        if [ -d "${dir}/configs" ]; then
            UBOOT_SRC_DIR="${dir}"
            break
        fi
    done
    
    if [ -n "${UBOOT_SRC_DIR}" ]; then
        # 复制 defconfig
        if cp -f "${UBOOT_DEFCONFIG_SOURCE}" "${UBOOT_SRC_DIR}/configs/rk3588-microslam_defconfig" 2>/dev/null; then
            echo -e "${SUCCESS} U-Boot defconfig 已复制: ${UBOOT_SRC_DIR}/configs/rk3588-microslam_defconfig"
        else
            echo -e "${WARNING} 无法复制 U-Boot defconfig（权限不足），将在构建时通过 patch 复制"
        fi
        
        # 复制头文件
        if [ -f "${UBOOT_HEADER_SOURCE}" ]; then
            if cp -f "${UBOOT_HEADER_SOURCE}" "${UBOOT_SRC_DIR}/include/configs/microslam.h" 2>/dev/null; then
                echo -e "${SUCCESS} U-Boot 头文件已复制: ${UBOOT_SRC_DIR}/include/configs/microslam.h"
            else
                echo -e "${WARNING} 无法复制 U-Boot 头文件（权限不足），将在构建时通过 patch 复制"
            fi
        fi
        
        # 复制 DTS 文件
        if [ -f "${UBOOT_DTS_SOURCE}" ]; then
            UBOOT_DTS_TARGET="${UBOOT_SRC_DIR}/arch/arm/dts/rk3588-microslam.dts"
            mkdir -p "$(dirname "${UBOOT_DTS_TARGET}")"
            if cp -f "${UBOOT_DTS_SOURCE}" "${UBOOT_DTS_TARGET}" 2>/dev/null; then
                echo -e "${SUCCESS} U-Boot DTS 文件已复制: ${UBOOT_DTS_TARGET}"
            else
                echo -e "${WARNING} 无法复制 U-Boot DTS 文件（权限不足），将在构建时通过 patch 复制"
            fi
        else
            echo -e "${WARNING} U-Boot DTS 源文件不存在: ${UBOOT_DTS_SOURCE}"
        fi
    else
        echo -e "${INFO} U-Boot 源码目录尚未准备，文件将在构建时通过 patch 复制"
    fi
else
    echo -e "${WARNING} U-Boot defconfig 源文件不存在: ${UBOOT_DEFCONFIG_SOURCE}"
fi

# ============================================================================
# 第三部分：从 configs 生成 userpatches 文件
# ============================================================================
echo -e "${INFO} [3/4] 从 configs 生成 userpatches 文件..."

# 创建 userpatches 目录结构
mkdir -p "${ARMBIAN_USERPATCHES}/sources" \
         "${ARMBIAN_USERPATCHES}/patch/kernel" \
         "${ARMBIAN_USERPATCHES}/patch/u-boot/legacy/u-boot-radxa-rk35xx/defconfig" \
         "${ARMBIAN_USERPATCHES}/overlay" \
         "${ARMBIAN_USERPATCHES}/config/boards" \
         "${ARMBIAN_USERPATCHES}/extensions"

# 3.1 生成板卡配置文件（从 configs 生成，但保留基本结构）
BOARD_CONFIG="${ARMBIAN_USERPATCHES}/config/boards/microslam.conf"
cat > "${BOARD_CONFIG}" << 'EOF'
# MicroSLAM Board Configuration
# This file defines the MicroSLAM board configuration for Armbian build
# Generated from configs directory

# Board identification
BOARD_NAME="MicroSLAM"
BOARDFAMILY="rockchip-rk3588"
LINUXFAMILY="rockchip-rk3588"

# Device tree configuration
BOOT_FDT_FILE="rockchip/rk3588-microslam.dtb"
BOOT_FDT_OVERLAY_DIR="rockchip/overlay"

# Kernel configuration
KERNEL_TARGET="current"
BOOTCONFIG="rk3588-microslam_defconfig"

# 使用 post_family_config hook 来覆盖 family 配置中的内核设置
# 因为 rockchip64_common.inc 中 current 分支默认使用 6.18 内核
post_family_config__microslam_kernel_6_1() {
    # 强制使用 6.1 内核版本和 unifreq 仓库
    declare -g KERNEL_MAJOR_MINOR="6.1"
    KERNELSOURCE="https://github.com/unifreq/linux-6.1.y-rockchip"
    KERNELBRANCH="branch:main"
    KERNELDIR="linux-6.1.y-rockchip"
    KERNEL_USE_GCC='> 10.0'
    # 设置内核 patch 目录（如果存在）
    KERNELPATCHDIR="archive/rockchip64-6.1"
    display_alert "MicroSLAM kernel config" "Using kernel 6.1 from unifreq/linux-6.1.y-rockchip" "info"
}

# Boot script
BOOTSCRIPT="boot-rockchip64.cmd:boot-rockchip64.scr"

# U-Boot configuration
BOOTSOURCE='https://github.com/ophub/u-boot'
BOOTBRANCH='branch:main'
BOOTDIR="u-boot"

# Package configuration（Intel Wi-Fi ucode 改由 customize-image 阶段 apt 安装 linux-firmware）
PACKAGE_LIST_BOARD=""

# Image configuration
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="ext4"
ROOTFS_TYPE="ext4"

# Hardware configuration
BOOT_SOC="rk3588"
ARCH=arm64

# Skip incompatible kernel driver patches
# unifreq/linux-6.1.y-rockchip 仓库已经包含了某些驱动的上游版本，与 Armbian 的 patch 冲突
declare -g -a KERNEL_DRIVERS_SKIP=(
    driver_mt7921u_add_pids  # MT7921u PID patch 在 unifreq 仓库中失败
    driver_rtw88              # rtw88 驱动已包含在 unifreq 仓库的上游版本中，patch 冲突
)

# Enable MicroSLAM extensions
declare -g EXTRA_EXTENSIONS="microslam-uboot microslam-loop-fix microslam-systemd-fix"
EOF

# 若指定 --desktop，追加 GNOME 桌面相关变量，供 build-rootfs.sh 在 BUILD_DESKTOP=yes 时使用
if [[ "${APPLY_DESKTOP}" == "yes" ]]; then
    cat >> "${BOARD_CONFIG}" << 'DESKTOPEOF'

# GNOME desktop support (when BUILD_DESKTOP=yes and build.sh --desktop)
# Armbian 据此安装 armbian-desktop / armbian-bsp-desktop 及 GNOME 相关包
DESKTOP_ENVIRONMENT="gnome"
DESKTOP_ENVIRONMENT_CONFIG_NAME="config_base"
DESKTOP_APPGROUPS_INSTALL="browser desktop"
DESKTOP_AUTOLOGIN="yes"
DESKTOP_ENVIRONMENT_PACKAGE_LIST="gnome"
DESKTOPEOF
    echo -e "${SUCCESS} 已向板卡配置追加 GNOME 桌面支持: ${BOARD_CONFIG}"
fi

echo -e "${SUCCESS} 已生成板卡配置文件: ${BOARD_CONFIG}"

# 3.2 从 configs/kernel/config-6.1 生成内核配置文件
KERNEL_CONFIG_SOURCE="${CONFIGS_DIR}/kernel/config-6.1"
KERNEL_CONFIG_TARGET="${ARMBIAN_USERPATCHES}/linux-rockchip64-current.config"

if [ -f "${KERNEL_CONFIG_SOURCE}" ]; then
    cp -f "${KERNEL_CONFIG_SOURCE}" "${KERNEL_CONFIG_TARGET}"
    echo -e "${SUCCESS} 已生成内核配置文件: ${KERNEL_CONFIG_TARGET}"
else
    echo -e "${WARNING} 内核配置源文件不存在: ${KERNEL_CONFIG_SOURCE}"
fi

# 3.3 生成内核源配置
# 注意：这个配置会被 board 配置文件中的设置覆盖
# 为了确保使用正确的内核源，我们在 board 配置中也设置这些变量
SOURCES_CONFIG="${ARMBIAN_USERPATCHES}/sources/rockchip.conf"
cat > "${SOURCES_CONFIG}" << 'EOF'
# Rockchip Kernel Source Configuration
# This file specifies the custom kernel repository for Rockchip platforms

KERNELSOURCE="https://github.com/unifreq/linux-6.1.y-rockchip"
KERNELBRANCH="branch:main"
KERNELDIR="linux-6.1.y-rockchip"
KERNEL_USE_GCC='> 10.0'
EOF
echo -e "${SUCCESS} 已生成内核源配置: ${SOURCES_CONFIG}"

# 3.4 生成镜像自定义脚本
CUSTOMIZE_SCRIPT="${ARMBIAN_USERPATCHES}/customize-image.sh"
cat > "${CUSTOMIZE_SCRIPT}" << 'EOF'
#!/bin/bash
#================================================================================================
#
# Armbian Image Customization Script
# 在镜像打包前注入MicroSLAM的bootfs和rootfs配置
#
# This script is called by Armbian build system before finalizing the image
# It runs inside the chroot environment
#
#================================================================================================

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"

echo -e "${STEPS} 开始自定义MicroSLAM镜像..."

# 覆盖 /etc/fstab 为 MicroSLAM 分区布局（p1=/boot, p2=/），替换 Armbian distro-agnostic 的 p1=/, p2=/usr
# 此步骤不依赖外部配置，始终执行
echo -e "${INFO} 写入 /etc/fstab（MicroSLAM 分区布局：p1=/boot, p2=/）..."
cat > /etc/fstab << 'FSTABEOF'
# UNCONFIGURED FSTAB FOR BASE SYSTEM
/dev/mmcblk0p1 /boot ext4 defaults 0 1
/dev/mmcblk0p2 / ext4 defaults 0 2
FSTABEOF
echo -e "${INFO} 已覆盖 /etc/fstab"

# 恢复 /etc/update-motd.d 可执行权限（distro-agnostic 会 chmod -x，在此恢复以允许首次启动即显示 MOTD）
chmod +x /etc/update-motd.d/* 2>/dev/null || true
echo -e "${INFO} 已恢复 /etc/update-motd.d 可执行权限"

# 获取MicroSLAM配置文件的路径
# 这些文件应该在构建时被复制到armbian-build目录
MICROSLAM_CONFIGS="/MicroSLAM-SDK/configs"

# 检查配置文件是否存在（在构建环境中）
if [ ! -d "${MICROSLAM_CONFIGS}" ]; then
    # 尝试从其他可能的位置查找
    if [ -d "/root/MicroSLAM-SDK/configs" ]; then
        MICROSLAM_CONFIGS="/root/MicroSLAM-SDK/configs"
    elif [ -d "/MicroSLAM/configs" ]; then
        MICROSLAM_CONFIGS="/MicroSLAM/configs"
    else
        echo -e "${INFO} 未找到MicroSLAM配置文件，跳过 bootfs/rootfs 复制步骤"
        echo -e "${SUCCESS} MicroSLAM镜像自定义完成"
        exit 0
    fi
fi

# 复制bootfs配置
if [ -d "${MICROSLAM_CONFIGS}/bootfs" ]; then
    echo -e "${INFO} 复制bootfs配置..."
    
    # 复制armbianEnv.txt
    if [ -f "${MICROSLAM_CONFIGS}/bootfs/armbianEnv.txt" ]; then
        cp -f "${MICROSLAM_CONFIGS}/bootfs/armbianEnv.txt" /boot/armbianEnv.txt
        echo -e "${INFO} 已更新 /boot/armbianEnv.txt"
    fi
    
    # 复制boot.cmd并重新编译boot.scr
    if [ -f "${MICROSLAM_CONFIGS}/bootfs/boot.cmd" ]; then
        cp -f "${MICROSLAM_CONFIGS}/bootfs/boot.cmd" /boot/boot.cmd
        if command -v mkimage >/dev/null 2>&1; then
            mkimage -C none -A arm -T script -n 'MicroSLAM boot script' \
                -d /boot/boot.cmd /boot/boot.scr 2>/dev/null || true
            echo -e "${INFO} 已更新 /boot/boot.cmd 和 /boot/boot.scr"
        fi
    fi
fi

# 复制rootfs配置
if [ -d "${MICROSLAM_CONFIGS}/rootfs" ]; then
    echo -e "${INFO} 复制rootfs配置..."
    
    # 复制balance_irq
    if [ -f "${MICROSLAM_CONFIGS}/rootfs/etc/balance_irq" ]; then
        mkdir -p /etc
        cp -f "${MICROSLAM_CONFIGS}/rootfs/etc/balance_irq" /etc/balance_irq
        chmod 644 /etc/balance_irq
        echo -e "${INFO} 已复制 /etc/balance_irq"
    fi
    
    # 复制 iwlwifi 模块配置（禁用节电等，避免 -110 超时）
    if [ -f "${MICROSLAM_CONFIGS}/rootfs/etc/modprobe.d/iwlwifi.conf" ]; then
        mkdir -p /etc/modprobe.d
        cp -f "${MICROSLAM_CONFIGS}/rootfs/etc/modprobe.d/iwlwifi.conf" /etc/modprobe.d/iwlwifi.conf
        chmod 644 /etc/modprobe.d/iwlwifi.conf
        echo -e "${INFO} 已复制 /etc/modprobe.d/iwlwifi.conf"
    fi
    
    # 复制 NetworkManager 配置（将 wlan0 作为首选无线网卡，屏蔽 p2p0）
    if [ -f "${MICROSLAM_CONFIGS}/rootfs/etc/NetworkManager/NetworkManager.conf" ]; then
        mkdir -p /etc/NetworkManager
        cp -f "${MICROSLAM_CONFIGS}/rootfs/etc/NetworkManager/NetworkManager.conf" /etc/NetworkManager/NetworkManager.conf
        chmod 644 /etc/NetworkManager/NetworkManager.conf
        echo -e "${INFO} 已复制 /etc/NetworkManager/NetworkManager.conf"
    fi
    
    # 复制 gdm3 配置（强制使用 X11，避免 Wayland 在 RK3588 上的 DRM 问题）
    if [ -f "${MICROSLAM_CONFIGS}/rootfs/etc/gdm3/custom.conf" ]; then
        mkdir -p /etc/gdm3
        cp -f "${MICROSLAM_CONFIGS}/rootfs/etc/gdm3/custom.conf" /etc/gdm3/custom.conf
        chmod 644 /etc/gdm3/custom.conf
        echo -e "${INFO} 已复制 /etc/gdm3/custom.conf（强制 X11）"
    fi

    # 应用用户配置（users.yaml）
    USERS_CONFIG="${MICROSLAM_CONFIGS}/rootfs/users.yaml"
    if [ -f "${USERS_CONFIG}" ]; then
        echo -e "${INFO} 应用用户配置: ${USERS_CONFIG}"

        while IFS=$'\t' read -r username password; do
            # 跳过空行或解析失败的条目
            if [ -z "${username}" ]; then
                continue
            fi

            # 如果密码为空，跳过该用户
            if [ -z "${password}" ]; then
                echo -e "${INFO} 用户 ${username} 密码为空，跳过"
                continue
            fi

            if [ "${username}" = "root" ]; then
                echo "root:${password}" | chpasswd
                echo -e "${INFO} 已设置 root 密码"
            else
                if ! id -u "${username}" >/dev/null 2>&1; then
                    # 确保 /home 存在，否则 useradd -m 可能不会创建目录
                    mkdir -p /home
                    useradd -m -s /bin/bash "${username}"
                    echo -e "${INFO} 已创建用户 ${username}"
                fi

                # 若 home 目录未创建，手动补齐并修正属主
                if [ ! -d "/home/${username}" ]; then
                    mkdir -p "/home/${username}"
                    chown "${username}:${username}" "/home/${username}"
                    chmod 755 "/home/${username}"
                    echo -e "${INFO} 已创建 /home/${username}"
                fi

                echo "${username}:${password}" | chpasswd
                if usermod -aG video,render,input,tty "${username}"; then
                    echo -e "${INFO} 已将 ${username} 加入 video/render/input/tty 组"
                else
                    echo -e "${INFO} 无法将 ${username} 加入 video/render/input/tty 组（可能不存在该组）"
                fi
                echo -e "${INFO} 已设置 ${username} 密码"
            fi
        done < <(
            awk '
                BEGIN { in_users = 0; user = "" }
                {
                    line = $0
                    sub(/#.*/, "", line)
                    if (line ~ /^[ \t]*$/) next
                    if (line ~ /^users:[ \t]*$/) { in_users = 1; next }
                    if (!in_users) next
                    if (line ~ /^[ \t]{2}[^:]+:[ \t]*$/) {
                        sub(/^[ \t]{2}/, "", line)
                        sub(/:[ \t]*$/, "", line)
                        user = line
                        next
                    }
                    if (line ~ /^[ \t]{4}password:[ \t]*/ && user != "") {
                        sub(/^[ \t]{4}password:[ \t]*/, "", line)
                        gsub(/^[ \t]+|[ \t]+$/, "", line)
                        gsub(/^["\047]|["\047]$/, "", line)
                        print user "\t" line
                    }
                }
            ' "${USERS_CONFIG}"
        )
    else
        echo -e "${INFO} 未找到 users.yaml，跳过用户配置"
    fi
fi

# 仅安装 iwlwifi-ty-a0-gf-a0（Intel AX210）固件为 .ucode，避免整包 linux-firmware 导致 rootfs 增大约 600MB 且多为 .zst
if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
    echo -e "${INFO} 安装 iwlwifi-ty-a0-gf-a0 固件（.ucode）..."
    _fw_tmp="/tmp/microslam-fw"
    _deb_tmp="/tmp/microslam-fw-deb"
    mkdir -p "${_fw_tmp}" "${_deb_tmp}"
    _fw_src=""
    if apt-get update -qq 2>/dev/null; then
        (cd "${_deb_tmp}" && apt-get download -q linux-firmware 2>/dev/null)
        _deb="$(ls -1 "${_deb_tmp}"/linux-firmware_*.deb 2>/dev/null | head -1)"
        if [ -n "${_deb}" ] && [ -f "${_deb}" ]; then
            dpkg -x "${_deb}" "${_fw_tmp}"
            [ -d "${_fw_tmp}/lib/firmware" ] && _fw_src="${_fw_tmp}/lib/firmware"
            [ -z "${_fw_src}" ] && [ -d "${_fw_tmp}/usr/lib/firmware" ] && _fw_src="${_fw_tmp}/usr/lib/firmware"
        fi
    fi
    if [ -n "${_fw_src}" ]; then
        mkdir -p /lib/firmware
        for _f in "${_fw_src}"/iwlwifi-ty-a0-gf-a0*; do
            [ -e "${_f}" ] || continue
            _base="$(basename "${_f}")"
            if [ "${_base%.zst}" != "${_base}" ]; then
                _out="${_base%.zst}"
                if command -v zstd >/dev/null 2>&1; then
                    zstd -d -q -f -o "/lib/firmware/${_out}" "${_f}" 2>/dev/null || true
                fi
            else
                cp -f "${_f}" "/lib/firmware/${_base}" 2>/dev/null || true
            fi
        done
        echo -e "${INFO} 已安装 iwlwifi-ty-a0-gf-a0（仅 .ucode/.pnvm，无整包冗余）"
    fi
    rm -rf "${_fw_tmp}" "${_deb_tmp}"
fi

# 桌面环境配置：gdm3 为 static 服务，确保 graphical.target 与 display-manager.service 正确关联
GDM_UNIT=""
if [ -f /usr/lib/systemd/system/gdm.service ]; then
    GDM_UNIT="/usr/lib/systemd/system/gdm.service"
elif [ -f /lib/systemd/system/gdm.service ]; then
    GDM_UNIT="/lib/systemd/system/gdm.service"
elif [ -f /usr/lib/systemd/system/gdm3.service ]; then
    GDM_UNIT="/usr/lib/systemd/system/gdm3.service"
elif [ -f /lib/systemd/system/gdm3.service ]; then
    GDM_UNIT="/lib/systemd/system/gdm3.service"
fi

if [ -n "${GDM_UNIT}" ]; then
    echo -e "${INFO} 检测到 GDM 单元：${GDM_UNIT}"

    # 设置默认启动 target 为 graphical.target
    rm -f /etc/systemd/system/default.target
    if [ -f /usr/lib/systemd/system/graphical.target ]; then
        ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
    elif [ -f /lib/systemd/system/graphical.target ]; then
        ln -sf /lib/systemd/system/graphical.target /etc/systemd/system/default.target
    fi
    echo -e "${INFO} 已设置默认启动 target 为 graphical.target"

    # 创建 display-manager.service 指向 gdm.service，确保 graphical.target 能拉起显示管理器
    mkdir -p /etc/systemd/system
    rm -f /etc/systemd/system/display-manager.service
    ln -sf "${GDM_UNIT}" /etc/systemd/system/display-manager.service
    echo -e "${INFO} 已创建 display-manager.service -> ${GDM_UNIT}"
else
    echo -e "${INFO} 未检测到 GDM 单元，保持默认 CLI 模式"
fi

echo -e "${SUCCESS} MicroSLAM镜像自定义完成"
EOF
chmod +x "${CUSTOMIZE_SCRIPT}"
echo -e "${SUCCESS} 已生成镜像自定义脚本: ${CUSTOMIZE_SCRIPT}"

# 3.5 生成 U-Boot extension（复制 defconfig、头文件和板卡目录）
UBOOT_EXTENSION="${ARMBIAN_USERPATCHES}/extensions/microslam-uboot.sh"
cat > "${UBOOT_EXTENSION}" << 'EOF'
#!/bin/bash
#================================================================================================
#
# MicroSLAM U-Boot Extension
# 在U-Boot准备阶段集成自定义defconfig、头文件和板卡目录
#
# 根据 Armbian 官方规范：
# - 扩展文件只包含函数定义，不应有顶层执行代码
# - Hook 函数命名格式：hookname__implementation_name
# - 必须在 pre_config_uboot_target hook 中复制 board 文件，确保在 patch 之后、配置之前完成
#
#================================================================================================

# 注意：扩展通过配置文件中的 EXTRA_EXTENSIONS="microslam-uboot" 启用
# 不需要在扩展文件内部调用 enable_extension

# 调试：确认扩展文件被加载
echo "MicroSLAM U-Boot extension file loaded" >&2

function extension_prepare_config__microslam_uboot() {
    echo "extension_prepare_config__microslam_uboot called" >&2
    display_alert "Preparing MicroSLAM U-Boot files" "defconfig, header, board" "info"
}

function pre_config_uboot_target__microslam_uboot() {
    # 根据 Armbian 官方规范，pre_config_uboot_target hook 在 patch 完成后、配置之前执行
    # 这是复制 board 文件的最佳时机，确保在配置阶段之前文件已存在
    # 当前工作目录应该是 U-Boot 源码目录
    
    # 强制输出到标准错误，确保能看到
    echo "==========================================" >&2
    echo "MicroSLAM U-Boot Extension: pre_config_uboot_target hook called" >&2
    echo "Current directory: $(pwd)" >&2
    echo "SRC: ${SRC}" >&2
    echo "==========================================" >&2
    
    display_alert "MicroSLAM U-Boot extension" "pre_config_uboot_target hook - copying board files" "info"
    copy_microslam_uboot_files
    
    echo "==========================================" >&2
    echo "MicroSLAM U-Boot Extension: pre_config_uboot_target hook finished" >&2
    echo "==========================================" >&2
}

function copy_microslam_uboot_files() {
    # 获取 MicroSLAM-SDK 配置目录路径
    # 首先尝试从 patch 目录复制（因为 overlay 可能已经复制了部分文件）
    local patch_dir="${SRC}/patch/u-boot/legacy/u-boot-radxa-rk35xx"
    local microslam_configs="${SRC}/MicroSLAM-SDK/configs/uboot"
    
    # 调试：显示路径信息（输出到标准错误）
    echo "--- copy_microslam_uboot_files called ---" >&2
    echo "patch_dir: ${patch_dir}" >&2
    echo "microslam_configs: ${microslam_configs}" >&2
    echo "current: $(pwd)" >&2
    echo "SRC: ${SRC}" >&2
    display_alert "MicroSLAM U-Boot copy function" "patch_dir: ${patch_dir}, microslam_configs: ${microslam_configs}, current: $(pwd)" "info"
    
    # 如果链接不存在，尝试其他路径
    if [ ! -d "${microslam_configs}" ]; then
        microslam_configs="${SRC}/../MicroSLAM-SDK/configs/uboot"
    fi
    
    # 如果还是找不到，尝试从 PROJECT_ROOT 查找
    if [ ! -d "${microslam_configs}" ]; then
        local project_root="${SRC}/.."
        if [ -d "${project_root}/MicroSLAM-SDK/configs/uboot" ]; then
            microslam_configs="${project_root}/MicroSLAM-SDK/configs/uboot"
        fi
    fi
    
    # 查找 U-Boot 源码目录（当前工作目录应该是 U-Boot 源码目录）
    local uboot_src_dir="$(pwd)"
    if [ ! -d "${uboot_src_dir}/configs" ]; then
        # 如果当前目录不是 U-Boot 源码目录，尝试查找
        local uboot_src_dirs=(
            "${SRC}/cache/sources/u-boot-worktree/u-boot/next-dev-v2024.10"
            "${SRC}/cache/sources/u-boot-worktree/u-boot"
            "${SRC}/cache/sources/u-boot"
        )
        
        for dir in "${uboot_src_dirs[@]}"; do
            if [ -d "${dir}/configs" ]; then
                uboot_src_dir="${dir}"
                break
            fi
        done
    fi
    
    if [ ! -d "${uboot_src_dir}/configs" ]; then
        display_alert "U-Boot source directory not found" "current: $(pwd)" "warn"
        return 0
    fi
    
    echo "Found U-Boot source directory: ${uboot_src_dir}"
    display_alert "Found U-Boot source" "${uboot_src_dir}" "info"
    
    # 1. 复制 defconfig（如果还没有）
    echo "--- Step 1: Copying defconfig ---"
    if [ ! -f "${uboot_src_dir}/configs/rk3588-microslam_defconfig" ]; then
        # 优先从 patch 目录复制
        if [ -f "${patch_dir}/defconfig/rk3588-microslam_defconfig" ]; then
            cp -f "${patch_dir}/defconfig/rk3588-microslam_defconfig" "${uboot_src_dir}/configs/rk3588-microslam_defconfig"
            display_alert "MicroSLAM U-Boot defconfig copied from patch" "rk3588-microslam_defconfig" "info"
        elif [ -f "${microslam_configs}/rk3588-microslam_defconfig" ]; then
            cp -f "${microslam_configs}/rk3588-microslam_defconfig" "${uboot_src_dir}/configs/rk3588-microslam_defconfig"
            display_alert "MicroSLAM U-Boot defconfig copied" "rk3588-microslam_defconfig" "info"
        fi
    fi
    
    # 2. 复制头文件（如果还没有）
    echo "--- Step 2: Copying header file ---"
    if [ ! -f "${uboot_src_dir}/include/configs/microslam.h" ]; then
        mkdir -p "${uboot_src_dir}/include/configs"
        # 优先从 patch 目录复制
        if [ -f "${patch_dir}/include/configs/microslam.h" ]; then
            cp -f "${patch_dir}/include/configs/microslam.h" "${uboot_src_dir}/include/configs/microslam.h"
            display_alert "MicroSLAM U-Boot header copied from patch" "include/configs/microslam.h" "info"
        elif [ -f "${microslam_configs}/include/configs/microslam.h" ]; then
            cp -f "${microslam_configs}/include/configs/microslam.h" "${uboot_src_dir}/include/configs/microslam.h"
            display_alert "MicroSLAM U-Boot header copied" "include/configs/microslam.h" "info"
        fi
    fi
    
    # 3. 复制板卡目录（如果还没有）
    echo "--- Step 3: Copying board directory ---"
    echo "Checking if board directory exists: ${uboot_src_dir}/board/rockchip/microslam"
    if [ ! -d "${uboot_src_dir}/board/rockchip/microslam" ]; then
        echo "Board directory does not exist, creating it..."
        mkdir -p "${uboot_src_dir}/board/rockchip/microslam"
        # 优先从 patch 目录复制
        if [ -d "${patch_dir}/board/rockchip/microslam" ]; then
            echo "Copying from patch directory: ${patch_dir}/board/rockchip/microslam"
            display_alert "Copying board files from patch" "${patch_dir}/board/rockchip/microslam -> ${uboot_src_dir}/board/rockchip/microslam" "info"
            cp -rf "${patch_dir}/board/rockchip/microslam"/* "${uboot_src_dir}/board/rockchip/microslam/" 2>&1
            local copy_result=$?
            echo "Copy result: ${copy_result}"
            if [ ${copy_result} -eq 0 ]; then
                echo "Board files copied successfully from patch"
                ls -la "${uboot_src_dir}/board/rockchip/microslam/" 2>&1
                display_alert "MicroSLAM U-Boot board directory copied from patch" "board/rockchip/microslam" "info"
            else
                echo "Failed to copy board files from patch"
                display_alert "Failed to copy board files from patch" "${patch_dir}/board/rockchip/microslam" "err"
            fi
        elif [ -d "${microslam_configs}/board/rockchip/microslam" ]; then
            echo "Copying from configs directory: ${microslam_configs}/board/rockchip/microslam"
            display_alert "Copying board files from configs" "${microslam_configs}/board/rockchip/microslam -> ${uboot_src_dir}/board/rockchip/microslam" "info"
            cp -rf "${microslam_configs}/board/rockchip/microslam"/* "${uboot_src_dir}/board/rockchip/microslam/" 2>&1
            local copy_result=$?
            echo "Copy result: ${copy_result}"
            if [ ${copy_result} -eq 0 ]; then
                echo "Board files copied successfully from configs"
                ls -la "${uboot_src_dir}/board/rockchip/microslam/" 2>&1
                display_alert "MicroSLAM U-Boot board directory copied" "board/rockchip/microslam" "info"
            else
                echo "Failed to copy board files from configs"
                display_alert "Failed to copy board files from configs" "${microslam_configs}/board/rockchip/microslam" "err"
            fi
        else
            echo "ERROR: Board directory not found in patch or configs"
            echo "  patch: ${patch_dir}/board/rockchip/microslam"
            echo "  configs: ${microslam_configs}/board/rockchip/microslam"
            display_alert "Board directory not found" "patch: ${patch_dir}/board/rockchip/microslam, configs: ${microslam_configs}/board/rockchip/microslam" "warn"
        fi
    else
        echo "Board directory already exists: ${uboot_src_dir}/board/rockchip/microslam"
        ls -la "${uboot_src_dir}/board/rockchip/microslam/" 2>&1
        display_alert "Board directory already exists" "${uboot_src_dir}/board/rockchip/microslam" "info"
    fi
    
    # 4. 复制 Kconfig 文件（如果需要）
    echo "--- Step 4: Checking Kconfig file ---"
    if [ ! -f "${uboot_src_dir}/arch/arm/mach-rockchip/rk3588/Kconfig" ] || ! grep -q "TARGET_MICROSLAM" "${uboot_src_dir}/arch/arm/mach-rockchip/rk3588/Kconfig" 2>/dev/null; then
        mkdir -p "${uboot_src_dir}/arch/arm/mach-rockchip/rk3588"
        # 优先从 patch 目录复制
        if [ -f "${patch_dir}/arch/arm/mach-rockchip/rk3588/Kconfig" ]; then
            cp -f "${patch_dir}/arch/arm/mach-rockchip/rk3588/Kconfig" "${uboot_src_dir}/arch/arm/mach-rockchip/rk3588/Kconfig"
            display_alert "MicroSLAM U-Boot Kconfig copied from patch" "arch/arm/mach-rockchip/rk3588/Kconfig" "info"
        elif [ -f "${microslam_configs}/arch/arm/mach-rockchip/rk3588/Kconfig" ]; then
            cp -f "${microslam_configs}/arch/arm/mach-rockchip/rk3588/Kconfig" "${uboot_src_dir}/arch/arm/mach-rockchip/rk3588/Kconfig"
            display_alert "MicroSLAM U-Boot Kconfig copied" "arch/arm/mach-rockchip/rk3588/Kconfig" "info"
        fi
    fi
    echo "--- copy_microslam_uboot_files finished ---"
}
EOF
chmod +x "${UBOOT_EXTENSION}"
echo -e "${SUCCESS} 已生成 U-Boot extension: ${UBOOT_EXTENSION}"

# 3.5.1 生成 Loop 设备修复扩展（修复 Docker 容器中分区节点创建问题）
LOOP_FIX_EXTENSION="${ARMBIAN_USERPATCHES}/extensions/microslam-loop-fix.sh"
cat > "${LOOP_FIX_EXTENSION}" << 'EOF'
#!/bin/bash
#================================================================================================
#
# MicroSLAM Loop Device Fix Extension
# 修复 Docker 容器中 loop 设备分区节点创建延迟的问题
# 通过覆盖 check_loop_device_internal 函数来在检查时自动创建分区节点
#
#================================================================================================

# 覆盖 check_loop_device_internal 函数，增强分区节点创建逻辑
function check_loop_device_internal() {
    local device="${1}"
    display_alert "MicroSLAM Loop Fix: Checking loop device" "${device}" "debug"
    
    if [[ ! -b "${device}" ]]; then
        # 检查是否是分区设备（格式：/dev/loopXpY）
        if [[ "${device}" =~ ^/dev/loop[0-9]+p[0-9]+$ ]]; then
            # 这是分区设备，尝试从 /sys/block 获取信息并创建节点
            local loop_base=$(echo "${device}" | sed 's|/dev/||' | sed 's|p[0-9]*$||')
            local part_num=$(echo "${device}" | sed 's|.*p||')
            local loop_device="/dev/${loop_base}"
            
            display_alert "MicroSLAM Loop Fix" "Partition device missing, attempting to create: ${device}" "info"
            
            # 检查主 loop 设备是否存在
            if [ -b "${loop_device}" ]; then
                # 运行 partprobe 确保分区表已读取
                if command -v partprobe >/dev/null 2>&1; then
                    partprobe "${loop_device}" 2>/dev/null || true
                    sleep 0.2  # 等待内核创建设备节点
                fi
                
                # 方法1：从 /sys/block/loopX/loopXpY/dev 读取主次设备号
                local sys_dev_file="/sys/block/${loop_base}/${loop_base}p${part_num}/dev"
                if [ -r "${sys_dev_file}" ]; then
                    local major_minor=$(cat "${sys_dev_file}" 2>/dev/null | tr -d '\n')
                    if [ -n "${major_minor}" ] && [[ "${major_minor}" =~ ^[0-9]+:[0-9]+$ ]]; then
                        local major=$(echo "${major_minor}" | cut -d: -f1)
                        local minor=$(echo "${major_minor}" | cut -d: -f2)
                        display_alert "MicroSLAM Loop Fix" "Creating partition node from /sys: ${device} (${major}:${minor})" "info"
                        mknod -m0660 "${device}" b "${major}" "${minor}" 2>/dev/null || true
                        sleep 0.1  # 等待节点创建完成
                    fi
                fi
                
                # 方法2：如果 /sys 方法失败，尝试从 /tmp/dev 获取（CONTAINER_COMPAT 机制）
                if [ ! -b "${device}" ] && [ -b "/tmp/${device}" ]; then
                    local major=$(stat -c '%t' "/tmp/${device}" 2>/dev/null)
                    local minor=$(stat -c '%T' "/tmp/${device}" 2>/dev/null)
                    if [ -n "${major}" ] && [ -n "${minor}" ]; then
                        display_alert "MicroSLAM Loop Fix" "Creating partition node from /tmp/dev: ${device}" "info"
                        mknod -m0660 "${device}" b "0x${major}" "0x${minor}" 2>/dev/null || true
                        sleep 0.1
                    fi
                fi
                
                # 方法3：从主设备的 /sys/block/loopX/ 目录查找分区
                if [ ! -b "${device}" ]; then
                    # 遍历 /sys/block/loopX/ 下的所有分区目录
                    for part_dir in /sys/block/${loop_base}/${loop_base}p*; do
                        if [ -d "${part_dir}" ]; then
                            local part_name=$(basename "${part_dir}")
                            if [ "${part_name}" = "${loop_base}p${part_num}" ]; then
                                local part_dev_file="${part_dir}/dev"
                                if [ -r "${part_dev_file}" ]; then
                                    local major_minor=$(cat "${part_dev_file}" 2>/dev/null | tr -d '\n')
                                    if [ -n "${major_minor}" ] && [[ "${major_minor}" =~ ^[0-9]+:[0-9]+$ ]]; then
                                        local major=$(echo "${major_minor}" | cut -d: -f1)
                                        local minor=$(echo "${major_minor}" | cut -d: -f2)
                                        display_alert "MicroSLAM Loop Fix" "Creating partition node from /sys (method 3): ${device} (${major}:${minor})" "info"
                                        mknod -m0660 "${device}" b "${major}" "${minor}" 2>/dev/null || true
                                        sleep 0.1
                                        break
                                    fi
                                fi
                            fi
                        fi
                    done
                fi
            fi
        fi
        
        # 原有的 CONTAINER_COMPAT 处理逻辑（用于非分区设备）
        if [[ ! -b "${device}" ]] && [[ $CONTAINER_COMPAT == yes && -b "/tmp/${device}" ]]; then
            display_alert "Creating device node" "${device}"
            run_host_command_logged mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/${device}")" "0x$(stat -c '%T' "/tmp/${device}")"
            if [[ ! -b "${device}" ]]; then
                return 1
            else
                display_alert "Device node created OK" "${device}" "info"
            fi
        elif [[ ! -b "${device}" ]]; then
            # 只有非分区设备或创建失败时才输出调试信息
            if [[ ! "${device}" =~ ^/dev/loop[0-9]+p[0-9]+$ ]]; then
                display_alert "Device node does not exist yet" "${device}" "debug"
            fi
            return 1
        fi
    fi

    # 原有的设备大小检查逻辑
    if [[ "${CHECK_LOOP_FOR_SIZE:-yes}" != "no" ]]; then
        local device_size
        device_size=$(blockdev --getsize64 "${device}" 2>/dev/null || echo "0")
        display_alert "Device node size" "${device}: ${device_size}" "debug"
        if [[ ${device_size} -eq 0 ]]; then
            # only break on the first 3 iterations. then give up; let it try to use the device...
            if [[ ${RETRY_RUNS} -lt 4 ]]; then
                display_alert "Device node exists but is 0-sized; retry ${RETRY_RUNS}" "${device}" "warn"
                return 1
            else
                display_alert "Device node exists but is 0-sized; proceeding anyway" "${device}" "warn"
            fi
        fi
    fi

    return 0
}
EOF
chmod +x "${LOOP_FIX_EXTENSION}"
echo -e "${SUCCESS} 已生成 Loop 设备修复 extension: ${LOOP_FIX_EXTENSION}"

# 3.5.2 生成 Systemd 服务修复扩展（修复 ondemand.service 不存在时的错误）
SYSTEMD_FIX_EXTENSION="${ARMBIAN_USERPATCHES}/extensions/microslam-systemd-fix.sh"
cat > "${SYSTEMD_FIX_EXTENSION}" << 'EOF'
#!/bin/bash
#================================================================================================
#
# MicroSLAM Systemd Service Fix Extension
# 修复 systemd 服务禁用时服务不存在导致的错误
#
#================================================================================================

# 覆盖 disable_systemd_service_sdcard 函数，使其在服务不存在时静默失败
function disable_systemd_service_sdcard() {
    display_alert "Disabling systemd service(s) on target" "${*}" "debug"
    declare service
    for service in "${@}"; do
        # 首先检查服务是否存在
        if chroot_sdcard systemctl list-unit-files --type=service --no-pager --no-legend "${service}" 2>/dev/null | grep -q "^${service}"; then
            # 服务存在，尝试禁用
            display_alert "Disabling systemd service" "${service}" "debug"
            chroot_sdcard systemctl --no-reload disable "${service}" 2>/dev/null || {
                # 如果禁用失败，尝试 mask（更强力的禁用方式）
                display_alert "Disable failed, trying mask" "${service}" "debug"
                chroot_sdcard systemctl --no-reload mask "${service}" 2>/dev/null || true
            }
        else
            # 服务不存在，静默跳过
            display_alert "Systemd service does not exist, skipping" "${service}" "debug"
        fi
    done
}
EOF
chmod +x "${SYSTEMD_FIX_EXTENSION}"
echo -e "${SUCCESS} 已生成 Systemd 服务修复 extension: ${SYSTEMD_FIX_EXTENSION}"

# 3.6 生成 U-Boot defconfig 和头文件 patch（使用 overlay 机制）
# 将 defconfig 和头文件复制到主 patch 目录
# 因为 0000.patching_config.yaml 已经配置了从 defconfig 目录复制文件到 configs/
UBOOT_PATCH_DEFCONFIG_DIR="${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx/defconfig"
UBOOT_PATCH_DT_DIR="${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx/dt"
UBOOT_USERPATCH_DEFCONFIG_DIR="${ARMBIAN_USERPATCHES}/patch/u-boot/legacy/u-boot-radxa-rk35xx/defconfig"

if [ -f "${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig" ]; then
    # 确保主 patch 目录的 defconfig 子目录存在
    mkdir -p "${UBOOT_PATCH_DEFCONFIG_DIR}"
    
    # 复制 defconfig 到主 patch 目录（Armbian 的 patch 系统会从这里复制）
    if cp -f "${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig" "${UBOOT_PATCH_DEFCONFIG_DIR}/rk3588-microslam_defconfig" 2>/dev/null; then
        echo -e "${SUCCESS} 已复制 U-Boot defconfig 到主 patch 目录: ${UBOOT_PATCH_DEFCONFIG_DIR}/rk3588-microslam_defconfig"
    else
        # 如果权限不足，复制到 userpatches 目录
        mkdir -p "${UBOOT_USERPATCH_DEFCONFIG_DIR}"
        cp -f "${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig" "${UBOOT_USERPATCH_DEFCONFIG_DIR}/rk3588-microslam_defconfig"
        echo -e "${SUCCESS} 已复制 U-Boot defconfig 到 userpatches 目录: ${UBOOT_USERPATCH_DEFCONFIG_DIR}/rk3588-microslam_defconfig"
        echo -e "${INFO} 注意：Armbian patch 系统会自动合并 userpatches 和主 patch 目录"
    fi
else
    echo -e "${WARNING} U-Boot defconfig 源文件不存在，跳过 patch 生成"
fi

# 复制 U-Boot 头文件、板卡目录和 Kconfig 文件（通过 overlay 机制）
UBOOT_PATCH_INCLUDE_DIR="${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx/include"
UBOOT_PATCH_BOARD_DIR="${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx/board"
UBOOT_PATCH_ARCH_DIR="${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx/arch"

# 复制头文件
if [ -f "${CONFIGS_DIR}/uboot/include/configs/microslam.h" ]; then
    mkdir -p "${UBOOT_PATCH_INCLUDE_DIR}/configs"
    
    if cp -f "${CONFIGS_DIR}/uboot/include/configs/microslam.h" "${UBOOT_PATCH_INCLUDE_DIR}/configs/microslam.h" 2>/dev/null; then
        echo -e "${SUCCESS} 已复制 U-Boot 头文件到 patch 目录: ${UBOOT_PATCH_INCLUDE_DIR}/configs/microslam.h"
    else
        echo -e "${WARNING} 无法复制 U-Boot 头文件到 patch 目录（权限不足）"
    fi
fi

# 复制板卡目录
if [ -d "${CONFIGS_DIR}/uboot/board/rockchip/microslam" ]; then
    mkdir -p "${UBOOT_PATCH_BOARD_DIR}/rockchip/microslam"
    
    if cp -f "${CONFIGS_DIR}/uboot/board/rockchip/microslam"/* "${UBOOT_PATCH_BOARD_DIR}/rockchip/microslam/" 2>/dev/null; then
        echo -e "${SUCCESS} 已复制 U-Boot 板卡目录到 patch 目录: ${UBOOT_PATCH_BOARD_DIR}/rockchip/microslam"
    else
        echo -e "${WARNING} 无法复制 U-Boot 板卡目录到 patch 目录（权限不足）"
    fi
fi

# 复制 rk3588/Kconfig 文件（包含 TARGET_MICROSLAM 定义）
if [ -f "${CONFIGS_DIR}/uboot/arch/arm/mach-rockchip/rk3588/Kconfig" ]; then
    mkdir -p "${UBOOT_PATCH_ARCH_DIR}/arm/mach-rockchip/rk3588"
    
    if cp -f "${CONFIGS_DIR}/uboot/arch/arm/mach-rockchip/rk3588/Kconfig" "${UBOOT_PATCH_ARCH_DIR}/arm/mach-rockchip/rk3588/Kconfig" 2>/dev/null; then
        echo -e "${SUCCESS} 已复制 U-Boot Kconfig 文件到 patch 目录: ${UBOOT_PATCH_ARCH_DIR}/arm/mach-rockchip/rk3588/Kconfig"
    else
        echo -e "${WARNING} 无法复制 U-Boot Kconfig 文件到 patch 目录（权限不足）"
    fi
fi

# 复制 U-Boot DTS 文件
if [ -f "${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts" ]; then
    mkdir -p "${UBOOT_PATCH_DT_DIR}"
    
    if cp -f "${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts" "${UBOOT_PATCH_DT_DIR}/rk3588-microslam.dts" 2>/dev/null; then
        echo -e "${SUCCESS} 已复制 U-Boot DTS 文件到 patch 目录: ${UBOOT_PATCH_DT_DIR}/rk3588-microslam.dts"
    else
        # 如果权限不足，复制到 userpatches 目录
        UBOOT_USERPATCH_DT_DIR="${ARMBIAN_USERPATCHES}/patch/u-boot/legacy/u-boot-radxa-rk35xx/dt"
        mkdir -p "${UBOOT_USERPATCH_DT_DIR}"
        cp -f "${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts" "${UBOOT_USERPATCH_DT_DIR}/rk3588-microslam.dts"
        echo -e "${SUCCESS} 已复制 U-Boot DTS 文件到 userpatches 目录: ${UBOOT_USERPATCH_DT_DIR}/rk3588-microslam.dts"
        echo -e "${INFO} 注意：Armbian patch 系统会自动合并 userpatches 和主 patch 目录"
    fi
else
    echo -e "${WARNING} U-Boot DTS 源文件不存在: ${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts"
fi

# 更新 0000.patching_config.yaml 以包含 MicroSLAM 的 overlay
# 将 overlay 配置合并到主配置文件中，确保被正确应用
UBOOT_PATCH_MAIN_YAML="${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx/0000.patching_config.yaml"
if [ -f "${UBOOT_PATCH_MAIN_YAML}" ]; then
    # 检查是否已经包含我们的 overlay
    if ! grep -q "include.*configs\|board.*rockchip.*microslam\|arch.*mach-rockchip.*rk3588" "${UBOOT_PATCH_MAIN_YAML}" 2>/dev/null; then
        # 使用 Python 或 sed 更新 YAML 文件，添加我们的 overlay
        python3 << EOF
import yaml
import sys

yaml_file = "${UBOOT_PATCH_MAIN_YAML}"
with open(yaml_file, 'r') as f:
    config = yaml.safe_load(f) or {}

if 'config' not in config:
    config['config'] = {}

if 'overlay-directories' not in config['config']:
    config['config']['overlay-directories'] = []

# 添加 MicroSLAM 的 overlay
overlays = config['config']['overlay-directories']
new_overlays = [
    {'source': 'include', 'target': 'include'},
    {'source': 'board', 'target': 'board'},
    {'source': 'arch', 'target': 'arch'}
]

# 检查是否已存在，避免重复
for new_ov in new_overlays:
    if new_ov not in overlays:
        overlays.append(new_ov)

with open(yaml_file, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)
EOF
        if [ $? -eq 0 ]; then
            echo -e "${SUCCESS} 已更新主 patch 配置文件，添加 MicroSLAM overlay"
        else
            echo -e "${WARNING} 无法更新主 patch 配置文件，将创建单独的配置文件"
            # 如果 Python 更新失败，创建单独的配置文件
            UBOOT_PATCH_INCLUDE_YAML="${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx/0002-microslam-header.patching_config.yaml"
            cat > "${UBOOT_PATCH_INCLUDE_YAML}" << 'EOF'
config:
  # MicroSLAM U-Boot header, board and Kconfig overlay
  overlay-directories:
    - { source: "include", target: "include" } # copies include/configs/microslam.h to include/configs/ in the u-boot source tree
    - { source: "board", target: "board" } # copies board/rockchip/microslam to board/rockchip/ in the u-boot source tree
    - { source: "arch", target: "arch" } # copies arch/arm/mach-rockchip/rk3588/Kconfig to arch/arm/mach-rockchip/rk3588/ in the u-boot source tree
EOF
            echo -e "${SUCCESS} 已创建单独的 U-Boot overlay 配置文件"
        fi
    else
        echo -e "${INFO} 主 patch 配置文件已包含 MicroSLAM overlay，跳过更新"
    fi
else
    echo -e "${WARNING} 主 patch 配置文件不存在，创建新的配置文件"
    cat > "${UBOOT_PATCH_MAIN_YAML}" << 'EOF'
config:
  overlay-directories:
    - { source: "defconfig", target: "configs" }
    - { source: "dt", target: "arch/arm/dts" }
    - { source: "include", target: "include" }
    - { source: "board", target: "board" }
    - { source: "arch", target: "arch" }
EOF
    echo -e "${SUCCESS} 已创建主 patch 配置文件"
fi

# ============================================================================
# 第四部分：准备 configs 目录链接供构建系统使用
# ============================================================================
echo -e "${INFO} [4/4] 准备 configs 目录链接..."

if [ -d "${CONFIGS_DIR}" ]; then
    # 在 armbian-build 目录创建 configs 链接，以便在 chroot 环境中访问
    if [ ! -L "${ARMBIAN_DIR}/MicroSLAM-SDK" ] && [ ! -d "${ARMBIAN_DIR}/MicroSLAM-SDK" ]; then
        ln -sf "${PROJECT_ROOT}" "${ARMBIAN_DIR}/MicroSLAM-SDK" 2>/dev/null || \
        cp -r "${CONFIGS_DIR}" "${ARMBIAN_DIR}/MicroSLAM-configs" 2>/dev/null || true
        echo -e "${SUCCESS} 已创建 configs 目录链接"
    else
        echo -e "${INFO} configs 目录链接已存在"
    fi
fi

echo -e "${SUCCESS} MicroSLAM 补丁和配置应用完成"
