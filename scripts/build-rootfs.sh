#!/bin/bash
#================================================================================================
#
# MicroSLAM RootFS Build Script
# 手动实现 RootFS 构建流程，完全跳过 compile.sh 和 artifact 系统，不调用 uboot/kernel 相关脚本
#
#================================================================================================

set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 路径配置
ARMBIAN_DIR="${PROJECT_ROOT}/repos/armbian-build"
CONFIGS_DIR="${PROJECT_ROOT}/configs"
OUTPUT_DIR="${PROJECT_ROOT}/output/rootfs"
USERPATCHES_DIR="${PROJECT_ROOT}/userpatches"

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

# 默认参数
RELEASE="${RELEASE:-noble}"
BRANCH="${BRANCH:-current}"
BUILD_DESKTOP="${BUILD_DESKTOP:-no}"
BUILD_MINIMAL="${BUILD_MINIMAL:-no}"
INCREMENTAL_BUILD_ROOTFS="${INCREMENTAL_BUILD_ROOTFS:-yes}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
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
        *)
            echo -e "${WARNING} 未知参数: $1"
            shift
            ;;
    esac
done

echo -e "${STEPS} 开始构建MicroSLAM RootFS（手动实现，跳过 compile.sh）..."

# 1. 检查Armbian仓库是否存在（init-repos 已由 build.sh 在宿主机先执行）
if [ ! -d "${ARMBIAN_DIR}" ]; then
    echo -e "${ERROR} armbian/build 仓库不存在，请先运行 init-repos.sh"
    exit 1
fi

# 3. 应用补丁和配置（从 configs 生成所有 userpatches 内容）
# 若 BUILD_DESKTOP=yes 则传入 --desktop，使生成的板级配置包含 DESKTOP_ENVIRONMENT（否则子进程无法继承未 export 的变量）
echo -e "${INFO} 应用 MicroSLAM 补丁和配置..."
if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
    "${SCRIPT_DIR}/apply-patches.sh" --desktop
else
    "${SCRIPT_DIR}/apply-patches.sh"
fi

# 4. 创建必要的目录
echo -e "${INFO} 创建必要的构建目录..."
mkdir -p "${ARMBIAN_DIR}/output/images" \
         "${ARMBIAN_DIR}/output/debs" \
         "${ARMBIAN_DIR}/output/logs" \
         "${ARMBIAN_DIR}/cache" \
         "${ARMBIAN_DIR}/.tmp" \
         "${OUTPUT_DIR}"

# 5. 切换到 Armbian 目录并加载 Armbian 库
echo -e "${INFO} 加载 Armbian 构建系统..."
cd "${ARMBIAN_DIR}"

# 设置 SRC 变量（Armbian 构建系统需要）
export SRC="${ARMBIAN_DIR}"

# 检查 lib/single.sh 是否存在
if [[ ! -f "${SRC}/lib/single.sh" ]]; then
    echo -e "${ERROR} 缺少 Armbian 构建目录结构，请检查 ${SRC}/lib/single.sh"
    exit 255
fi

# 加载 Armbian 核心库
source "${SRC}/lib/single.sh"

