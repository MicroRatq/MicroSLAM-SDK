#!/bin/bash
#================================================================================================
#
# MicroSLAM Main Build Script
# 主构建脚本，集成所有组件构建，支持精细的增量构建控制参数
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
CLEAN_ONLY="no"
RELEASE="${RELEASE:-noble}"
BRANCH="${BRANCH:-current}"
BUILD_DESKTOP="${BUILD_DESKTOP:-no}"
BUILD_MINIMAL="${BUILD_MINIMAL:-no}"

# 增量构建标志（默认值，会在参数解析时设置）
INCREMENTAL_BUILD_UBOOT="yes"
INCREMENTAL_BUILD_KERNEL="yes"
INCREMENTAL_BUILD_ROOTFS="yes"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -u)
            BUILD_UBOOT="yes"
            INCREMENTAL_BUILD_UBOOT="yes"
            echo -e "${INFO} 将增量构建 U-Boot"
            shift
            ;;
        -uc)
            BUILD_UBOOT="yes"
            INCREMENTAL_BUILD_UBOOT="no"
            echo -e "${INFO} 将全量构建 U-Boot"
            shift
            ;;
        -k)
            BUILD_KERNEL="yes"
            INCREMENTAL_BUILD_KERNEL="yes"
            echo -e "${INFO} 将增量构建 Kernel"
            shift
            ;;
        -kc)
            BUILD_KERNEL="yes"
            INCREMENTAL_BUILD_KERNEL="no"
            echo -e "${INFO} 将全量构建 Kernel"
            shift
            ;;
        -f)
            BUILD_ROOTFS="yes"
            INCREMENTAL_BUILD_ROOTFS="yes"
            echo -e "${INFO} 将增量构建 RootFS"
            shift
            ;;
        -fc)
            BUILD_ROOTFS="yes"
            INCREMENTAL_BUILD_ROOTFS="no"
            echo -e "${INFO} 将全量构建 RootFS"
            shift
            ;;
        -p|--package)
            BUILD_PACKAGE="yes"
            echo -e "${INFO} 将在构建流程最后执行打包"
            shift
            ;;
        --clean-cache)
            CLEAN_ONLY="yes"
            echo -e "${INFO} 仅清理缓存，不进行构建"
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
            echo "  -u              增量构建 U-Boot"
            echo "  -uc             全量构建 U-Boot"
            echo "  -k              增量构建 Kernel"
            echo "  -kc             全量构建 Kernel"
            echo "  -f              增量构建 RootFS"
            echo "  -fc             全量构建 RootFS"
            echo "  -p, --package   仅打包镜像（不构建），需要所有组件缓存存在"
            echo "  --clean-cache   仅清理缓存，不进行构建"
            echo "  -r, --release RELEASE  Armbian发布版本（默认: noble）"
            echo "  -b, --branch BRANCH    Armbian分支（默认: current）"
            echo "  --desktop              构建桌面版本"
            echo "  --minimal              构建最小版本"
            echo "  -j, --threads N        编译线程数（默认: 自动计算）"
            echo "  -h, --help             显示此帮助信息"
            echo ""
            echo "示例:"
            echo "  $0                      # 全量构建（U-Boot + Kernel + RootFS + 打包，增量模式）"
            echo "  $0 -u                   # 仅增量构建 U-Boot"
            echo "  $0 -uc                  # 仅全量构建 U-Boot"
            echo "  $0 -u -kc -f            # U-Boot 增量，Kernel 全量，RootFS 增量"
            echo "  $0 -p                   # 仅打包（使用所有组件缓存）"
            echo "  $0 -u -p                # 增量构建 U-Boot，使用 Kernel 和 RootFS 缓存打包"
            echo "  $0 --clean-cache        # 清理所有缓存"
            echo "  $0 -u --clean-cache     # 仅清理 U-Boot 缓存"
            exit 0
            ;;
        *)
            echo -e "${WARNING} 未知参数: $1，使用 --help 查看帮助"
            shift
            ;;
    esac
done

