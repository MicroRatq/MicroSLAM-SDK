#!/bin/bash
#================================================================================================
#
# MicroSLAM Main Build Script
# 主构建脚本，集成所有组件构建，支持-u/-k/-f参数和--incremental增量构建参数
# 基于make的增量构建机制
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载公共函数库
source "${SCRIPT_DIR}/common.sh"

# 路径配置
OUTPUT_DIR="${PROJECT_ROOT}/output"

# 默认参数
BUILD_UBOOT="no"
BUILD_KERNEL="no"
BUILD_ROOTFS="no"
BUILD_PACKAGE="no"
INCREMENTAL_BUILD="no"
CLEAN_CACHE="no"
RELEASE="${RELEASE:-noble}"
BRANCH="${BRANCH:-current}"
BUILD_DESKTOP="${BUILD_DESKTOP:-no}"
BUILD_MINIMAL="${BUILD_MINIMAL:-no}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--build-uboot)
            BUILD_UBOOT="yes"
            echo -e "${INFO} 将构建 U-Boot"
            shift
            ;;
        -k|--build-kernel)
            BUILD_KERNEL="yes"
            echo -e "${INFO} 将构建 Kernel"
            shift
            ;;
        -f|--build-rootfs)
            BUILD_ROOTFS="yes"
            echo -e "${INFO} 将构建 RootFS"
            shift
            ;;
        --incremental)
            INCREMENTAL_BUILD="yes"
            echo -e "${INFO} 增量构建模式：跳过 make clean/mrproper"
            shift
            ;;
        --clean-cache)
            CLEAN_CACHE="yes"
            echo -e "${INFO} 将在构建前进行深度清理"
            shift
            ;;
        -r|--release)
            RELEASE="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        --desktop)
            BUILD_DESKTOP="yes"
            shift
            ;;
        --minimal)
            BUILD_MINIMAL="yes"
            shift
            ;;
        -j|--threads)
            CPUTHREADS="$2"
            echo -e "${INFO} 设置编译线程数为: ${CPUTHREADS}"
            shift 2
            ;;
        -h|--help)
            echo "MicroSLAM Build Script"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  -u, --build-uboot      仅构建 U-Boot"
            echo "  -k, --build-kernel     仅构建 Kernel"
            echo "  -f, --build-rootfs     仅构建 RootFS"
            echo "  --incremental          增量构建模式（跳过 make clean/mrproper）"
            echo "  --clean-cache          深度清理（包括源代码和缓存）"
            echo "  -r, --release RELEASE  Armbian发布版本（默认: noble）"
            echo "  -b, --branch BRANCH    Armbian分支（默认: current）"
            echo "  --desktop              构建桌面版本"
            echo "  --minimal              构建最小版本"
            echo "  -j, --threads N        编译线程数（默认: CPU核心数）"
            echo "  -h, --help             显示此帮助信息"
            echo ""
            echo "示例:"
            echo "  $0                      # 全量构建（U-Boot + Kernel + RootFS + 打包）"
            echo "  $0 -u                   # 仅构建 U-Boot"
            echo "  $0 -k --incremental     # 增量构建 Kernel"
            echo "  $0 -f -r jammy          # 构建 RootFS（使用 jammy 发布版本）"
            exit 0
            ;;
        *)
            echo -e "${WARNING} 未知参数: $1，使用 --help 查看帮助"
            shift
            ;;
    esac
done

# 如果没有指定任何组件，则全量构建
if [ "${BUILD_UBOOT}" = "no" ] && [ "${BUILD_KERNEL}" = "no" ] && [ "${BUILD_ROOTFS}" = "no" ]; then
    BUILD_UBOOT="yes"
    BUILD_KERNEL="yes"
    BUILD_ROOTFS="yes"
    BUILD_PACKAGE="yes"
    echo -e "${INFO} 全量构建模式：将构建所有组件并打包镜像"
fi

# 如果构建了所有组件，自动启用打包
if [ "${BUILD_UBOOT}" = "yes" ] && [ "${BUILD_KERNEL}" = "yes" ] && [ "${BUILD_ROOTFS}" = "yes" ]; then
    BUILD_PACKAGE="yes"
    echo -e "${INFO} 所有组件已构建，将自动打包镜像"
fi

echo -e "${STEPS} 开始MicroSLAM构建流程..."
echo -e "${INFO} 构建组件: U-Boot=${BUILD_UBOOT}, Kernel=${BUILD_KERNEL}, RootFS=${BUILD_ROOTFS}, Package=${BUILD_PACKAGE}"
echo -e "${INFO} 增量构建: ${INCREMENTAL_BUILD}"
echo -e "${INFO} 发布版本: ${RELEASE}, 分支: ${BRANCH}"

# 设置增量构建环境变量
if [ "${INCREMENTAL_BUILD}" = "yes" ]; then
    export INCREMENTAL_BUILD_UBOOT="yes"
    export INCREMENTAL_BUILD_KERNEL="yes"
else
    export INCREMENTAL_BUILD_UBOOT="no"
    export INCREMENTAL_BUILD_KERNEL="no"
fi

