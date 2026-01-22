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
rm -rf "${OUTPUT_DIR}"/{boot/,dtb/,modules/,header/,packages/}
mkdir -p "${OUTPUT_DIR}"/{boot/,dtb/rockchip/,modules/,header/,packages/}

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

# 10.5. 使用 olddefconfig 生成完整配置（参考 Armbian 方法）
# 这将基于现有配置和内核默认值填充所有缺失的配置项，避免交互式提示
echo -e "${INFO} 使用 olddefconfig 生成完整配置..."
make ${MAKE_SET_STRING} olddefconfig
if [ $? -ne 0 ]; then
    echo -e "${WARNING} olddefconfig 执行失败，继续构建..."
else
    echo -e "${SUCCESS} 配置已更新为完整配置"
fi

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

# 15.5. 安装内核头文件（参考 amlogic-s9xxx-armbian-new）
echo -e "${INFO} 安装内核头文件..."
make ${MAKE_SET_STRING} headers_install INSTALL_HDR_PATH="${OUTPUT_DIR}/header"
if [ $? -ne 0 ]; then
    echo -e "${WARNING} 内核头文件安装失败，继续构建..."
else
    echo -e "${SUCCESS} 内核头文件安装成功"
fi

# 16. 获取内核版本名称
KERNEL_OUTNAME=$(ls -1 "${OUTPUT_DIR}/modules/lib/modules/" 2>/dev/null | head -1)
if [ -z "${KERNEL_OUTNAME}" ]; then
    echo -e "${WARNING} 无法确定内核版本名称，使用默认值"
    KERNEL_OUTNAME="6.1.0"
fi
echo -e "${INFO} 内核版本名称: ${KERNEL_OUTNAME}"

# 17. 复制内核镜像和相关文件到 boot 目录（参考 amlogic-s9xxx-armbian-new）
if [ -f "arch/${ARCH}/boot/Image" ]; then
    # 复制 Image 和 vmlinuz（参考第 698 行）
    cp -f "arch/${ARCH}/boot/Image" "${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_OUTNAME}"
    cp -f "arch/${ARCH}/boot/Image" "${OUTPUT_DIR}/boot/Image"
    echo -e "${SUCCESS} 复制内核镜像完成"
else
    echo -e "${ERROR} 未找到内核镜像: arch/${ARCH}/boot/Image"
    exit 1
fi

# 17.5. 复制内核配置文件和 System.map（参考第 696-697 行）
if [ -f "System.map" ]; then
    cp -f "System.map" "${OUTPUT_DIR}/boot/System.map-${KERNEL_OUTNAME}"
    echo -e "${SUCCESS} 复制 System.map 完成"
fi

if [ -f ".config" ]; then
    cp -f ".config" "${OUTPUT_DIR}/boot/config-${KERNEL_OUTNAME}"
    echo -e "${SUCCESS} 复制内核配置文件完成"
fi

# 17.6. 生成 uInitrd 和 initrd.img（可选，如果系统支持 update-initramfs）
# 注意：在交叉编译环境中，这通常需要目标系统的 rootfs
# 如果无法生成，boot.cmd 已经支持可选加载 uInitrd
# 在 Docker 容器内，需要先安装 initramfs-tools 和 u-boot-tools
echo -e "${INFO} 检查 uInitrd 生成环境..."

# 检查并安装 initramfs-tools（如果需要）
if ! command -v update-initramfs >/dev/null 2>&1; then
    echo -e "${INFO} update-initramfs 不存在，尝试安装 initramfs-tools..."
    if command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y initramfs-tools >/dev/null 2>&1 || echo -e "${WARNING} 无法安装 initramfs-tools"
    fi
fi

# 检查并安装 u-boot-tools（如果需要，用于 mkimage）
if ! command -v mkimage >/dev/null 2>&1; then
    echo -e "${INFO} mkimage 不存在，尝试安装 u-boot-tools..."
    if command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        sudo apt-get install -y u-boot-tools >/dev/null 2>&1 || echo -e "${WARNING} 无法安装 u-boot-tools"
    fi