# 覆盖 rootfs 打包函数：保留 /home 内容（不修改 Armbian 源码）
function create_new_rootfs_cache_tarball() {
    # validate cache_fname is set
    [[ -n "${cache_fname}" ]] || exit_with_error "create_new_rootfs_cache_tarball: cache_fname is not set"
    # validate SDCARD is set
    [[ -n "${SDCARD}" ]] || exit_with_error "create_new_rootfs_cache_tarball: SDCARD is not set"
    # validate cache_name is set
    [[ -n "${cache_name}" ]] || exit_with_error "create_new_rootfs_cache_tarball: cache_name is not set"

    # Show the disk space usage of the rootfs; use only host-side tools, as qemu binary is already undeployed from chroot
    display_alert "Disk space usage of rootfs" "${RELEASE}:: ${cache_name}" "info"
    run_host_command_logged "cd ${SDCARD} && " du -h -d 4 -x "." "| sort -h | tail -20"
    wait_for_disk_sync "after disk-space usage report of rootfs"

    declare compression_ratio_rootfs="${ROOTFS_COMPRESSION_RATIO:-"5"}"

    display_alert "zstd tarball of rootfs" "${RELEASE}:: ${cache_name} :: compression ${compression_ratio_rootfs}" "info"
    tar cp --xattrs --directory="$SDCARD"/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' \
        --exclude='./tmp/*' --exclude='./sys/*' --exclude='./root/*' . |
        pv -p -b -r -s "$(du -sb "$SDCARD"/ | cut -f1)" -N "$(logging_echo_prefix_for_pv "store_rootfs") $cache_name" |
        zstdmt "-${compression_ratio_rootfs}" -c > "${cache_fname}"

    declare -a pv_tar_zstdmt_pipe_status=("${PIPESTATUS[@]}") # capture and the pipe_status array from PIPESTATUS
    declare one_pipe_status
    for one_pipe_status in "${pv_tar_zstdmt_pipe_status[@]}"; do
        if [[ "$one_pipe_status" != "0" ]]; then
            exit_with_error "create_new_rootfs_cache_tarball: compress: ${cache_fname} failed (${pv_tar_zstdmt_pipe_status[*]}) - out of disk space?"
        fi
    done

    wait_for_disk_sync "after zstd tarball rootfs"

    # get the human readable size of the cache
    local cache_size
    cache_size=$(du -sh "${cache_fname}" | cut -f1)

    display_alert "rootfs cache created" "${cache_fname} [${cache_size}]" "info"
}

# 6. 设置 Armbian 构建系统必需的目录变量（必须在配置之前设置）
echo -e "${INFO} 设置 Armbian 构建系统目录变量..."
declare -g -r DEST="${SRC}/output"
declare -g -r USERPATCHES_PATH="${SRC}/userpatches"
declare -g -r WORKDIR_BASE_TMP="${SRC}/.tmp"

# 生成构建 UUID（用于创建唯一的临时目录）
if command -v uuidgen >/dev/null 2>&1; then
    declare -g ARMBIAN_BUILD_UUID="$(uuidgen)"
else
    declare -g ARMBIAN_BUILD_UUID="no-uuidgen-${RANDOM}-$((1 + $RANDOM % 10))$((1 + $RANDOM % 10))$((1 + $RANDOM % 10))$((1 + $RANDOM % 10))"
fi
declare -g -r ARMBIAN_BUILD_UUID="${ARMBIAN_BUILD_UUID}"

# 设置工作目录变量
declare -g -r WORKDIR="${WORKDIR_BASE_TMP}/work-${ARMBIAN_BUILD_UUID}"
declare -g -r LOGDIR="${WORKDIR_BASE_TMP}/logs-${ARMBIAN_BUILD_UUID}"
declare -g -r EXTENSION_MANAGER_TMP_DIR="${WORKDIR_BASE_TMP}/extensions-${ARMBIAN_BUILD_UUID}"
declare -g -r SDCARD="${WORKDIR_BASE_TMP}/rootfs-${ARMBIAN_BUILD_UUID}"
declare -g -r MOUNT="${WORKDIR_BASE_TMP}/mount-${ARMBIAN_BUILD_UUID}"
declare -g -r DESTIMG="${WORKDIR_BASE_TMP}/image-${ARMBIAN_BUILD_UUID}"

# 创建必要的目录
mkdir -p "${DEST}" "${USERPATCHES_PATH}" "${WORKDIR_BASE_TMP}"

# 设置日志 CLI ID（用于日志文件命名）
declare -r -g ARMBIAN_LOG_CLI_ID="${ARMBIAN_LOG_CLI_ID:-rootfs}"

# 初始化日志系统（需要在 DEST 设置之后）
logging_init

# 初始化 traps
traps_init

# 准备日志目录（如果需要 tmpfs）
prepare_tmpfs_for "LOGDIR" "${LOGDIR}" || true

# 添加清理处理器（但不启动日志记录，让配置函数自己管理）
add_cleanup_handler trap_handler_cleanup_logging || true
add_cleanup_handler trap_handler_reset_output_owner || true

# 7. 设置环境变量（强制跳过 uboot/kernel，必须在配置之前设置）
# 注意：这些变量必须在 source lib/single.sh 之后、prep_conf 之前设置，确保 Armbian 配置系统能读取到
echo -e "${INFO} 设置构建环境变量..."
export BOARD="microslam"
export BRANCH="${BRANCH}"
export RELEASE="${RELEASE}"
export ARCH="arm64"
export BUILD_MINIMAL="${BUILD_MINIMAL}"
export BUILD_DESKTOP="${BUILD_DESKTOP}"

# 强制跳过 uboot 和 kernel（必须在配置之前设置）
export BOOTCONFIG="none"
export KERNELSOURCE="none"
export BOOTSOURCE="none"
export SKIP_ARMBIAN_REPO="yes"  # rootfs 构建时不使用 Armbian repo

# 设置其他必要的环境变量
export COLUMNS="${COLUMNS:-160}"
export SKIP_BINFMT_CHECK="${SKIP_BINFMT_CHECK:-yes}"
export PREFER_DOCKER=no
export ARMBIAN_RUNNING_IN_CONTAINER=yes
export USE_CCACHE=no
export NEEDS_BINFMT="yes"  # 确保 binfmt 在 prepare_host 中安装

# 设置 chroot 环境中使用的 DNS 服务器
# 在 Docker 容器中，必须使用 Docker 的内嵌 DNS 服务器（127.0.0.11）
# 默认的 1.0.0.1（Cloudflare DNS）在容器中无法直接访问
export NAMESERVER="${NAMESERVER:-127.0.0.11}"

# 7.1. 如果 BUILD_DESKTOP=yes，确保板级配置中的 DESKTOP_ENVIRONMENT 被读取
# Armbian 的 prep_conf 会 source 板级配置文件，但如果 DESKTOP_ENVIRONMENT 在文件中已设置，
# 需要确保它在 prep_conf 执行时能被正确读取
# 注意：板级配置文件中的变量会在 source 时自动生效，但为了确保 aggregation 能正确识别，
# 我们在这里显式读取板级配置文件中的 DESKTOP_ENVIRONMENT（如果存在）
if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
    BOARD_CONFIG_FILE="${USERPATCHES_PATH}/config/boards/${BOARD}.conf"
    if [[ -f "${BOARD_CONFIG_FILE}" ]]; then
        # 临时 source 板级配置文件以读取 DESKTOP_ENVIRONMENT（如果已设置）
        # 使用 subshell 避免污染当前环境
        DESKTOP_ENV_FROM_CONFIG=$(grep -E "^DESKTOP_ENVIRONMENT=" "${BOARD_CONFIG_FILE}" | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "")
        if [[ -n "${DESKTOP_ENV_FROM_CONFIG}" ]]; then
            export DESKTOP_ENVIRONMENT="${DESKTOP_ENV_FROM_CONFIG}"
            echo -e "${INFO} 从板级配置读取 DESKTOP_ENVIRONMENT: ${DESKTOP_ENVIRONMENT}"
        fi
        # 同样读取 DESKTOP_ENVIRONMENT_CONFIG_NAME
        DESKTOP_CONFIG_NAME_FROM_CONFIG=$(grep -E "^DESKTOP_ENVIRONMENT_CONFIG_NAME=" "${BOARD_CONFIG_FILE}" | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "")
        if [[ -n "${DESKTOP_CONFIG_NAME_FROM_CONFIG}" ]]; then
            export DESKTOP_ENVIRONMENT_CONFIG_NAME="${DESKTOP_CONFIG_NAME_FROM_CONFIG}"
            echo -e "${INFO} 从板级配置读取 DESKTOP_ENVIRONMENT_CONFIG_NAME: ${DESKTOP_ENVIRONMENT_CONFIG_NAME}"
        fi
    fi
fi

# 8. 执行配置准备（最小配置，只配置 rootfs，不配置 uboot/kernel）
# ENABLE_EXTENSIONS 必须在 prep_conf 之前 export，initialize_extension_manager 会读取此变量。
# 不能用 use_board=yes（会 source microslam.conf 覆盖 BOOTCONFIG/KERNELSOURCE 导致 uboot artifact 被要求）。
# 直接在这里显式设置 ENABLE_EXTENSIONS，extension manager 初始化时会自动加载。
export ENABLE_EXTENSIONS="microslam-uboot microslam-loop-fix microslam-systemd-fix"
echo -e "${INFO} 执行配置准备（跳过 uboot/kernel 配置）..."
prep_conf_main_only_rootfs_ni < /dev/null

# 8.1. 验证 DESKTOP_ENVIRONMENT 是否已正确设置（调试用）
if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
    if [[ -n "${DESKTOP_ENVIRONMENT:-}" ]]; then
        echo -e "${SUCCESS} DESKTOP_ENVIRONMENT 已设置: ${DESKTOP_ENVIRONMENT}"
        if [[ -n "${DESKTOP_ENVIRONMENT_CONFIG_NAME:-}" ]]; then
            echo -e "${SUCCESS} DESKTOP_ENVIRONMENT_CONFIG_NAME 已设置: ${DESKTOP_ENVIRONMENT_CONFIG_NAME}"
        else
            echo -e "${WARNING} DESKTOP_ENVIRONMENT_CONFIG_NAME 未设置"
        fi
    else
        echo -e "${ERROR} BUILD_DESKTOP=yes 但 DESKTOP_ENVIRONMENT 仍未设置，请检查板级配置文件"
        exit 1
    fi
fi

# 9. 准备构建环境（准备主机、聚合包列表等）
# main_default_start_build 会自动运行 aggregation（如果被标记）
echo -e "${INFO} 准备构建环境..."
main_default_start_build

# 10. 验证 aggregation 已运行（artifact 系统会在内部计算 rootfs cache ID）
echo -e "${INFO} 验证 aggregation 已运行..."
assert_requires_aggregation  # 确保 aggregation 已运行（会生成 AGGREGATED_ROOTFS_HASH）
# 注意：不要在这里调用 calculate_rootfs_cache_id，让 artifact 系统在 artifact_rootfs_prepare_version 中调用

# 11. 使用 artifact 系统获取或创建 rootfs cache（自动检查缓存）
# 如果 INCREMENTAL_BUILD_ROOTFS="no"（即 -fc），强制全量构建，清理 rootfs 缓存
if [ "${INCREMENTAL_BUILD_ROOTFS}" = "no" ]; then
    echo -e "${INFO} 强制全量构建：清理 rootfs 缓存..."
    if [ -d "${ARMBIAN_DIR}/cache/rootfs" ]; then
        rm -rf "${ARMBIAN_DIR}/cache/rootfs"/*
        echo -e "${SUCCESS} Rootfs 缓存已清理"
    fi
fi

# get_or_create_rootfs_cache_chroot_sdcard 会：
# - 调用 WHAT="rootfs" build_artifact_for_image（自动检查缓存，如果存在则使用，不存在则创建）
# - 调用 prepare_rootfs_build_params_and_trap（设置清理处理器）
# - 调用 extract_rootfs_artifact（提取 rootfs 到 SDCARD）
# 注意：不要用 do_with_logging 包装，因为 build_artifact_for_image 内部已经管理了日志段
echo -e "${INFO} 获取或创建 rootfs cache（使用 artifact 系统缓存机制）..."
get_or_create_rootfs_cache_chroot_sdcard

# 验证 rootfs cache 文件是否存在（artifact_final_file 由 build_artifact_for_image 设置）
if [[ -z "${artifact_final_file:-}" ]] || [[ ! -f "${artifact_final_file}" ]]; then
    echo -e "${ERROR} Rootfs cache 文件不存在: ${artifact_final_file:-未设置}"
    exit 1
fi

# 15. 部署 QEMU 二进制文件并挂载 chroot
echo -e "${INFO} 部署 QEMU 并挂载 chroot..."
LOG_SECTION="deploy_qemu_binary_to_chroot_image" do_with_logging deploy_qemu_binary_to_chroot "${SDCARD}" "image"
LOG_SECTION="mount_chroot_sdcard" do_with_logging mount_chroot "${SDCARD}"

# 15.3. 清理残留的 apt lock 文件（从 rootfs cache 提取后可能残留）
echo -e "${INFO} 清理残留的 apt lock 文件..."
# 清理所有 apt/dpkg 锁文件
for lock_file in "${SDCARD}/var/cache/apt/archives/lock" \
                 "${SDCARD}/var/lib/apt/lists/lock" \
                 "${SDCARD}/var/lib/dpkg/lock-frontend" \
                 "${SDCARD}/var/lib/dpkg/lock"; do
    if [[ -f "${lock_file}" ]]; then
        display_alert "Removing stale lock" "${lock_file}" "wrn"
        run_host_command_logged rm -f "${lock_file}"
    fi
done

# 确保没有残留的 apt 进程（在 chroot 中）
# 注意：pkill 一次只能接受一个模式，需要分别调用
if chroot_sdcard pgrep -x apt-get >/dev/null 2>&1; then
    display_alert "Killing stale apt-get processes in chroot" "cleaning up" "wrn"
    chroot_sdcard pkill -9 apt-get 2>/dev/null || true
fi
if chroot_sdcard pgrep -x apt >/dev/null 2>&1; then
    display_alert "Killing stale apt processes in chroot" "cleaning up" "wrn"
    chroot_sdcard pkill -9 apt 2>/dev/null || true
fi
if chroot_sdcard pgrep -x dpkg >/dev/null 2>&1; then
    display_alert "Killing stale dpkg processes in chroot" "cleaning up" "wrn"
    chroot_sdcard pkill -9 dpkg 2>/dev/null || true
fi

# 等待进程完全终止
sleep 1

# 再次清理锁文件（防止进程在终止时重新创建）
for lock_file in "${SDCARD}/var/cache/apt/archives/lock" \
                 "${SDCARD}/var/lib/apt/lists/lock" \
                 "${SDCARD}/var/lib/dpkg/lock-frontend" \
                 "${SDCARD}/var/lib/dpkg/lock"; do
    if [[ -f "${lock_file}" ]]; then
        display_alert "Removing lock file after process cleanup" "${lock_file}" "wrn"
        run_host_command_logged rm -f "${lock_file}"
    fi
done

# 15.5. 构建必要的 artifact 包（由于跳过了 artifact 系统，需要手动构建）
# 这些包在 install_distribution_specific 和 install_distribution_agnostic 中需要
echo -e "${INFO} 构建必要的 artifact 包..."
declare -g -A image_artifacts_debs_reversioned=()  # 初始化全局数组

# 辅助函数：构建 artifact 并填充数组
build_and_register_artifact() {
    local artifact_name="$1"
    echo -e "${INFO} 构建 ${artifact_name}..."
    WHAT="${artifact_name}" build_artifact_for_image
    
    # 填充 image_artifacts_debs_reversioned 数组（artifact_map_* 是全局变量）
    for one_artifact_package in "${!artifact_map_packages[@]}"; do
        image_artifacts_debs_reversioned["${one_artifact_package}"]="${artifact_map_debs_reversioned[${one_artifact_package}]}"
        display_alert "Added artifact to image" "${one_artifact_package} -> ${artifact_map_debs_reversioned[${one_artifact_package}]}" "debug"
    done
}

# 构建 fake-ubuntu-advantage-tools（Ubuntu 需要）
if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
    build_and_register_artifact "fake_ubuntu_advantage_tools"
fi

# 构建 armbian-base-files（总是需要）
build_and_register_artifact "armbian-base-files"

# 构建 armbian-firmware（如果 INSTALL_ARMBIAN_FIRMWARE=yes）
if [[ "${INSTALL_ARMBIAN_FIRMWARE:-yes}" == "yes" ]]; then
    if [[ "${BOARD_FIRMWARE_INSTALL:-}" == "-full" ]]; then
        build_and_register_artifact "full_firmware"
    else
        build_and_register_artifact "firmware"
    fi
fi

# 构建 armbian-bsp-cli（总是需要）
build_and_register_artifact "armbian-bsp-cli"

# 构建 armbian-zsh（如果 BUILD_MINIMAL != yes 且不在 PACKAGE_LIST_RM 中）
if [[ "${BUILD_MINIMAL}" != "yes" ]] && [[ "${PACKAGE_LIST_RM:-}" != *armbian-zsh* ]]; then
    build_and_register_artifact "armbian-zsh"
fi

# 构建 armbian-plymouth-theme（如果 PLYMOUTH == yes）
if [[ "${PLYMOUTH:-no}" == "yes" ]]; then
    build_and_register_artifact "armbian-plymouth-theme"
fi

# 构建 armbian-desktop 和 armbian-bsp-desktop（如果 BUILD_DESKTOP == yes 且 DESKTOP_ENVIRONMENT 已设置）
# 注意：如果 BUILD_DESKTOP == yes 但 DESKTOP_ENVIRONMENT 未设置，install_distribution_agnostic 仍会尝试安装它们
# 所以我们需要确保条件一致，或者在没有 DESKTOP_ENVIRONMENT 时禁用 BUILD_DESKTOP
if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
    if [[ -n "${DESKTOP_ENVIRONMENT:-}" ]]; then
        build_and_register_artifact "armbian-desktop"
        build_and_register_artifact "armbian-bsp-desktop"
    else
        # BUILD_DESKTOP == yes 但 DESKTOP_ENVIRONMENT 未设置，这是配置错误
        # 但我们不能在这里退出，因为 install_distribution_agnostic 会尝试安装
        # 所以我们需要构建空的占位符，或者禁用 BUILD_DESKTOP
        echo -e "${WARNING} BUILD_DESKTOP=yes 但 DESKTOP_ENVIRONMENT 未设置，跳过 armbian-desktop 构建"
        echo -e "${WARNING} 注意：install_distribution_agnostic 可能会失败，因为缺少 armbian-desktop 包"
        # 临时禁用 BUILD_DESKTOP 以避免 install_distribution_agnostic 尝试安装
        export BUILD_DESKTOP="no"
    fi
fi

# 16. 安装发行版特定包
# 在安装之前，再次确保 apt lock 文件已清理（防止在构建 artifact 包期间有进程创建了锁）
echo -e "${INFO} 安装发行版特定包前，再次清理 apt lock..."
for lock_file in "${SDCARD}/var/cache/apt/archives/lock" \
                 "${SDCARD}/var/lib/apt/lists/lock" \
                 "${SDCARD}/var/lib/dpkg/lock-frontend" \
                 "${SDCARD}/var/lib/dpkg/lock"; do
    if [[ -f "${lock_file}" ]]; then
        display_alert "Removing lock file before installation" "${lock_file}" "wrn"
        run_host_command_logged rm -f "${lock_file}"
    fi
done

echo -e "${INFO} 安装发行版特定包..."
LOG_SECTION="install_distribution_specific_${RELEASE}" do_with_logging install_distribution_specific

# 17. 安装发行版无关包（会自动跳过 uboot/kernel，因为 BOOTCONFIG="none" 和 KERNELSOURCE="none"）
# 在安装之前，确保 NetworkManager extension 需要的目录存在
# 注意：原始代码会直接执行 cp "${EXTENSION_DIR}/config-nm/netplan/*"，如果通配符没有匹配到文件会失败
# 问题：run_host_command_logged 使用 bash -c "$*"，通配符在子 shell 中展开
# 如果源目录为空，通配符不会匹配任何文件，bash 会保持通配符原样，cp 会尝试复制字面量 "*"，导致失败
# 解决方案：在调用前检查源目录，如果为空则创建占位符文件
echo -e "${INFO} 准备 NetworkManager 配置目录..."
# 确保目标目录存在
run_host_command_logged mkdir -p "${SDCARD}/etc/netplan" "${SDCARD}/etc/NetworkManager/conf.d"

# 检查源目录是否存在且非空，如果为空则创建占位符文件（避免 cp * 失败）
# 注意：根据错误信息，EXTENSION_DIR 可能指向 extensions（而不是 extensions/network）
# 所以路径可能是 ${SRC}/extensions/config-nm/... 或 ${SRC}/extensions/network/config-nm/...
# 如果 EXTENSION_DIR 指向 extensions，我们需要创建符号链接或复制文件到 extensions/config-nm/
declare netplan_config_src_actual="${SRC}/extensions/network/config-nm/netplan"
declare network_manager_config_src_actual="${SRC}/extensions/network/config-nm/NetworkManager"
declare netplan_config_src_expected="${SRC}/extensions/config-nm/netplan"
declare network_manager_config_src_expected="${SRC}/extensions/config-nm/NetworkManager"

# 如果实际路径存在但预期路径不存在，创建符号链接（不修改原始仓库）
if [[ -d "${netplan_config_src_actual}" ]] && [[ ! -d "${netplan_config_src_expected}" ]]; then
    display_alert "Creating symlink for netplan config" "${netplan_config_src_expected} -> ${netplan_config_src_actual}" "debug"
    run_host_command_logged mkdir -p "$(dirname "${netplan_config_src_expected}")"
    run_host_command_logged ln -sfn "../network/config-nm/netplan" "${netplan_config_src_expected}"
fi
if [[ -d "${network_manager_config_src_actual}" ]] && [[ ! -d "${network_manager_config_src_expected}" ]]; then
    display_alert "Creating symlink for NetworkManager config" "${network_manager_config_src_expected} -> ${network_manager_config_src_actual}" "debug"
    run_host_command_logged mkdir -p "$(dirname "${network_manager_config_src_expected}")"
    run_host_command_logged ln -sfn "../network/config-nm/NetworkManager" "${network_manager_config_src_expected}"
fi

# 检查目录是否为空，如果为空则创建占位符文件
for config_src in "${netplan_config_src_actual}" "${netplan_config_src_expected}" "${network_manager_config_src_actual}" "${network_manager_config_src_expected}"; do
    if [[ -d "${config_src}" ]] && [[ -z "$(ls -A "${config_src}" 2>/dev/null)" ]]; then
        display_alert "Config directory is empty, creating placeholder" "${config_src}" "wrn"
        run_host_command_logged touch "${config_src}/.keep"
    fi
done

echo -e "${INFO} 安装发行版无关包（跳过 uboot/kernel）..."
LOG_SECTION="install_distribution_agnostic" do_with_logging install_distribution_agnostic

# 18. 自定义镜像（应用 MicroSLAM 自定义配置）
# 确保 chroot 内能访问 /MicroSLAM-SDK/configs，避免自定义脚本找不到配置
echo -e "${INFO} 准备 MicroSLAM 配置到 chroot..."
run_host_command_logged mkdir -p "${SDCARD}/MicroSLAM-SDK"
run_host_command_logged cp -a "${PROJECT_ROOT}/configs" "${SDCARD}/MicroSLAM-SDK/"

echo -e "${INFO} 自定义镜像..."
LOG_SECTION="customize_image" do_with_logging customize_image

# 清理复制到此的临时配置和debs目录，防止被打包进rootfs影响后续挂载大小
echo -e "${INFO} 清理 chroot 中的 MicroSLAM 临时配置..."
run_host_command_logged rm -rf "${SDCARD}/MicroSLAM-SDK"

# 19. 创建 sources.list 并部署 repo key
echo -e "${INFO} 配置 APT 源..."
create_sources_list_and_deploy_repo_key "image-late" "${RELEASE}" "${SDCARD}/"

# 20. 运行 post-repo 相关步骤
echo -e "${INFO} 运行 post-repo 步骤..."
LOG_SECTION="post_repo_apt_update" do_with_logging post_repo_apt_update

# 运行 post-repo customize hooks（如果有）
if [[ "${SKIP_ARMBIAN_REPO}" != "yes" ]]; then
    LOG_SECTION="post_armbian_repo_customize_image" do_with_logging run_hooks_post_armbian_repo_customize_image
fi
LOG_SECTION="post_repo_customize_image" do_with_logging run_hooks_post_repo_customize_image

# 21. 清理和优化
echo -e "${INFO} 清理和优化 rootfs..."
LOG_SECTION="apt_purge_unneeded_packages_and_clean_apt_caches" do_with_logging apt_purge_unneeded_packages_and_clean_apt_caches
LOG_SECTION="apt_lists_copy_from_host_to_image_and_update" do_with_logging apt_lists_copy_from_host_to_image_and_update
LOG_SECTION="post_debootstrap_tweaks" do_with_logging post_debootstrap_tweaks

# 22. 获取 rootfs 大小
declare -i rootfs_size_mib
rootfs_size_mib=$(du --apparent-size -sm "${SDCARD}" | awk '{print $1}')
display_alert "Actual rootfs size" "${rootfs_size_mib}MiB" ""

# 23. 卸载 QEMU 和 chroot
echo -e "${INFO} 卸载 QEMU 和 chroot..."
LOG_SECTION="undeploy_qemu_binary_from_chroot_image" do_with_logging undeploy_qemu_binary_from_chroot "${SDCARD}" "image"
LOG_SECTION="umount_chroot_sdcard" do_with_logging umount_chroot "${SDCARD}"

# 24. 重新打包 rootfs 为 tar.zst（因为 rootfs 已经被修改：安装了包、自定义等）
# 注意：create_new_rootfs_cache 创建的 tarball 是初始的，我们需要重新打包更新后的 rootfs
echo -e "${INFO} 打包 rootfs 为 tar.zst..."
# 确保 cache_fname 和 cache_name 变量已设置（使用 artifact 系统的命名格式）
# artifact 系统格式：rootfs-${ARCH}-${RELEASE}-${cache_type}_${yyyymm}-${rootfs_cache_id}.tar.zst
# 注意：artifact_name 和 artifact_version 之间使用 _ 分隔符，不是 -
declare yyyymm="$(date +%Y%m)"
declare artifact_name="rootfs-${ARCH}-${RELEASE}-${cache_type}"
declare artifact_version="${yyyymm}-${rootfs_cache_id}"
# 不再覆盖 cache/rootfs 下的干净底包，而是直接保存成带有 microslam 前缀的内容至 OUTPUT_DIR
declare -g artifact_final_file="${OUTPUT_DIR}/microslam-${artifact_name}_${artifact_version}.tar.zst"
declare -g cache_fname="${artifact_final_file}"
declare -g cache_name="microslam-${artifact_name}_${artifact_version}"
LOG_SECTION="create_rootfs_tarball" do_with_logging create_new_rootfs_cache_tarball

# 25. 检查 rootfs 输出文件
echo -e "${INFO} 检查 rootfs 输出文件..."
if [[ -f "${artifact_final_file}" ]]; then
    echo -e "${SUCCESS} RootFS 已创建: $(basename ${artifact_final_file})"
    ls -lh "${artifact_final_file}"
else
    echo -e "${ERROR} RootFS 文件不存在: ${artifact_final_file}"
    echo -e "${ERROR} 请检查 rootfs 打包过程"
    exit 1
fi

# 26. 清理和结束
echo -e "${INFO} 清理构建环境..."
execute_and_remove_cleanup_handler trap_handler_cleanup_rootfs_and_image
main_default_end_build

echo -e "${SUCCESS} RootFS 构建流程完成！"
echo -e "${INFO} 输出文件位置: ${OUTPUT_DIR}"