# 互斥参数检查
if [ "${BUILD_UBOOT}" = "yes" ]; then
    # 检查是否同时指定了 -u 和 -uc（这不应该发生，因为 case 语句会覆盖）
    # 但为了安全起见，我们检查 INCREMENTAL_BUILD_UBOOT 是否被正确设置
    if [ -z "${INCREMENTAL_BUILD_UBOOT}" ]; then
        echo -e "${ERROR} U-Boot 构建标志未正确设置"
        exit 1
    fi
fi

if [ "${BUILD_KERNEL}" = "yes" ]; then
    if [ -z "${INCREMENTAL_BUILD_KERNEL}" ]; then
        echo -e "${ERROR} Kernel 构建标志未正确设置"
        exit 1
    fi
fi

if [ "${BUILD_ROOTFS}" = "yes" ]; then
    if [ -z "${INCREMENTAL_BUILD_ROOTFS}" ]; then
        echo -e "${ERROR} RootFS 构建标志未正确设置"
        exit 1
    fi
fi

# 如果指定了 --clean-cache，执行清理逻辑并退出
if [ "${CLEAN_ONLY}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 清理缓存"
    echo -e "${STEPS} ========================================"
    
    # 根据 -u/-k/-f 参数决定清理范围
    if [ "${BUILD_UBOOT}" = "no" ] && [ "${BUILD_KERNEL}" = "no" ] && [ "${BUILD_ROOTFS}" = "no" ]; then
        # 默认情况：清理所有缓存
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
        
        # 重置 u-boot-radxa
        if [ -d "${PROJECT_ROOT}/repos/u-boot-radxa/.git" ]; then
            cd "${PROJECT_ROOT}/repos/u-boot-radxa"
            git fetch origin 2>/dev/null || true
            current_branch=$(git branch --show-current 2>/dev/null || echo "next-dev-v2024.10")
            git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
            git clean -fd 2>/dev/null || true
            echo -e "${SUCCESS} u-boot-radxa 仓库已重置"
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
        if [ "${BUILD_UBOOT}" = "yes" ]; then
            echo -e "${INFO} 清理 U-Boot 缓存..."
            if [ -d "${OUTPUT_DIR}/uboot" ]; then
                rm -rf "${OUTPUT_DIR}/uboot"/*
                echo -e "${SUCCESS} U-Boot 输出目录已清理"
            fi
            if [ -d "${PROJECT_ROOT}/repos/u-boot-radxa/.git" ]; then
                cd "${PROJECT_ROOT}/repos/u-boot-radxa"
                git fetch origin 2>/dev/null || true
                current_branch=$(git branch --show-current 2>/dev/null || echo "next-dev-v2024.10")
                git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
                git clean -fd 2>/dev/null || true
                echo -e "${SUCCESS} u-boot-radxa 仓库已重置"
            fi
        fi
        
        if [ "${BUILD_KERNEL}" = "yes" ]; then
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
        
        if [ "${BUILD_ROOTFS}" = "yes" ]; then
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
    exit 0
fi

# 默认行为处理
if [ "${BUILD_UBOOT}" = "no" ] && [ "${BUILD_KERNEL}" = "no" ] && [ "${BUILD_ROOTFS}" = "no" ]; then
    if [ "${BUILD_PACKAGE}" = "yes" ]; then
        # 如果指定了 -p 但没有指定任何构建参数，则仅打包（不构建）
        echo -e "${INFO} 仅打包模式：将使用缓存进行打包，不进行构建"
    else
        # 如果既没有构建参数也没有 -p，默认构建所有组件且使用增量构建
        BUILD_UBOOT="yes"
        BUILD_KERNEL="yes"
        BUILD_ROOTFS="yes"
        INCREMENTAL_BUILD_UBOOT="yes"
        INCREMENTAL_BUILD_KERNEL="yes"
        INCREMENTAL_BUILD_ROOTFS="yes"
        BUILD_PACKAGE="yes"  # 默认情况下自动打包
        echo -e "${INFO} 默认构建模式：将构建所有组件（增量）并打包镜像"
    fi
fi

# 如果构建了所有组件，自动启用打包（除非明确指定了 -p）
if [ "${BUILD_UBOOT}" = "yes" ] && [ "${BUILD_KERNEL}" = "yes" ] && [ "${BUILD_ROOTFS}" = "yes" ]; then
    if [ "${BUILD_PACKAGE}" = "no" ]; then
        BUILD_PACKAGE="yes"
        echo -e "${INFO} 所有组件已构建，将自动打包镜像"
    fi
fi

# 导出增量构建环境变量
export INCREMENTAL_BUILD_UBOOT
export INCREMENTAL_BUILD_KERNEL
export INCREMENTAL_BUILD_ROOTFS

echo -e "${STEPS} 开始MicroSLAM构建流程..."
echo -e "${INFO} 构建组件: U-Boot=${BUILD_UBOOT}, Kernel=${BUILD_KERNEL}, RootFS=${BUILD_ROOTFS}, Package=${BUILD_PACKAGE}"
echo -e "${INFO} 增量构建: U-Boot=${INCREMENTAL_BUILD_UBOOT}, Kernel=${INCREMENTAL_BUILD_KERNEL}, RootFS=${INCREMENTAL_BUILD_ROOTFS}"
echo -e "${INFO} 发布版本: ${RELEASE}, 分支: ${BRANCH}"

# 设置编译线程数（如果未指定）
if [ -z "${CPUTHREADS}" ]; then
    CPUTHREADS=$(calculate_optimal_threads)
    echo -e "${INFO} 自动计算编译线程数: ${CPUTHREADS}"
fi

# 创建输出目录
create_output_dirs "${PROJECT_ROOT}"

# 构建U-Boot
if [ "${BUILD_UBOOT}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 构建 U-Boot (${INCREMENTAL_BUILD_UBOOT}模式)"
    echo -e "${STEPS} ========================================"
    
    if [ "${INCREMENTAL_BUILD_UBOOT}" = "yes" ]; then
        "${SCRIPT_DIR}/build-uboot.sh" --incremental -j "${CPUTHREADS}"
    else
        "${SCRIPT_DIR}/build-uboot.sh" -j "${CPUTHREADS}"
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
    echo -e "${STEPS} 构建 Kernel (${INCREMENTAL_BUILD_KERNEL}模式)"
    echo -e "${STEPS} ========================================"
    
    if [ "${INCREMENTAL_BUILD_KERNEL}" = "yes" ]; then
        "${SCRIPT_DIR}/build-kernel.sh" --incremental -j "${CPUTHREADS}"
    else
        "${SCRIPT_DIR}/build-kernel.sh" -j "${CPUTHREADS}"
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
    echo -e "${STEPS} 构建 RootFS (${INCREMENTAL_BUILD_ROOTFS}模式)"
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

    # 检查所有必要的输出（如果某个组件未构建，检查缓存是否存在）
    missing_components=()
    
    # 检查 U-Boot
    if [ "${BUILD_UBOOT}" = "no" ]; then
        if ! check_build_outputs "uboot" "${PROJECT_ROOT}" 2>/dev/null; then
            missing_components+=("U-Boot")
        else
            echo -e "${SUCCESS} U-Boot 缓存存在"
        fi
    else
        check_build_outputs "uboot" "${PROJECT_ROOT}" || exit 1
    fi
    
    # 检查 Kernel
    if [ "${BUILD_KERNEL}" = "no" ]; then
        if ! check_build_outputs "kernel" "${PROJECT_ROOT}" 2>/dev/null; then
            missing_components+=("Kernel")
        else
            echo -e "${SUCCESS} Kernel 缓存存在"
        fi
    else
        check_build_outputs "kernel" "${PROJECT_ROOT}" || exit 1
    fi
    
    # 检查 RootFS
    if [ "${BUILD_ROOTFS}" = "no" ]; then
        if ! check_build_outputs "rootfs" "${PROJECT_ROOT}" 2>/dev/null; then
            missing_components+=("RootFS")
        else
            echo -e "${SUCCESS} RootFS 缓存存在"
        fi
    else
        check_build_outputs "rootfs" "${PROJECT_ROOT}" || exit 1
    fi
    
    # 如果缺少任何组件，报错退出
    if [ ${#missing_components[@]} -gt 0 ]; then
        echo -e "${ERROR} 打包失败：以下组件的缓存不存在: ${missing_components[*]}"
        echo -e "${ERROR} 请先构建这些组件（使用 -u/-k/-f 参数）"
        exit 1
    fi
    
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
