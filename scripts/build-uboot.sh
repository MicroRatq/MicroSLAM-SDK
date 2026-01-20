#!/bin/bash
#================================================================================================
#
# MicroSLAM U-Boot Build Script
# U-Boot独立构建脚本，包括源码初始化、配置应用、交叉编译、输出生成
# 实现基于make的增量构建（通过控制是否执行make clean）
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 路径配置
UBOOT_REPO="https://github.com/radxa/u-boot.git"
UBOOT_BRANCH="next-dev-v2024.10"
UBOOT_DIR="${PROJECT_ROOT}/repos/u-boot-radxa"
ARMBIAN_DIR="${PROJECT_ROOT}/repos/armbian-build"
CONFIGS_DIR="${PROJECT_ROOT}/configs"
OUTPUT_DIR="${PROJECT_ROOT}/output/uboot"

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

# 默认参数
INCREMENTAL_BUILD_UBOOT="${INCREMENTAL_BUILD_UBOOT:-no}"
# 对于Intel 14代CPU等硬件，使用CPU核心数而不是nproc（避免段错误）
if [ -z "${CPUTHREADS}" ]; then
    if command -v nproc >/dev/null 2>&1; then
        CPU_CORES=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
    else
        CPU_CORES=4
    fi
    # 使用核心数作为默认值（更保守，避免段错误）
    CPUTHREADS="${CPU_CORES}"
fi

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --incremental)
            INCREMENTAL_BUILD_UBOOT="yes"
            echo -e "${INFO} 增量构建模式：跳过 make clean"
            shift
            ;;
        -j|--threads)
            CPUTHREADS="$2"
            echo -e "${INFO} 设置编译线程数为: ${CPUTHREADS}"
            shift 2
            ;;
        *)
            echo -e "${WARNING} 未知参数: $1"
            shift
            ;;
    esac
done

echo -e "${STEPS} 开始构建MicroSLAM U-Boot..."

# 1. 初始化U-Boot源码仓库
echo -e "${INFO} 检查U-Boot源码仓库..."
if [ ! -d "${UBOOT_DIR}" ]; then
    echo -e "${INFO} U-Boot仓库不存在，开始clone..."
    mkdir -p "${PROJECT_ROOT}/repos"
    git clone --depth=1 --branch="${UBOOT_BRANCH}" "${UBOOT_REPO}" "${UBOOT_DIR}"
    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} U-Boot仓库clone完成"
    else
        echo -e "${ERROR} U-Boot仓库clone失败"
        exit 1
    fi
else
    echo -e "${INFO} U-Boot仓库已存在，更新到最新版本..."
    cd "${UBOOT_DIR}"
    git fetch origin "${UBOOT_BRANCH}"
    git checkout "${UBOOT_BRANCH}"
    git pull origin "${UBOOT_BRANCH}" || true
fi

# 2. 检查交叉编译工具链
echo -e "${INFO} 检查交叉编译工具链..."
if [ -z "${CROSS_COMPILE}" ]; then
    # 尝试从Armbian工具链获取
    if [ -d "${ARMBIAN_DIR}/cache/tools" ]; then
        TOOLCHAIN_DIR=$(find "${ARMBIAN_DIR}/cache/tools" -type d -name "aarch64-linux-gnu-gcc*" -o -name "gcc-arm-*" | head -1)
        if [ -n "${TOOLCHAIN_DIR}" ]; then
            TOOLCHAIN_BIN="${TOOLCHAIN_DIR}/bin"
            if [ -f "${TOOLCHAIN_BIN}/aarch64-linux-gnu-gcc" ]; then
                export PATH="${TOOLCHAIN_BIN}:${PATH}"
                export CROSS_COMPILE="aarch64-linux-gnu-"
                echo -e "${SUCCESS} 使用Armbian工具链: ${TOOLCHAIN_BIN}"
            fi
        fi
    fi
    
    # 如果还是找不到，尝试系统工具链
    if [ -z "${CROSS_COMPILE}" ]; then
        if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
            export CROSS_COMPILE="aarch64-linux-gnu-"
            echo -e "${SUCCESS} 使用系统工具链"
        else
            echo -e "${ERROR} 未找到交叉编译工具链，请安装 aarch64-linux-gnu-gcc"
            exit 1
        fi
    fi
else
    echo -e "${INFO} 使用指定的交叉编译工具链: ${CROSS_COMPILE}"
fi

# 3. 应用MicroSLAM配置
echo -e "${INFO} 应用MicroSLAM配置..."
cd "${UBOOT_DIR}"

# 3.1 复制defconfig
if [ -f "${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig" ]; then
    cp -f "${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig" "${UBOOT_DIR}/configs/rk3588-microslam_defconfig"
    echo -e "${SUCCESS} 复制defconfig完成"
else
    echo -e "${ERROR} 未找到defconfig文件: ${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig"
    exit 1
fi

