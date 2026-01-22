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
UBOOT_DIR="${PROJECT_ROOT}/repos/u-boot"
ARMBIAN_DIR="${PROJECT_ROOT}/repos/armbian-build"
RKBIN_DIR="${PROJECT_ROOT}/repos/rkbin"
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

# 3. 检查 rkbin 目录
echo -e "${INFO} 检查 rkbin 目录..."
if [ ! -d "${RKBIN_DIR}" ]; then
    echo -e "${ERROR} rkbin 目录不存在: ${RKBIN_DIR}"
    echo -e "${ERROR} 请先运行 ./scripts/init-repos.sh 初始化仓库"
    exit 1
fi
echo -e "${SUCCESS} rkbin 目录检查通过"

# 4. 应用 ddrbin_param.txt 配置
echo -e "${INFO} 应用 ddrbin_param.txt 配置..."
if [ -f "${CONFIGS_DIR}/rkbin/ddrbin_param.txt" ]; then
    mkdir -p "${RKBIN_DIR}/tools"
    cp -f "${CONFIGS_DIR}/rkbin/ddrbin_param.txt" "${RKBIN_DIR}/tools/ddrbin_param.txt"
    echo -e "${SUCCESS} ddrbin_param.txt 配置已应用"
else
    echo -e "${WARNING} 未找到 ddrbin_param.txt 配置文件: ${CONFIGS_DIR}/rkbin/ddrbin_param.txt"
fi

# 5. 应用U-Boot配置（基于 nanopct6，最小化结构）
echo -e "${INFO} 应用U-Boot配置..."
cd "${UBOOT_DIR}"

# 5.1 复制defconfig
if [ -f "${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig" ]; then
    cp -f "${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig" "${UBOOT_DIR}/configs/rk3588-microslam_defconfig"
    echo -e "${SUCCESS} 复制defconfig完成"
else
    echo -e "${ERROR} 未找到defconfig文件: ${CONFIGS_DIR}/uboot/rk3588-microslam_defconfig"
    exit 1
fi

# 5.2 复制DTS文件
if [ -f "${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts" ]; then
    mkdir -p "${UBOOT_DIR}/arch/arm/dts"
    cp -f "${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts" "${UBOOT_DIR}/arch/arm/dts/rk3588-microslam.dts"
    echo -e "${SUCCESS} 复制DTS文件完成"
else
    echo -e "${WARNING} 未找到DTS文件: ${CONFIGS_DIR}/uboot/dts/rk3588-microslam.dts"
fi

# 6. 应用Armbian的U-Boot patch（如果存在）
if [ -d "${ARMBIAN_DIR}/patch/u-boot/legacy/u-boot-radxa-rk35xx" ]; then
    echo -e "${INFO} 应用Armbian U-Boot patch..."
    # 这里可以添加patch应用逻辑，如果需要的话
    # 目前配置已经通过复制文件的方式应用了
fi

# 7. 增量构建判断
if [ "${INCREMENTAL_BUILD_UBOOT}" != "yes" ]; then
    echo -e "${INFO} 全量构建：执行 make clean"
    make CROSS_COMPILE=${CROSS_COMPILE} clean || true
else
    echo -e "${INFO} 增量构建：跳过 make clean"
fi

# 8. 配置U-Boot
echo -e "${INFO} 配置U-Boot..."
make CROSS_COMPILE=${CROSS_COMPILE} rk3588-microslam_defconfig
if [ $? -ne 0 ]; then
    echo -e "${ERROR} U-Boot配置失败"
    exit 1
fi

# 9. 准备 BL31 固件（用于生成 u-boot.itb）
echo -e "${INFO} 准备 BL31 固件..."
cd "${UBOOT_DIR}"

# 查找 rkbin 中的 BL31 文件（与 nanopct6 一致，使用 v1.48，如果不存在则使用最新版本）
# 注意：Armbian rkbin 仓库结构是 rk35/ 而不是 bin/rk35/
BL31_ELF=$(find "${RKBIN_DIR}/rk35" -name "rk3588_bl31_v1.48.elf" 2>/dev/null | head -1)

# 如果 v1.48 不存在，尝试查找最新版本
if [ -z "${BL31_ELF}" ] || [ ! -f "${BL31_ELF}" ]; then
    BL31_ELF=$(find "${RKBIN_DIR}/rk35" -name "rk3588_bl31_*.elf" 2>/dev/null | sort -V | tail -1)
fi

if [ -z "${BL31_ELF}" ] || [ ! -f "${BL31_ELF}" ]; then
    echo -e "${ERROR} 未找到 BL31 固件: ${RKBIN_DIR}/rk35/rk3588_bl31_*.elf"
    echo -e "${ERROR} 请检查 rkbin 仓库是否正确初始化"
    echo -e "${ERROR} 期望的 BL31 版本: rk3588_bl31_v1.48.elf (与 nanopct6 一致)"
    echo -e "${ERROR} 如果 v1.48 不存在，将使用最新可用版本"
    exit 1
