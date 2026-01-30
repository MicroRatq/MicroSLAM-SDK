#!/bin/bash
#================================================================================================
#
# MicroSLAM rtnicpg Build Script
# 独立编译脚本，用于 rtl8125 网卡 efuse 一次性烧录
# 编译 pgdrv.ko 内核模块和 rtnicpg 用户空间工具
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载公共函数库
source "${SCRIPT_DIR}/common.sh"

# 路径配置
RTNICPG_DIR="${PROJECT_ROOT}/repos/rtnicpg"
KERNEL_DIR="${PROJECT_ROOT}/repos/linux-6.1.y-rockchip"
OUTPUT_DIR="${PROJECT_ROOT}/output/rtnicpg"
ARMBIAN_DIR="${PROJECT_ROOT}/repos/armbian-build"

# 默认参数
CPUTHREADS="${CPUTHREADS:-$(calculate_optimal_threads)}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
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

echo -e "${STEPS} 开始构建 rtnicpg 驱动模块..."

# 1. 检查内核源码是否存在
if [ ! -d "${KERNEL_DIR}" ]; then
    echo -e "${ERROR} 内核源码目录不存在: ${KERNEL_DIR}"
    echo -e "${ERROR} 请先运行 ./scripts/init-repos.sh 初始化仓库"
    exit 1
fi

# 2. 检查内核 .config 是否存在（至少需要 .config 用于模块编译）
if [ ! -f "${KERNEL_DIR}/.config" ]; then
    echo -e "${WARNING} 内核 .config 不存在，尝试从配置文件复制..."
    CONFIGS_DIR="${PROJECT_ROOT}/configs"
    if [ -f "${CONFIGS_DIR}/kernel/config-6.1" ]; then
        cp -f "${CONFIGS_DIR}/kernel/config-6.1" "${KERNEL_DIR}/.config"
        echo -e "${INFO} 已复制内核配置文件"
    else
        echo -e "${ERROR} 未找到内核配置文件，请先构建内核或提供 .config"
        exit 1
    fi
fi

# 2.5. 准备内核头文件（用于模块编译）
echo -e "${INFO} 准备内核头文件..."
cd "${KERNEL_DIR}"
export ARCH=arm64
export SRC_ARCH=arm64
if [ -z "${CROSS_COMPILE}" ]; then
    # 临时设置工具链用于 prepare（后续会重新检测）
    if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
        export CROSS_COMPILE="aarch64-linux-gnu-"
    fi
fi
# 运行 olddefconfig 确保配置完整，然后 prepare 准备头文件
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig >/dev/null 2>&1 || true
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" prepare >/dev/null 2>&1 || true
echo -e "${SUCCESS} 内核头文件准备完成"

# 3. 检查交叉编译工具链
echo -e "${INFO} 检查交叉编译工具链..."
if ! find_cross_compiler arm64 "${PROJECT_ROOT}"; then
    exit 1
fi

if ! check_cross_compiler; then
    exit 1
fi

# 4. 设置编译环境变量（确保与内核准备时一致）
export ARCH=arm64
export SRC_ARCH=arm64

# 5. 克隆或更新 rtnicpg 仓库
echo -e "${INFO} 检查 rtnicpg 仓库..."
if [ ! -d "${RTNICPG_DIR}" ]; then
    echo -e "${INFO} 克隆 rtnicpg 仓库..."
    git clone https://github.com/redchenjs/rtnicpg.git "${RTNICPG_DIR}"
    echo -e "${SUCCESS} rtnicpg 仓库已克隆"
else
    echo -e "${INFO} rtnicpg 仓库已存在，跳过克隆"
    # 可选：更新仓库
    # cd "${RTNICPG_DIR}" && git pull || true
fi

# 6. 准备输出目录
echo -e "${INFO} 准备输出目录..."
mkdir -p "${OUTPUT_DIR}"
echo -e "${SUCCESS} 输出目录已创建: ${OUTPUT_DIR}"

# 7. 编译内核模块 pgdrv.ko
echo -e "${INFO} 开始编译内核模块 pgdrv.ko..."
cd "${RTNICPG_DIR}"

