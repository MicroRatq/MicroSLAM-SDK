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

# 清理函数：在脚本退出时修复 repos 目录权限
# Docker 容器内以 root 运行可能导致目录权限问题，需要恢复可执行权限
cleanup_repos_permissions() {
    local repos_dir="${PROJECT_ROOT}/repos"
    local output_dir="${PROJECT_ROOT}/output"
    echo -e "${INFO} 修复 repos/output 目录权限..."
    [ -d "${repos_dir}" ] && chmod -R 775 "${repos_dir}" 2>/dev/null || true
    [ -d "${output_dir}" ] && chmod -R 775 "${output_dir}" 2>/dev/null || true
    echo -e "${SUCCESS} repos/output 目录权限已修复"
}

# 设置 trap：在脚本退出时（无论成功、失败或 Ctrl+C）执行清理
trap cleanup_repos_permissions EXIT

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

# 检测 docker compose / docker-compose（--clean-cache 与构建流程均需使用）
if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif docker-compose --version >/dev/null 2>&1; then
    DC="docker-compose"
else
    echo -e "${ERROR} 未找到 docker compose 或 docker-compose"
    exit 1
fi

# 检测并配置 QEMU binfmt（用于 arm64 容器）
check_and_setup_binfmt() {
    # 检查是否已配置 aarch64 binfmt
    if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        return 0
    fi

    echo -e "${INFO} 配置 QEMU binfmt 以支持 arm64 容器..."
    if docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1; then
        echo -e "${SUCCESS} QEMU binfmt 配置成功"
        return 0
    else
        echo -e "${WARNING} QEMU binfmt 配置失败，arm64 容器功能可能不可用"
        return 1
    fi
}