fi

# 复制 BL31 文件到 U-Boot 目录（decode_bl31.py 需要 bl31.elf）
cp -f "${BL31_ELF}" "${UBOOT_DIR}/bl31.elf"
echo -e "${SUCCESS} BL31 固件已准备: ${BL31_ELF}"

# 10. 编译U-Boot
echo -e "${INFO} 开始编译U-Boot（线程数: ${CPUTHREADS}）..."
make CROSS_COMPILE=${CROSS_COMPILE} -j${CPUTHREADS}
if [ $? -ne 0 ]; then
    echo -e "${ERROR} U-Boot编译失败"
    exit 1
fi

# 11. 生成u-boot.itb（FIT镜像）
echo -e "${INFO} 生成 u-boot.itb..."
make CROSS_COMPILE=${CROSS_COMPILE} u-boot.itb
if [ $? -ne 0 ]; then
    echo -e "${WARNING} u-boot.itb 生成失败，继续..."
fi

# 12. 生成 idbloader.img（使用 rkbin 的 ddr.bin 和 spl.bin）
echo -e "${INFO} 生成 idbloader.img..."
cd "${UBOOT_DIR}"

# 查找 rkbin 中的 ddr.bin 和 spl.bin
# 注意：Armbian rkbin 仓库结构是 rk35/ 而不是 bin/rk35/
DDR_BIN=$(find "${RKBIN_DIR}/rk35" -name "rk3588_ddr_*.bin" 2>/dev/null | grep -v eyescan | head -1)
SPL_BIN=$(find "${RKBIN_DIR}/rk35" -name "rk3588_spl_*.bin" 2>/dev/null | head -1)

if [ -z "${DDR_BIN}" ] || [ -z "${SPL_BIN}" ]; then
    echo -e "${ERROR} 未找到 rkbin 的 ddr.bin 或 spl.bin"
    echo -e "${ERROR} 请检查 rkbin 仓库是否正确初始化: ${RKBIN_DIR}/rk35/"
    if [ -z "${DDR_BIN}" ]; then
        echo -e "${ERROR} 未找到 ddr.bin 文件"
    fi
    if [ -z "${SPL_BIN}" ]; then
        echo -e "${ERROR} 未找到 spl.bin 文件"
    fi
    exit 1
fi

echo -e "${INFO} 使用 rkbin 的 ddr.bin 和 spl.bin"
echo -e "${INFO} DDR bin: ${DDR_BIN}"
echo -e "${INFO} SPL bin: ${SPL_BIN}"

# 使用 U-Boot 的 mkimage 工具生成 idbloader.img（使用 : 分隔符一次性生成）
if [ ! -f "${UBOOT_DIR}/tools/mkimage" ]; then
    echo -e "${ERROR} 未找到 mkimage 工具: ${UBOOT_DIR}/tools/mkimage"
    exit 1
fi

"${UBOOT_DIR}/tools/mkimage" -T rksd -n rk3588 -d "${DDR_BIN}:${SPL_BIN}" idbloader.img
if [ $? -ne 0 ]; then
    echo -e "${ERROR} 生成 idbloader.img 失败"
    exit 1
fi

echo -e "${SUCCESS} idbloader.img 生成成功"

# 13. 生成输出文件
echo -e "${INFO} 生成输出文件..."
mkdir -p "${OUTPUT_DIR}"

# 查找生成的二进制文件
if [ -f "${UBOOT_DIR}/u-boot.itb" ]; then
    cp -f "${UBOOT_DIR}/u-boot.itb" "${OUTPUT_DIR}/u-boot.itb"
    echo -e "${SUCCESS} 复制 u-boot.itb 到 ${OUTPUT_DIR}"
fi

# 复制 idbloader.img（如果已生成）
if [ -f "${UBOOT_DIR}/idbloader.img" ]; then
    cp -f "${UBOOT_DIR}/idbloader.img" "${OUTPUT_DIR}/idbloader.img"
    echo -e "${SUCCESS} 复制 idbloader.img 到 ${OUTPUT_DIR}"
fi

# 12. 检查输出
if [ -f "${OUTPUT_DIR}/u-boot.itb" ]; then
    echo -e "${SUCCESS} U-Boot构建完成！"
    echo -e "${INFO} 输出文件位置: ${OUTPUT_DIR}"
    ls -lh "${OUTPUT_DIR}"/*.itb "${OUTPUT_DIR}"/*.img 2>/dev/null || true
else
    echo -e "${WARNING} 未找到 u-boot.itb，请检查构建日志"
fi

echo -e "${SUCCESS} U-Boot构建流程完成"