# 3.2 复制头文件
if [ -f "${CONFIGS_DIR}/uboot/include/configs/microslam.h" ]; then
    mkdir -p "${UBOOT_DIR}/include/configs"
    cp -f "${CONFIGS_DIR}/uboot/include/configs/microslam.h" "${UBOOT_DIR}/include/configs/microslam.h"
    echo -e "${SUCCESS} 复制头文件完成"
fi

# 3.3 复制board目录
if [ -d "${CONFIGS_DIR}/uboot/board/rockchip/microslam" ]; then
    mkdir -p "${UBOOT_DIR}/board/rockchip/microslam"
    cp -rf "${CONFIGS_DIR}/uboot/board/rockchip/microslam"/* "${UBOOT_DIR}/board/rockchip/microslam/"
    echo -e "${SUCCESS} 复制board目录完成"
fi

# 3.4 复制DTS文件
if [ -f "${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts" ]; then
    mkdir -p "${UBOOT_DIR}/arch/arm/dts"
    cp -f "${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts" "${UBOOT_DIR}/arch/arm/dts/rk3588-microslam.dts"
    echo -e "${SUCCESS} 复制DTS文件完成"
fi

# 3.5 复制Kconfig修改
if [ -f "${CONFIGS_DIR}/uboot/arch/arm/mach-rockchip/rk3588/Kconfig" ]; then
    mkdir -p "${UBOOT_DIR}/arch/arm/mach-rockchip/rk3588"
    cp -f "${CONFIGS_DIR}/uboot/arch/arm/mach-rockchip/rk3588/Kconfig" "${UBOOT_DIR}/arch/arm/mach-rockchip/rk3588/Kconfig"
    echo -e "${SUCCESS} 复制Kconfig完成"
fi

# 4. 应用Armbian的U-Boot patch（如果存在）
if [ -d "${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx" ]; then
    echo -e "${INFO} 应用Armbian U-Boot patch..."
    # 这里可以添加patch应用逻辑，如果需要的话
    # 目前配置已经通过复制文件的方式应用了
fi

# 5. 增量构建判断
if [ "${INCREMENTAL_BUILD_UBOOT}" != "yes" ]; then
    echo -e "${INFO} 全量构建：执行 make clean"
    make CROSS_COMPILE=${CROSS_COMPILE} clean || true
else
    echo -e "${INFO} 增量构建：跳过 make clean"
fi

# 6. 配置U-Boot
echo -e "${INFO} 配置U-Boot..."
make CROSS_COMPILE=${CROSS_COMPILE} rk3588-microslam_defconfig
if [ $? -ne 0 ]; then
    echo -e "${ERROR} U-Boot配置失败"
    exit 1
fi

# 7. 编译U-Boot
echo -e "${INFO} 开始编译U-Boot（线程数: ${CPUTHREADS}）..."
make CROSS_COMPILE=${CROSS_COMPILE} -j${CPUTHREADS}
if [ $? -ne 0 ]; then
    echo -e "${ERROR} U-Boot编译失败"
    exit 1
fi

# 7.5 生成u-boot.itb（FIT镜像）
echo -e "${INFO} 生成 u-boot.itb..."
make CROSS_COMPILE=${CROSS_COMPILE} u-boot.itb
if [ $? -ne 0 ]; then
    echo -e "${WARNING} u-boot.itb 生成失败，继续..."
fi

# 8. 生成输出文件
echo -e "${INFO} 生成输出文件..."
mkdir -p "${OUTPUT_DIR}"

# 查找生成的二进制文件
if [ -f "${UBOOT_DIR}/u-boot.itb" ]; then
    cp -f "${UBOOT_DIR}/u-boot.itb" "${OUTPUT_DIR}/u-boot.itb"
    echo -e "${SUCCESS} 复制 u-boot.itb 到 ${OUTPUT_DIR}"
fi

# 查找idbloader.img（可能在tools目录或其他位置）
if [ -f "${UBOOT_DIR}/idbloader.img" ]; then
    cp -f "${UBOOT_DIR}/idbloader.img" "${OUTPUT_DIR}/idbloader.img"
    echo -e "${SUCCESS} 复制 idbloader.img 到 ${OUTPUT_DIR}"
fi

# 查找其他可能的输出文件
for file in "${UBOOT_DIR}"/*.img "${UBOOT_DIR}"/*.bin; do
    if [ -f "${file}" ]; then
        filename=$(basename "${file}")
        cp -f "${file}" "${OUTPUT_DIR}/${filename}"
        echo -e "${INFO} 复制 ${filename} 到 ${OUTPUT_DIR}"
    fi
done

# 9. 检查输出
if [ -f "${OUTPUT_DIR}/u-boot.itb" ]; then
    echo -e "${SUCCESS} U-Boot构建完成！"
    echo -e "${INFO} 输出文件位置: ${OUTPUT_DIR}"
    ls -lh "${OUTPUT_DIR}"/*.itb "${OUTPUT_DIR}"/*.img 2>/dev/null || true
else
    echo -e "${WARNING} 未找到 u-boot.itb，请检查构建日志"
fi

echo -e "${SUCCESS} U-Boot构建流程完成"
