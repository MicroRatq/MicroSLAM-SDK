#!/bin/bash
#================================================================================================
#
# MicroSLAM Repository Initialization Script
# 初始化被引用的仓库，如果不存在则从GitHub clone
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 仓库配置
ARMBIAN_REPO="https://github.com/armbian/build.git"
ARMBIAN_DIR="${PROJECT_ROOT}/repos/armbian-build"
KERNEL_REPO="https://github.com/unifreq/linux-6.1.y-rockchip.git"
KERNEL_DIR="${PROJECT_ROOT}/repos/linux-6.1.y-rockchip"
UBOOT_REPO="https://github.com/radxa/u-boot.git"
UBOOT_BRANCH="next-dev-v2024.10"
UBOOT_DIR="${PROJECT_ROOT}/repos/u-boot"
RKBIN_REPO="https://github.com/armbian/rkbin.git"
RKBIN_DIR="${PROJECT_ROOT}/repos/rkbin"

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"

echo -e "${STEPS} 开始初始化仓库..."

# 创建repos目录
mkdir -p "${PROJECT_ROOT}/repos"
cd "${PROJECT_ROOT}/repos"

# 检查并clone armbian/build仓库
if [ ! -d "${ARMBIAN_DIR}" ]; then
    echo -e "${INFO} armbian/build 仓库不存在，开始clone..."
    git clone "${ARMBIAN_REPO}" armbian-build
    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} armbian/build 仓库clone完成"
    else
        echo -e "${ERROR} armbian/build 仓库clone失败"
        exit 1
    fi
else
    echo -e "${INFO} armbian/build 仓库已存在，跳过clone"
fi

# 检查并clone linux-6.1.y-rockchip仓库
if [ ! -d "${KERNEL_DIR}" ]; then
    echo -e "${INFO} linux-6.1.y-rockchip 仓库不存在，开始clone..."
    git clone "${KERNEL_REPO}" linux-6.1.y-rockchip
    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} linux-6.1.y-rockchip 仓库clone完成"
    else
        echo -e "${ERROR} linux-6.1.y-rockchip 仓库clone失败"
        exit 1
    fi
else
    echo -e "${INFO} linux-6.1.y-rockchip 仓库已存在，跳过clone"
fi

# 检查并clone u-boot仓库
if [ ! -d "${UBOOT_DIR}" ]; then
    echo -e "${INFO} u-boot 仓库不存在，开始clone..."
    git clone --depth=1 --branch="${UBOOT_BRANCH}" "${UBOOT_REPO}" u-boot
    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} u-boot 仓库clone完成"
    else
        echo -e "${ERROR} u-boot 仓库clone失败"
        exit 1
    fi
else
    echo -e "${INFO} u-boot 仓库已存在，跳过clone"
fi

# 检查并clone rkbin仓库
if [ ! -d "${RKBIN_DIR}" ]; then
    echo -e "${INFO} rkbin 仓库不存在，开始clone..."
    git clone "${RKBIN_REPO}" rkbin
    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} rkbin 仓库clone完成"
    else
        echo -e "${ERROR} rkbin 仓库clone失败"
        exit 1
    fi
else
    echo -e "${INFO} rkbin 仓库已存在，跳过clone"
fi

echo -e "${SUCCESS} 仓库初始化完成"