# 如果指定了 --clean-cache，在容器内执行 clean-cache.sh 并退出
if [ "${CLEAN_ONLY}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 清理缓存"
    echo -e "${STEPS} ========================================"

    # 根据 -u/-k/-f 构造 clean-cache.sh 参数
    if [ "${BUILD_UBOOT}" = "no" ] && [ "${BUILD_KERNEL}" = "no" ] && [ "${BUILD_ROOTFS}" = "no" ]; then
        CLEAN_ARGS="--all"
    else
        CLEAN_ARGS=""
        [ "${BUILD_UBOOT}" = "yes" ] && CLEAN_ARGS="${CLEAN_ARGS} -u"
        [ "${BUILD_KERNEL}" = "yes" ] && CLEAN_ARGS="${CLEAN_ARGS} -k"
        [ "${BUILD_ROOTFS}" = "yes" ] && CLEAN_ARGS="${CLEAN_ARGS} -f"
        CLEAN_ARGS="${CLEAN_ARGS# }"
    fi

    $DC -f "${PROJECT_ROOT}/docker-compose.yml" run --rm --user root microslam-builder bash -c 'cd /MicroSLAM-SDK && ./scripts/clean-cache.sh '"${CLEAN_ARGS}"
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

# 在需要 arm64 容器时检查 binfmt（用于生成 uInitrd）
if [ "${BUILD_KERNEL}" = "yes" ]; then
    check_and_setup_binfmt
fi

echo -e "${STEPS} 开始MicroSLAM构建流程..."
echo -e "${INFO} 构建组件: U-Boot=${BUILD_UBOOT}, Kernel=${BUILD_KERNEL}, RootFS=${BUILD_ROOTFS}, Package=${BUILD_PACKAGE}"
echo -e "${INFO} 增量构建: U-Boot=${INCREMENTAL_BUILD_UBOOT}, Kernel=${INCREMENTAL_BUILD_KERNEL}, RootFS=${INCREMENTAL_BUILD_ROOTFS}"
echo -e "${INFO} 发布版本: ${RELEASE}, 分支: ${BRANCH}"

# 设置编译线程数（如果未指定）
if [ -z "${CPUTHREADS}" ]; then
    CPUTHREADS=$(calculate_optimal_threads)
    echo -e "${INFO} 自动计算编译线程数: ${CPUTHREADS}"
fi

# 若需构建或打包，确保 init-repos、容器已启动并创建输出目录
if [ "${BUILD_UBOOT}" = "yes" ] || [ "${BUILD_KERNEL}" = "yes" ] || [ "${BUILD_ROOTFS}" = "yes" ] || [ "${BUILD_PACKAGE}" = "yes" ]; then
    [ "${BUILD_UBOOT}" = "yes" ] || [ "${BUILD_KERNEL}" = "yes" ] || [ "${BUILD_ROOTFS}" = "yes" ] && "${SCRIPT_DIR}/init-repos.sh"
    $DC -f "${PROJECT_ROOT}/docker-compose.yml" up -d microslam-builder
    $DC -f "${PROJECT_ROOT}/docker-compose.yml" exec --user root microslam-builder bash -c 'mkdir -p /MicroSLAM-SDK/output/{uboot,kernel,rootfs,images}'
    echo -e "${SUCCESS} 输出目录已创建: ${OUTPUT_DIR}"
fi

# 构建U-Boot
if [ "${BUILD_UBOOT}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 构建 U-Boot (${INCREMENTAL_BUILD_UBOOT}模式)"
    echo -e "${STEPS} ========================================"

    UBOOT_ARGS="-j ${CPUTHREADS}"
    [ "${INCREMENTAL_BUILD_UBOOT}" = "yes" ] && UBOOT_ARGS="--incremental ${UBOOT_ARGS}"
    $DC -f "${PROJECT_ROOT}/docker-compose.yml" exec --user root -e INCREMENTAL_BUILD_UBOOT="${INCREMENTAL_BUILD_UBOOT}" -e CPUTHREADS="${CPUTHREADS}" microslam-builder bash -c 'cd /MicroSLAM-SDK && ./scripts/build-uboot.sh '"${UBOOT_ARGS}"
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

    KERNEL_ARGS="-j ${CPUTHREADS}"
    [ "${INCREMENTAL_BUILD_KERNEL}" = "yes" ] && KERNEL_ARGS="--incremental ${KERNEL_ARGS}"
    $DC -f "${PROJECT_ROOT}/docker-compose.yml" exec --user root -e INCREMENTAL_BUILD_KERNEL="${INCREMENTAL_BUILD_KERNEL}" -e CPUTHREADS="${CPUTHREADS}" microslam-builder bash -c 'cd /MicroSLAM-SDK && ./scripts/build-kernel.sh '"${KERNEL_ARGS}"
    if [ $? -ne 0 ]; then
        echo -e "${ERROR} Kernel构建失败"
        exit 1
    fi

    # 检查输出
    check_build_outputs "kernel" "${PROJECT_ROOT}" || exit 1

    # 在宿主机通过 arm64 容器生成 uInitrd（在 builder 内 run 时 compose 的 . 会解析到错误宿主机路径，/MicroSLAM-SDK 挂载为空）
    KERNEL_OUTNAME=$(ls -1 "${PROJECT_ROOT}/output/kernel/modules/lib/modules/" 2>/dev/null | head -1)
    if [ -n "${KERNEL_OUTNAME}" ]; then
        echo -e "${INFO} 在 arm64 容器中生成 uInitrd..."
        $DC -f "${PROJECT_ROOT}/docker-compose.yml" run --rm -e KERNEL_OUTNAME="${KERNEL_OUTNAME}" microslam-arm64 bash -c '
            mkdir -p /boot /usr/lib/modules
            cp -f /MicroSLAM-SDK/output/kernel/boot/vmlinuz-${KERNEL_OUTNAME} /boot/vmlinuz-${KERNEL_OUTNAME}
            cp -f /MicroSLAM-SDK/output/kernel/boot/config-${KERNEL_OUTNAME} /boot/config-${KERNEL_OUTNAME}
            cp -f /MicroSLAM-SDK/output/kernel/boot/System.map-${KERNEL_OUTNAME} /boot/System.map-${KERNEL_OUTNAME}
            cp -f /MicroSLAM-SDK/output/kernel/boot/vmlinuz-${KERNEL_OUTNAME} /boot/Image
            cp -r /MicroSLAM-SDK/output/kernel/modules/lib/modules/${KERNEL_OUTNAME} /usr/lib/modules/
            cd /boot && update-initramfs -c -k ${KERNEL_OUTNAME}
            mkimage -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs-${KERNEL_OUTNAME} -d /boot/initrd.img-${KERNEL_OUTNAME} /boot/uInitrd-${KERNEL_OUTNAME}
            cp -f /boot/uInitrd-${KERNEL_OUTNAME} /boot/initrd.img-${KERNEL_OUTNAME} /MicroSLAM-SDK/output/kernel/boot/
        '
        echo -e "${SUCCESS} uInitrd 生成完成"
        # build-kernel 的 19.1 在 uInitrd 之前已执行，此处在 builder 容器内以 root 重新打包 boot 以包含 uInitrd（宿主机无权限覆盖 root 属主的 tar.gz）
        if [ -f "${PROJECT_ROOT}/output/kernel/boot/uInitrd-${KERNEL_OUTNAME}" ] && [ -d "${PROJECT_ROOT}/output/kernel/packages/${KERNEL_OUTNAME}" ]; then
            $DC -f "${PROJECT_ROOT}/docker-compose.yml" exec --user root microslam-builder bash -c 'tar -czf /MicroSLAM-SDK/output/kernel/packages/'"${KERNEL_OUTNAME}"'/boot-'"${KERNEL_OUTNAME}"'.tar.gz -C /MicroSLAM-SDK/output/kernel/boot .'
            echo -e "${INFO} 已更新 boot 包以包含 uInitrd"
        fi
    fi
fi

# 构建RootFS
if [ "${BUILD_ROOTFS}" = "yes" ]; then
    echo -e "${STEPS} ========================================"
    echo -e "${STEPS} 构建 RootFS (${INCREMENTAL_BUILD_ROOTFS}模式)"
    echo -e "${STEPS} ========================================"

    ROOTFS_ARGS="-r ${RELEASE} -b ${BRANCH}"
    [ "${BUILD_DESKTOP}" = "yes" ] && ROOTFS_ARGS="${ROOTFS_ARGS} --desktop"
    [ "${BUILD_MINIMAL}" = "yes" ] && ROOTFS_ARGS="${ROOTFS_ARGS} --minimal"
    $DC -f "${PROJECT_ROOT}/docker-compose.yml" exec --user root -e RELEASE="${RELEASE}" -e BRANCH="${BRANCH}" -e BUILD_DESKTOP="${BUILD_DESKTOP}" -e BUILD_MINIMAL="${BUILD_MINIMAL}" -e INCREMENTAL_BUILD_ROOTFS="${INCREMENTAL_BUILD_ROOTFS}" microslam-builder bash -c 'cd /MicroSLAM-SDK && ./scripts/build-rootfs.sh '"${ROOTFS_ARGS}"
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

    $DC -f "${PROJECT_ROOT}/docker-compose.yml" exec --user root microslam-builder bash -c 'cd /MicroSLAM-SDK && ./scripts/package-image.sh'
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