fi

if command -v update-initramfs >/dev/null 2>&1 && command -v mkimage >/dev/null 2>&1; then
    echo -e "${INFO} 尝试生成 uInitrd 和 initrd.img..."
    
    # 确保必要目录存在（使用 sudo）
    if command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p /boot /usr/lib/modules
    else
        mkdir -p /boot /usr/lib/modules
    fi
    
    # 备份当前 /boot 文件
    BOOT_BACKUP="/tmp/boot_backup_$$"
    mkdir -p "${BOOT_BACKUP}"
    if command -v sudo >/dev/null 2>&1; then
        sudo mv -f /boot/{config-*,initrd.img-*,System.map-*,vmlinuz-*,uInitrd*,*Image} "${BOOT_BACKUP}/" 2>/dev/null || true
    else
        mv -f /boot/{config-*,initrd.img-*,System.map-*,vmlinuz-*,uInitrd*,*Image} "${BOOT_BACKUP}/" 2>/dev/null || true
    fi
    
    # 复制文件到 /boot（使用 sudo）
    if command -v sudo >/dev/null 2>&1; then
        sudo cp -f "${OUTPUT_DIR}/boot/System.map-${KERNEL_OUTNAME}" /boot/System.map-${KERNEL_OUTNAME}
        sudo cp -f "${OUTPUT_DIR}/boot/config-${KERNEL_OUTNAME}" /boot/config-${KERNEL_OUTNAME}
        sudo cp -f "${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_OUTNAME}" /boot/vmlinuz-${KERNEL_OUTNAME}
        sudo cp -f "${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_OUTNAME}" /boot/Image
    else
        cp -f "${OUTPUT_DIR}/boot/System.map-${KERNEL_OUTNAME}" /boot/System.map-${KERNEL_OUTNAME}
        cp -f "${OUTPUT_DIR}/boot/config-${KERNEL_OUTNAME}" /boot/config-${KERNEL_OUTNAME}
        cp -f "${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_OUTNAME}" /boot/vmlinuz-${KERNEL_OUTNAME}
        cp -f "${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_OUTNAME}" /boot/Image
    fi
    
    # 复制模块到 /usr/lib/modules（使用 sudo）
    MODULES_BACKUP="/tmp/modules_backup_$$"
    mkdir -p "${MODULES_BACKUP}"
    if command -v sudo >/dev/null 2>&1; then
        sudo mv -f /usr/lib/modules/$(uname -r) "${MODULES_BACKUP}/" 2>/dev/null || true
        sudo mkdir -p /usr/lib/modules
        sudo cp -rf "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" /usr/lib/modules/
    else
        mv -f /usr/lib/modules/$(uname -r) "${MODULES_BACKUP}/" 2>/dev/null || true
        mkdir -p /usr/lib/modules
        cp -rf "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" /usr/lib/modules/
    fi
    
    # 生成 initrd.img（使用 sudo）
    cd /boot
    if command -v sudo >/dev/null 2>&1; then
        sudo update-initramfs -c -k ${KERNEL_OUTNAME} 2>&1 | grep -v "^W:" || echo -e "${WARNING} update-initramfs 执行失败，跳过 uInitrd 生成"
    else
        update-initramfs -c -k ${KERNEL_OUTNAME} 2>&1 | grep -v "^W:" || echo -e "${WARNING} update-initramfs 执行失败，跳过 uInitrd 生成"
    fi
    
    # 使用 mkimage 将 initrd.img 转换为 uInitrd（使用 sudo）
    if [ -f "initrd.img-${KERNEL_OUTNAME}" ]; then
        echo -e "${INFO} 将 initrd.img 转换为 uInitrd..."
        if command -v sudo >/dev/null 2>&1; then
            sudo mkimage -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 \
                -n initramfs-${KERNEL_OUTNAME} -d initrd.img-${KERNEL_OUTNAME} \
                uInitrd-${KERNEL_OUTNAME} >/dev/null 2>&1
        else
            mkimage -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 \
                -n initramfs-${KERNEL_OUTNAME} -d initrd.img-${KERNEL_OUTNAME} \
                uInitrd-${KERNEL_OUTNAME} >/dev/null 2>&1
        fi
        
        if [ -f "uInitrd-${KERNEL_OUTNAME}" ]; then
            echo -e "${SUCCESS} uInitrd 生成成功"
        else
            echo -e "${WARNING} uInitrd 转换失败"
        fi
    fi
    
    # 复制生成的 uInitrd 和 initrd.img 回输出目录（使用 sudo）
    if [ -f "uInitrd-${KERNEL_OUTNAME}" ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo cp -f uInitrd-${KERNEL_OUTNAME} "${OUTPUT_DIR}/boot/" 2>/dev/null || true
        else
            cp -f uInitrd-${KERNEL_OUTNAME} "${OUTPUT_DIR}/boot/" 2>/dev/null || true
        fi
    fi
    if [ -f "initrd.img-${KERNEL_OUTNAME}" ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo cp -f initrd.img-${KERNEL_OUTNAME} "${OUTPUT_DIR}/boot/" 2>/dev/null || true
        else
            cp -f initrd.img-${KERNEL_OUTNAME} "${OUTPUT_DIR}/boot/" 2>/dev/null || true
        fi
    fi
    
    # 恢复 /boot 和 /usr/lib/modules（使用 sudo）
    if command -v sudo >/dev/null 2>&1; then
        sudo mv -f *${KERNEL_OUTNAME} "${OUTPUT_DIR}/boot/" 2>/dev/null || true
        sudo mv -f "${BOOT_BACKUP}"/* /boot/ 2>/dev/null || true
        sudo rm -rf /usr/lib/modules/${KERNEL_OUTNAME}
        sudo mv -f "${MODULES_BACKUP}"/* /usr/lib/modules/ 2>/dev/null || true
    else
        mv -f *${KERNEL_OUTNAME} "${OUTPUT_DIR}/boot/" 2>/dev/null || true
        mv -f "${BOOT_BACKUP}"/* /boot/ 2>/dev/null || true
        rm -rf /usr/lib/modules/${KERNEL_OUTNAME}
        mv -f "${MODULES_BACKUP}"/* /usr/lib/modules/ 2>/dev/null || true
    fi
    rm -rf "${BOOT_BACKUP}" "${MODULES_BACKUP}"
    cd - > /dev/null
else
    echo -e "${WARNING} 无法生成 uInitrd（需要 update-initramfs 和 mkimage），boot.cmd 已支持可选加载"
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

# 19. 打包内核文件（参考 amlogic-s9xxx-armbian-new 格式）
echo -e "${INFO} 开始打包内核文件..."
PACKAGE_DIR="${OUTPUT_DIR}/packages/${KERNEL_OUTNAME}"
mkdir -p "${PACKAGE_DIR}"

# 19.1. 打包 boot 文件（参考 amlogic-s9xxx-armbian-new 第 808-813 行）
echo -e "${INFO} 打包 boot 文件..."
cd "${OUTPUT_DIR}/boot"
# 移除可能的 dtb-* 文件（参考第 809 行）
rm -rf dtb-* 2>/dev/null || true
# 设置可执行权限（参考第 810 行）
chmod +x * 2>/dev/null || true
# 打包所有文件（参考第 811 行）
if [ "$(ls -A . 2>/dev/null)" ]; then
    tar -czf "${PACKAGE_DIR}/boot-${KERNEL_OUTNAME}.tar.gz" *
    echo -e "${SUCCESS} boot 文件打包完成: boot-${KERNEL_OUTNAME}.tar.gz"
else
    echo -e "${WARNING} boot 目录为空，跳过打包"
fi

# 19.2. 打包 dtb 文件
echo -e "${INFO} 打包 dtb 文件..."
if [ -d "${OUTPUT_DIR}/dtb/rockchip" ] && [ "$(ls -A ${OUTPUT_DIR}/dtb/rockchip 2>/dev/null)" ]; then
    cd "${OUTPUT_DIR}/dtb"
    tar -czf "${PACKAGE_DIR}/dtb-rockchip-${KERNEL_OUTNAME}.tar.gz" rockchip/
    echo -e "${SUCCESS} dtb 文件打包完成: dtb-rockchip-${KERNEL_OUTNAME}.tar.gz"
else
    echo -e "${WARNING} 未找到 dtb 文件，跳过打包"
fi

# 19.3. 打包 modules 文件
echo -e "${INFO} 打包 modules 文件..."
if [ -d "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" ]; then
    cd "${OUTPUT_DIR}/modules"
    tar -czf "${PACKAGE_DIR}/modules-${KERNEL_OUTNAME}.tar.gz" lib/modules/${KERNEL_OUTNAME}/
    echo -e "${SUCCESS} modules 文件打包完成: modules-${KERNEL_OUTNAME}.tar.gz"
else
    echo -e "${WARNING} 未找到 modules 文件，跳过打包"
fi

# 19.4. 打包 header 文件（参考 amlogic-s9xxx-armbian-new 第 820-823 行）
echo -e "${INFO} 打包 header 文件..."
# make headers_install 会在 INSTALL_HDR_PATH 下创建 usr/include 等目录
# 参考实现直接打包 header 目录的所有内容
if [ -d "${OUTPUT_DIR}/header" ] && [ "$(ls -A ${OUTPUT_DIR}/header 2>/dev/null)" ]; then
    cd "${OUTPUT_DIR}/header"
    tar -czf "${PACKAGE_DIR}/header-${KERNEL_OUTNAME}.tar.gz" *
    echo -e "${SUCCESS} header 文件打包完成: header-${KERNEL_OUTNAME}.tar.gz"
else
    echo -e "${WARNING} 未找到 header 文件，跳过打包"
fi

cd - > /dev/null

# 19.5. 生成 sha256sums 文件
echo -e "${INFO} 生成 sha256sums 文件..."
if [ -d "${PACKAGE_DIR}" ] && [ "$(ls -A ${PACKAGE_DIR}/*.tar.gz 2>/dev/null)" ]; then
    cd "${PACKAGE_DIR}"
    sha256sum *.tar.gz > sha256sums 2>/dev/null || true
    echo -e "${SUCCESS} sha256sums 文件生成完成"
    cd - > /dev/null
else
    echo -e "${WARNING} 未找到打包文件，跳过 sha256sums 生成"
fi

# 20. 检查输出
echo -e "${INFO} 检查输出文件..."
if [ -f "${OUTPUT_DIR}/boot/Image" ] && [ -d "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" ]; then
    echo -e "${SUCCESS} Kernel构建完成！"
    echo -e "${INFO} 输出文件位置: ${OUTPUT_DIR}"
    echo -e "${INFO} 内核镜像: ${OUTPUT_DIR}/boot/Image"
    echo -e "${INFO} 设备树文件: ${OUTPUT_DIR}/dtb/rockchip/"
    echo -e "${INFO} 内核模块: ${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}/"
    if [ -d "${OUTPUT_DIR}/header" ] && [ "$(ls -A ${OUTPUT_DIR}/header 2>/dev/null)" ]; then
        echo -e "${INFO} 内核头文件: ${OUTPUT_DIR}/header/"
    fi
    if [ -d "${PACKAGE_DIR}" ]; then
        echo -e "${INFO} 打包文件: ${PACKAGE_DIR}/"
        ls -lh "${PACKAGE_DIR}"/*.tar.gz 2>/dev/null | head -5 || true
    fi
    ls -lh "${OUTPUT_DIR}/boot/Image" 2>/dev/null || true
    ls -lh "${OUTPUT_DIR}/dtb/rockchip"/*.dtb 2>/dev/null | head -5 || true
    echo -e "${INFO} 模块数量: $(find "${OUTPUT_DIR}/modules/lib/modules/${KERNEL_OUTNAME}" -name "*.ko" | wc -l)"
else
    echo -e "${WARNING} 输出文件不完整，请检查构建日志"
fi

echo -e "${SUCCESS} Kernel构建流程完成"
