#!/bin/bash
#================================================================================================
#
# MicroSLAM Kernel Build Script
# Kernel独立构建脚本，使用make modules_install生成.ko文件（不使用deb包）
# 实现基于make的增量构建（通过控制是否执行make mrproper）
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 路径配置
KERNEL_DIR="${PROJECT_ROOT}/repos/linux-6.1.y-rockchip"
CONFIGS_DIR="${PROJECT_ROOT}/configs"
OUTPUT_DIR="${PROJECT_ROOT}/output/kernel"
ARMBIAN_DIR="${PROJECT_ROOT}/repos/armbian-build"

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

# 默认参数
INCREMENTAL_BUILD_KERNEL="${INCREMENTAL_BUILD_KERNEL:-no}"
CPUTHREADS="${CPUTHREADS:-$(nproc)}"
KERNEL_VERSION="6.1"
KERNEL_VERPATCH="6.1"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --incremental)
            INCREMENTAL_BUILD_KERNEL="yes"
            echo -e "${INFO} 增量构建模式：跳过 make mrproper"
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

echo -e "${STEPS} 开始构建MicroSLAM Kernel..."

# 1. 初始化仓库
echo -e "${INFO} 初始化仓库..."
"${SCRIPT_DIR}/init-repos.sh"

# 2. 检查Kernel源码是否存在
if [ ! -d "${KERNEL_DIR}" ]; then
    echo -e "${ERROR} linux-6.1.y-rockchip 仓库不存在，请先运行 init-repos.sh"
    exit 1
fi

# 3. 检查交叉编译工具链
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

# 4. 设置编译环境变量
export ARCH=arm64
export SRC_ARCH=arm64
export LOCALVERSION=""

# 5. 准备输出目录
echo -e "${INFO} 准备输出目录..."
rm -rf "${OUTPUT_DIR}"/{boot/,dtb/,modules/,header/}
mkdir -p "${OUTPUT_DIR}"/{boot/,dtb/rockchip/,modules/,header/}

# 6. 进入Kernel源码目录
cd "${KERNEL_DIR}"

# 7. 设置make参数
MAKE_SET_STRING="ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} LOCALVERSION=${LOCALVERSION}"

# 8. 增量构建判断（参考 amlogic-s9xxx-armbian/recompile 第655-661行）
if [ "${INCREMENTAL_BUILD_KERNEL}" != "yes" ]; then
    echo -e "${INFO} 全量构建：执行 make mrproper"
    make ${MAKE_SET_STRING} mrproper
else
    echo -e "${INFO} 增量构建：跳过 make mrproper"
fi

# 9. 检查并复制内核配置
if [ ! -s ".config" ]; then
    if [ -f "${CONFIGS_DIR}/kernel/config-${KERNEL_VERPATCH}" ]; then
        echo -e "${INFO} 复制内核配置文件..."
        cp -f "${CONFIGS_DIR}/kernel/config-${KERNEL_VERPATCH}" .config
    else
        echo -e "${ERROR} 未找到内核配置文件: ${CONFIGS_DIR}/kernel/config-${KERNEL_VERPATCH}"
        exit 1
    fi
else
    echo -e "${INFO} 使用现有的 .config 文件"
fi

# 10. 清除内核签名
sed -i "s|CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"\"|" .config

