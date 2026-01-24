#!/bin/bash
#================================================================================================
#
# clean-cache.sh — 清理构建缓存
# 从 output、armbian-build/cache、.tmp 及对应 git 仓库清理；由 build.sh 通过
# docker compose run --rm --user root microslam-builder 在容器内调用。
# 参数: --all | -u | -k | -f（可组合 -u/-k/-f）；未传 --all 且未传 -u/-k/-f 时视作 --all。
#
#================================================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/output"

source "${SCRIPT_DIR}/common.sh"

CLEAN_ALL="no"
CLEAN_UBOOT="no"
CLEAN_KERNEL="no"
CLEAN_ROOTFS="no"

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            CLEAN_ALL="yes"
            shift
            ;;
        -u)
            CLEAN_UBOOT="yes"
            shift
            ;;
        -k)
            CLEAN_KERNEL="yes"
            shift
            ;;
        -f)
            CLEAN_ROOTFS="yes"
            shift
            ;;
        *)
            echo -e "${WARNING} 未知参数: $1，忽略"
            shift
            ;;
    esac
done

# 若未传 --all 且也未传 -u/-k/-f，则视作 --all
if [ "${CLEAN_ALL}" = "no" ] && [ "${CLEAN_UBOOT}" = "no" ] && [ "${CLEAN_KERNEL}" = "no" ] && [ "${CLEAN_ROOTFS}" = "no" ]; then
    CLEAN_ALL="yes"
fi

echo -e "${STEPS} ========================================"
echo -e "${STEPS} 清理缓存"
echo -e "${STEPS} ========================================"

if [ "${CLEAN_ALL}" = "yes" ]; then
    # 清理所有缓存
    echo -e "${INFO} 清理所有缓存..."

    # 清理输出目录
    if [ -d "${OUTPUT_DIR}" ]; then
        rm -rf "${OUTPUT_DIR}"/*
        echo -e "${SUCCESS} 输出目录已清理"
    fi

    # 清理 Armbian 缓存（保留 tools 目录）
    if [ -d "${PROJECT_ROOT}/repos/armbian-build/cache" ]; then
        find "${PROJECT_ROOT}/repos/armbian-build/cache" -mindepth 1 -maxdepth 1 ! -name "tools" -exec rm -rf {} + 2>/dev/null || true
        echo -e "${SUCCESS} Armbian 缓存已清理（保留 tools 目录）"
    fi

    # 清理临时目录
    if [ -d "${PROJECT_ROOT}/.tmp" ]; then
        rm -rf "${PROJECT_ROOT}/.tmp"/*
        echo -e "${SUCCESS} 临时目录已清理"
    fi

    # 重置 git 仓库到原始状态
    echo -e "${INFO} 重置 git 仓库到原始状态..."

    # 重置 armbian-build
    if [ -d "${PROJECT_ROOT}/repos/armbian-build/.git" ]; then
        cd "${PROJECT_ROOT}/repos/armbian-build"
        git fetch origin 2>/dev/null || true
        current_branch=$(git branch --show-current 2>/dev/null || echo "main")
        git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
        git clean -fd 2>/dev/null || true
        echo -e "${SUCCESS} armbian-build 仓库已重置"
    fi

    # 重置 u-boot
    if [ -d "${PROJECT_ROOT}/repos/u-boot/.git" ]; then
        cd "${PROJECT_ROOT}/repos/u-boot"
        git fetch origin 2>/dev/null || true
        current_branch=$(git branch --show-current 2>/dev/null || echo "next-dev-v2024.10")
        git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
        git clean -fd 2>/dev/null || true
        echo -e "${SUCCESS} u-boot 仓库已重置"
    fi

    # 重置 linux-6.1.y-rockchip
    if [ -d "${PROJECT_ROOT}/repos/linux-6.1.y-rockchip/.git" ]; then
        cd "${PROJECT_ROOT}/repos/linux-6.1.y-rockchip"
        git fetch origin 2>/dev/null || true
        current_branch=$(git branch --show-current 2>/dev/null || echo "6.1.y-rockchip")
        git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
        git clean -fd 2>/dev/null || true
        echo -e "${SUCCESS} linux-6.1.y-rockchip 仓库已重置"
    fi
else
    # 指定组件：仅清理对应组件的缓存
    if [ "${CLEAN_UBOOT}" = "yes" ]; then
        echo -e "${INFO} 清理 U-Boot 缓存..."
        if [ -d "${OUTPUT_DIR}/uboot" ]; then
            rm -rf "${OUTPUT_DIR}/uboot"/*
            echo -e "${SUCCESS} U-Boot 输出目录已清理"
        fi
        if [ -d "${PROJECT_ROOT}/repos/u-boot/.git" ]; then
            cd "${PROJECT_ROOT}/repos/u-boot"
            git fetch origin 2>/dev/null || true
            current_branch=$(git branch --show-current 2>/dev/null || echo "next-dev-v2024.10")
            git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
            git clean -fd 2>/dev/null || true
            echo -e "${SUCCESS} u-boot 仓库已重置"
        fi
    fi

    if [ "${CLEAN_KERNEL}" = "yes" ]; then
        echo -e "${INFO} 清理 Kernel 缓存..."
        if [ -d "${OUTPUT_DIR}/kernel" ]; then
            rm -rf "${OUTPUT_DIR}/kernel"/*
            echo -e "${SUCCESS} Kernel 输出目录已清理"
        fi
        if [ -d "${PROJECT_ROOT}/repos/linux-6.1.y-rockchip/.git" ]; then
            cd "${PROJECT_ROOT}/repos/linux-6.1.y-rockchip"
            git fetch origin 2>/dev/null || true
            current_branch=$(git branch --show-current 2>/dev/null || echo "6.1.y-rockchip")
            git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
            git clean -fd 2>/dev/null || true
            echo -e "${SUCCESS} linux-6.1.y-rockchip 仓库已重置"
        fi
    fi

    if [ "${CLEAN_ROOTFS}" = "yes" ]; then
        echo -e "${INFO} 清理 RootFS 缓存..."
        if [ -d "${OUTPUT_DIR}/rootfs" ]; then
            rm -rf "${OUTPUT_DIR}/rootfs"/*
            echo -e "${SUCCESS} RootFS 输出目录已清理"
        fi
        # 清理 Armbian rootfs 缓存
        if [ -d "${PROJECT_ROOT}/repos/armbian-build/cache/rootfs" ]; then
            rm -rf "${PROJECT_ROOT}/repos/armbian-build/cache/rootfs"/*
            echo -e "${SUCCESS} Armbian rootfs 缓存已清理"
        fi
        if [ -d "${PROJECT_ROOT}/repos/armbian-build/.git" ]; then
            cd "${PROJECT_ROOT}/repos/armbian-build"
            git fetch origin 2>/dev/null || true
            current_branch=$(git branch --show-current 2>/dev/null || echo "main")
            git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
            git clean -fd 2>/dev/null || true
            echo -e "${SUCCESS} armbian-build 仓库已重置"
        fi
    fi
fi

echo -e "${SUCCESS} 缓存清理完成！"