# 清理之前的构建
echo -e "${INFO} 清理之前的构建..."
make KERNELDIR="${KERNEL_DIR}" CROSS_COMPILE="${CROSS_COMPILE}" ARCH="${ARCH}" clean || true

# 编译内核模块
echo -e "${INFO} 编译内核模块（使用内核源码: ${KERNEL_DIR}）..."
make KERNELDIR="${KERNEL_DIR}" CROSS_COMPILE="${CROSS_COMPILE}" ARCH="${ARCH}" -j${CPUTHREADS}

if [ ! -f "pgdrv.ko" ]; then
    echo -e "${ERROR} 内核模块编译失败，未找到 pgdrv.ko"
    exit 1
fi

echo -e "${SUCCESS} 内核模块编译成功: pgdrv.ko"

# 8. 编译用户空间工具 rtnicpg
echo -e "${INFO} 开始编译用户空间工具 rtnicpg..."

# 检查是否有 rtnicpg.c 源文件
if [ -f "rtnicpg.c" ]; then
    echo -e "${INFO} 找到 rtnicpg.c，开始编译..."
    ${CROSS_COMPILE}gcc -o rtnicpg rtnicpg.c -static
    if [ ! -f "rtnicpg" ]; then
        echo -e "${ERROR} 用户空间工具编译失败，未找到 rtnicpg"
        exit 1
    fi
    echo -e "${SUCCESS} 用户空间工具编译成功: rtnicpg"
elif [ -f "rtnicpg" ]; then
    echo -e "${INFO} 找到预编译的 rtnicpg 二进制文件"
    # 检查是否为 arm64 架构（可选）
    if command -v file >/dev/null 2>&1; then
        file_info=$(file rtnicpg 2>/dev/null || echo "")
        if echo "${file_info}" | grep -q "ARM\|aarch64\|arm64"; then
            echo -e "${SUCCESS} rtnicpg 二进制文件已存在（ARM 架构）"
        else
            echo -e "${WARNING} rtnicpg 二进制文件架构可能不匹配，建议重新编译"
        fi
    fi
else
    echo -e "${WARNING} 未找到 rtnicpg.c 源文件或预编译二进制文件"
    echo -e "${WARNING} 将仅复制 pgdrv.ko"
fi

# 9. 复制编译产物到输出目录
echo -e "${INFO} 复制编译产物到输出目录..."
cp -f pgdrv.ko "${OUTPUT_DIR}/"
if [ -f "rtnicpg" ]; then
    cp -f rtnicpg "${OUTPUT_DIR}/"
    chmod +x "${OUTPUT_DIR}/rtnicpg"
fi

# 复制配置文件（如果存在）
if ls *.cfg 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo -e "${INFO} 复制配置文件..."
    cp -f *.cfg "${OUTPUT_DIR}/" 2>/dev/null || true
fi

# 10. 输出构建摘要
echo -e "${STEPS} ========================================"
echo -e "${STEPS} 构建摘要"
echo -e "${STEPS} ========================================"
echo -e "${SUCCESS} rtnicpg 构建完成！"
echo -e "${INFO} 输出文件位置: ${OUTPUT_DIR}"
if [ -f "${OUTPUT_DIR}/pgdrv.ko" ]; then
    ls -lh "${OUTPUT_DIR}/pgdrv.ko"
fi
if [ -f "${OUTPUT_DIR}/rtnicpg" ]; then
    ls -lh "${OUTPUT_DIR}/rtnicpg"
fi
echo -e "${INFO} 使用说明："
echo -e "${INFO} 1. 将 pgdrv.ko 和 rtnicpg 复制到目标设备"
echo -e "${INFO} 2. 卸载 Realtek 网卡驱动: rmmod r8169 r8168 r8125 r8101"
echo -e "${INFO} 3. 加载模块: insmod pgdrv.ko"
echo -e "${INFO} 4. 运行工具: ./rtnicpg /h 查看帮助"
echo -e "${INFO} 5. 使用完成后: rmmod pgdrv"