# 清理缓存（如果需要）
if [ "${CLEAN_CACHE}" = "yes" ]; then
    echo -e "${INFO} 进行深度清理..."
    
    # 清理输出目录
    if [ -d "${OUTPUT_DIR}" ]; then
        rm -rf "${OUTPUT_DIR}"/*
        echo -e "${SUCCESS} 输出目录已清理"
    fi
    
    # 清理Armbian缓存（保留tools目录）
    if [ -d "${PROJECT_ROOT}/repos/armbian-build/cache" ]; then
        find "${PROJECT_ROOT}/repos/armbian-build/cache" -mindepth 1 -maxdepth 1 ! -name "tools" -exec rm -rf {} + 2>/dev/null || true
        echo -e "${SUCCESS} Armbian缓存已清理（保留tools目录）"
    fi
    
    # 清理临时目录
    if [ -d "${PROJECT_ROOT}/.tmp" ]; then
        rm -rf "${PROJECT_ROOT}/.tmp"/*
        echo -e "${SUCCESS} 临时目录已清理"
    fi
fi

# 创建输出目录
create_output_dirs "${PROJECT_ROOT}"

# 构建U-Boot
if [ "${BUILD_UBOOT}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 构建 U-Boot"
    echo -e "${STEPS} ========================================"
    
    if [ "${INCREMENTAL_BUILD}" = "yes" ]; then
        "${SCRIPT_DIR}/build-uboot.sh" --incremental -j "${CPUTHREADS:-$(nproc)}"
    else
        "${SCRIPT_DIR}/build-uboot.sh" -j "${CPUTHREADS:-$(nproc)}"
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${ERROR} U-Boot构建失败"
    exit 1
fi

    # 检查输出
    check_build_outputs "uboot" "${PROJECT_ROOT}" || exit 1
fi

# 构建Kernel
if [ "${BUILD_KERNEL}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 构建 Kernel"
    echo -e "${STEPS} ========================================"
    
    if [ "${INCREMENTAL_BUILD}" = "yes" ]; then
        "${SCRIPT_DIR}/build-kernel.sh" --incremental -j "${CPUTHREADS:-$(nproc)}"
    else
        "${SCRIPT_DIR}/build-kernel.sh" -j "${CPUTHREADS:-$(nproc)}"
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${ERROR} Kernel构建失败"
        exit 1
    fi
    
    # 检查输出
    check_build_outputs "kernel" "${PROJECT_ROOT}" || exit 1
fi

# 构建RootFS
if [ "${BUILD_ROOTFS}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 构建 RootFS"
    echo -e "${STEPS} ========================================"
    
    "${SCRIPT_DIR}/build-rootfs.sh" \
        -r "${RELEASE}" \
        -b "${BRANCH}" \
        ${BUILD_DESKTOP:+--desktop} \
        ${BUILD_MINIMAL:+--minimal}
    
    if [ $? -ne 0 ]; then
        echo -e "${ERROR} RootFS构建失败"
        exit 1
fi

    # 检查输出
    check_build_outputs "rootfs" "${PROJECT_ROOT}" || exit 1
fi

# 打包镜像
if [ "${BUILD_PACKAGE}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 打包镜像"
    echo -e "${STEPS} ========================================"
    
    # 检查所有必要的输出
    check_build_outputs "uboot" "${PROJECT_ROOT}" || exit 1
    check_build_outputs "kernel" "${PROJECT_ROOT}" || exit 1
    check_build_outputs "rootfs" "${PROJECT_ROOT}" || exit 1
    
    "${SCRIPT_DIR}/package-image.sh"
    
    if [ $? -ne 0 ]; then
        echo -e "${ERROR} 镜像打包失败"
        exit 1
    fi
fi

# 显示构建摘要
echo -e "${STEPS} ========================================"
echo -e "${STEPS} 构建摘要"
echo -e "${STEPS} ========================================"

if [ "${BUILD_UBOOT}" = "yes" ]; then
    echo -e "${SUCCESS} U-Boot: ${OUTPUT_DIR}/uboot/"
    ls -lh "${OUTPUT_DIR}/uboot"/*.itb "${OUTPUT_DIR}/uboot"/*.img 2>/dev/null | head -3 || true
fi

if [ "${BUILD_KERNEL}" = "yes" ]; then
    echo -e "${SUCCESS} Kernel: ${OUTPUT_DIR}/kernel/"
    ls -lh "${OUTPUT_DIR}/kernel/boot/Image" 2>/dev/null || true
    echo -e "${INFO} 模块数量: $(find "${OUTPUT_DIR}/kernel/modules" -name "*.ko" 2>/dev/null | wc -l)"
fi

if [ "${BUILD_ROOTFS}" = "yes" ]; then
    echo -e "${SUCCESS} RootFS: ${OUTPUT_DIR}/rootfs/"
    ls -lh "${OUTPUT_DIR}/rootfs"/*.tar* 2>/dev/null | head -1 || true
fi

if [ "${BUILD_PACKAGE}" = "yes" ]; then
    echo -e "${SUCCESS} 镜像: ${OUTPUT_DIR}/images/"
    ls -lh "${OUTPUT_DIR}/images"/*.img 2>/dev/null | head -1 || true
fi

echo -e "${SUCCESS} 构建流程完成！"
