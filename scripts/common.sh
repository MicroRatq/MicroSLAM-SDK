#!/bin/bash
#================================================================================================
#
# MicroSLAM Common Functions Library
# 公共函数库，包含工具链管理、增量构建控制等通用功能
#
#================================================================================================

# 颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

#================================================================================================
# 工具链管理函数
#================================================================================================

# 查找并设置交叉编译工具链
# 参数: 架构 (默认: arm64)
# 返回: 设置 CROSS_COMPILE 环境变量
find_cross_compiler() {
    local arch="${1:-arm64}"
    local project_root="${2:-${PROJECT_ROOT}}"
    local armbian_dir="${project_root}/repos/armbian-build"
    
    if [ -z "${CROSS_COMPILE}" ]; then
        # 尝试从Armbian工具链获取
        if [ -d "${armbian_dir}/cache/tools" ]; then
            local toolchain_dir=$(find "${armbian_dir}/cache/tools" -type d \( -name "aarch64-linux-gnu-gcc*" -o -name "gcc-arm-*" \) | head -1)
            if [ -n "${toolchain_dir}" ]; then
                local toolchain_bin="${toolchain_dir}/bin"
                if [ -f "${toolchain_bin}/aarch64-linux-gnu-gcc" ]; then
                    export PATH="${toolchain_bin}:${PATH}"
                    export CROSS_COMPILE="aarch64-linux-gnu-"
                    echo -e "${SUCCESS} 使用Armbian工具链: ${toolchain_bin}"
                    return 0
                fi
            fi
        fi
        
        # 如果还是找不到，尝试系统工具链
        if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
            export CROSS_COMPILE="aarch64-linux-gnu-"
            echo -e "${SUCCESS} 使用系统工具链"
            return 0
        else
            echo -e "${ERROR} 未找到交叉编译工具链，请安装 aarch64-linux-gnu-gcc"
            return 1
        fi
    else
        echo -e "${INFO} 使用指定的交叉编译工具链: ${CROSS_COMPILE}"
        return 0
    fi
}

# 检查交叉编译工具链是否可用
check_cross_compiler() {
    if [ -z "${CROSS_COMPILE}" ]; then
        echo -e "${ERROR} CROSS_COMPILE 未设置"
        return 1
    fi
    
    if ! command -v ${CROSS_COMPILE}gcc >/dev/null 2>&1; then
        echo -e "${ERROR} 交叉编译工具链不可用: ${CROSS_COMPILE}gcc"
        return 1
    fi
    
    echo -e "${SUCCESS} 交叉编译工具链检查通过: ${CROSS_COMPILE}gcc"
    return 0
}

#================================================================================================
# 增量构建控制函数
#================================================================================================

# 检查是否启用增量构建
# 参数: 组件名称 (uboot/kernel)
# 返回: 0=全量构建, 1=增量构建
is_incremental_build() {
    local component="${1}"
    local incremental_var="INCREMENTAL_BUILD_$(echo ${component} | tr '[:lower:]' '[:upper:]')"
    local incremental_value=$(eval echo \$${incremental_var})
    
    if [ "${incremental_value}" = "yes" ]; then
        return 1  # 增量构建
    else
        return 0  # 全量构建
    fi
}

# 执行make clean（如果需要）
# 参数: 组件名称 (uboot/kernel), 源码目录
maybe_make_clean() {
    local component="${1}"
    local source_dir="${2}"
    local make_string="${3}"
    
    if [ -z "${source_dir}" ] || [ ! -d "${source_dir}" ]; then
        echo -e "${ERROR} 源码目录不存在: ${source_dir}"
        return 1
    fi
    
    cd "${source_dir}"
    
    if is_incremental_build "${component}"; then
        # 全量构建：执行清理
        if [ "${component}" = "uboot" ]; then
            echo -e "${INFO} 全量构建：执行 make clean"
            make ${make_string} clean || true
        elif [ "${component}" = "kernel" ]; then
            echo -e "${INFO} 全量构建：执行 make mrproper"
            make ${make_string} mrproper || true
        fi
    else
        # 增量构建：跳过清理
        echo -e "${INFO} 增量构建：跳过 make clean/mrproper"
    fi
    
    return 0
}