# 11. 复制DTS文件（如果需要）
if [ -d "${CONFIGS_DIR}/kernel/dts" ]; then
    echo -e "${INFO} 复制DTS文件..."
    for dts_file in "${CONFIGS_DIR}/kernel/dts"/*.dts; do
        if [ -f "${dts_file}" ]; then
            dts_name=$(basename "${dts_file}")
            dts_dest="arch/${ARCH}/boot/dts/rockchip/${dts_name}"
            mkdir -p "$(dirname "${dts_dest}")"
            cp -f "${dts_file}" "${dts_dest}"
            echo -e "${INFO} 复制 ${dts_name} 到 ${dts_dest}"
        fi
    done
fi

# 12. 编译内核
echo -e "${INFO} 开始编译内核（线程数: ${CPUTHREADS}）..."
make ${MAKE_SET_STRING} Image dtbs -j${CPUTHREADS}
if [ $? -ne 0 ]; then
    echo -e "${ERROR} 内核编译失败"
    exit 1
fi
echo -e "${SUCCESS} 内核编译成功"

# 13. 编译模块
echo -e "${INFO} 开始编译内核模块（线程数: ${CPUTHREADS}）..."
make ${MAKE_SET_STRING} modules -j${CPUTHREADS}
if [ $? -ne 0 ]; then
    echo -e "${ERROR} 内核模块编译失败"
    exit 1
fi
echo -e "${SUCCESS} 内核模块编译成功"

# 14. 安装模块（参考 amlogic-s9xxx-armbian-new/compile-kernel/tools/script/armbian_compile_kernel.sh）
echo -e "${INFO} 安装内核模块..."
make ${MAKE_SET_STRING} INSTALL_MOD_PATH="${OUTPUT_DIR}/modules" modules_install
if [ $? -ne 0 ]; then
    echo -e "${ERROR} 内核模块安装失败"
    exit 1
fi
echo -e "${SUCCESS} 内核模块安装成功"

# 15. 去除模块调试信息（可选）
if command -v ${CROSS_COMPILE}strip >/dev/null 2>&1; then
    echo -e "${INFO} 去除模块调试信息..."
    STRIP="${CROSS_COMPILE}strip"
    find "${OUTPUT_DIR}/modules" -name "*.ko" -print0 | xargs -0 ${STRIP} --strip-debug 2>/dev/null || true
    echo -e "${SUCCESS} 模块调试信息已去除"
fi

# 16. 获取内核版本名称
KERNEL_OUTNAME=$(ls -1 "${OUTPUT_DIR}/modules/lib/modules/" 2>/dev/null | head -1)
if [ -z "${KERNEL_OUTNAME}" ]; then
    echo -e "${WARNING} 无法确定内核版本名称，使用默认值"
    KERNEL_OUTNAME="6.1.0"
fi
echo -e "${INFO} 内核版本名称: ${KERNEL_OUTNAME}"

# 17. 复制内核镜像
if [ -f "arch/${ARCH}/boot/Image" ]; then
    cp -f "arch/${ARCH}/boot/Image" "${OUTPUT_DIR}/boot/Image"
    cp -f "arch/${ARCH}/boot/Image" "${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_OUTNAME}"
    echo -e "${SUCCESS} 复制内核镜像完成"
else
    echo -e "${ERROR} 未找到内核镜像: arch/${ARCH}/boot/Image"
    exit 1
fi

# 18. 复制设备树文件
if [ -d "arch/${ARCH}/boot/dts/rockchip" ]; then
    cp -f arch/${ARCH}/boot/dts/rockchip/*.dtb "${OUTPUT_DIR}/dtb/rockchip/" 2>/dev/null || true
    if [ -d "arch/${ARCH}/boot/dts/rockchip/overlay" ]; then
        mkdir -p "${OUTPUT_DIR}/dtb/rockchip/overlay"
        cp -f arch/${ARCH}/boot/dts/rockchip/overlay/*.dtbo "${OUTPUT_DIR}/dtb/rockchip/overlay/" 2>/dev/null || true
    fi
    echo -e "${SUCCESS} 复制设备树文件完成"
fi

# 19. 可选：打包模块（便于传输和缓存）
if [ -d "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" ]; then
    echo -e "${INFO} 打包内核模块..."
    cd "${OUTPUT_DIR}/modules"
    tar -czf "${OUTPUT_DIR}/modules-${KERNEL_OUTNAME}.tar.gz" lib/modules/${KERNEL_OUTNAME}
    cd - > /dev/null
    echo -e "${SUCCESS} 模块打包完成: modules-${KERNEL_OUTNAME}.tar.gz"
fi

# 20. 检查输出
echo -e "${INFO} 检查输出文件..."
if [ -f "${OUTPUT_DIR}/boot/Image" ] && [ -d "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" ]; then
    echo -e "${SUCCESS} Kernel构建完成！"
    echo -e "${INFO} 输出文件位置: ${OUTPUT_DIR}"
    echo -e "${INFO} 内核镜像: ${OUTPUT_DIR}/boot/Image"
    echo -e "${INFO} 设备树文件: ${OUTPUT_DIR}/dtb/rockchip/"
    echo -e "${INFO} 内核模块: ${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}/"
    ls -lh "${OUTPUT_DIR}/boot/Image" 2>/dev/null || true
    ls -lh "${OUTPUT_DIR}/dtb/rockchip"/*.dtb 2>/dev/null | head -5 || true
    echo -e "${INFO} 模块数量: $(find "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" -name "*.ko" | wc -l)"
else
    echo -e "${WARNING} 输出文件不完整，请检查构建日志"
fi

echo -e "${SUCCESS} Kernel构建流程完成"