#================================================================================================
# 路径和目录管理函数
#================================================================================================

# 获取项目根目录
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    echo "$(cd "${script_dir}/.." && pwd)"
}

# 创建输出目录
create_output_dirs() {
    local project_root="${1:-${PROJECT_ROOT}}"
    local output_dir="${project_root}/output"
    
    mkdir -p "${output_dir}"/{uboot,kernel,rootfs,images}
    echo -e "${SUCCESS} 输出目录已创建: ${output_dir}"
}

# 清理输出目录
clean_output_dirs() {
    local project_root="${1:-${PROJECT_ROOT}}"
    local output_dir="${project_root}/output"
    local component="${2:-all}"
    
    if [ "${component}" = "all" ]; then
        rm -rf "${output_dir}"/*
        echo -e "${SUCCESS} 所有输出目录已清理"
    else
        rm -rf "${output_dir}/${component}"/*
        echo -e "${SUCCESS} ${component} 输出目录已清理"
    fi
}

#================================================================================================
# 日志和输出函数
#================================================================================================

# 打印步骤信息
print_step() {
    echo -e "${STEPS} ${1}"
}

# 打印信息
print_info() {
    echo -e "${INFO} ${1}"
}

# 打印成功信息
print_success() {
    echo -e "${SUCCESS} ${1}"
}

# 打印错误信息
print_error() {
    echo -e "${ERROR} ${1}"
}

# 打印警告信息
print_warning() {
    echo -e "${WARNING} ${1}"
}

#================================================================================================
# 文件检查函数
#================================================================================================

# 检查文件是否存在
check_file_exists() {
    local file="${1}"
    local component="${2:-unknown}"
    
    if [ ! -f "${file}" ]; then
        echo -e "${ERROR} ${component} 输出文件不存在: ${file}"
        return 1
    fi
    
    return 0
}

# 检查目录是否存在
check_dir_exists() {
    local dir="${1}"
    local component="${2:-unknown}"
    
    if [ ! -d "${dir}" ]; then
        echo -e "${ERROR} ${component} 输出目录不存在: ${dir}"
        return 1
    fi
    
    return 0
}

# 检查必要的输出文件
check_build_outputs() {
    local component="${1}"
    local project_root="${2:-${PROJECT_ROOT}}"
    local output_dir="${project_root}/output/${component}"
    local missing_files=()
    
    case "${component}" in
        uboot)
            check_file_exists "${output_dir}/u-boot.itb" "U-Boot" || missing_files+=("u-boot.itb")
            ;;
        kernel)
            check_file_exists "${output_dir}/boot/Image" "Kernel" || missing_files+=("boot/Image")
            check_dir_exists "${output_dir}/modules/lib/modules" "Kernel" || missing_files+=("modules")
            ;;
        rootfs)
            local rootfs_tar=$(find "${output_dir}" -name "*rootfs*.tar*" -type f | head -1)
            if [ -z "${rootfs_tar}" ]; then
                missing_files+=("rootfs tar")
            fi
            ;;
    esac
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo -e "${ERROR} ${component} 构建输出不完整，缺少: ${missing_files[*]}"
        return 1
    fi
    
    echo -e "${SUCCESS} ${component} 构建输出检查通过"
    return 0
}

#================================================================================================
# 参数解析函数
#================================================================================================

# 解析增量构建参数
parse_incremental_args() {
    local component="${1}"
    local incremental_var="INCREMENTAL_BUILD_$(echo ${component} | tr '[:lower:]' '[:upper:]')"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --incremental)
                export ${incremental_var}="yes"
                echo -e "${INFO} ${component} 增量构建模式：跳过 make clean/mrproper"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

# 解析线程数参数
parse_threads_args() {
    local default_threads="${CPUTHREADS:-$(nproc)}"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -j|--threads)
                export CPUTHREADS="$2"
                echo -e "${INFO} 设置编译线程数为: ${CPUTHREADS}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [ -z "${CPUTHREADS}" ]; then
        export CPUTHREADS="${default_threads}"
    fi
}
