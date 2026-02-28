FROM ubuntu:22.04

# 设置非交互式环境（避免apt安装时卡在时区选择）
ENV DEBIAN_FRONTEND=noninteractive

# 安装Armbian build所需的基础依赖
# 参考: https://docs.armbian.com/Developer-Guide_Build-Preparation/
# 完整依赖列表来自: lib/functions/host/prepare-host.sh
RUN apt-get update && apt-get install -y \
    # 基础构建工具
    git make gcc g++ bison flex swig \
    # 开发库
    libssl-dev libncurses-dev bc \
    python3-dev python3-setuptools python3-pip \
    device-tree-compiler libgnutls28-dev \
    # Armbian build 核心依赖（来自 prepare-host.sh）
    bsdextrautils \
    ccache \
    dwarves \
    gettext \
    imagemagick \
    jq \
    libbison-dev libelf-dev libfdt-dev libmpc-dev libfl-dev \
    lz4 \
    libusb-1.0-0-dev \
    lsof \
    psmisc \
    ntpsec-ntpdate \
    patchutils \
    pkg-config \
    arch-test \
    udev \
    uuid-dev \
    zlib1g-dev \
    # 日志和工具
    tree expect \
    colorized-logs \
    # 压缩工具
    pbzip2 \
    # 分区工具
    gdisk fdisk \
    # 下载工具
    aria2 axel curl \
    # 并行处理
    parallel \
    # 其他工具
    rdfind \
    binwalk \
    # Python 2 支持（某些工具需要）
    python2 python2-dev \
    libffi-dev \
    # 交叉编译工具链（可选，优先使用Armbian工具链）
    gcc-arm-linux-gnueabi \
    libc6-amd64-cross \
    # 工具
    wget unzip rsync cpio xz-utils \
    sudo kmod dosfstools \
    file bzip2 ssh xxd u-boot-tools \
    fakeroot busybox libc6-i386 lib32stdc++6 \
    # 分区和文件系统工具（package-image.sh需要）
    parted util-linux e2fsprogs btrfs-progs \
    # RootFS构建工具（build-rootfs.sh需要）
    debootstrap \
    # Docker相关（用于容器化构建）
    docker.io docker-compose \
    # Armbian build额外依赖
    pv lzop zip time \
    # QEMU支持（用于跨架构构建）
    qemu-user-static binfmt-support \
    # 交叉编译工具链（可选，优先使用Armbian工具链）
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    # 其他工具
    pigz zstd \
    # 其他必需依赖
    ca-certificates cpio dialog dirmngr \
    gawk gnupg gpg \
    linux-base locales \
    ncurses-base ncurses-term \
    && rm -rf /var/lib/apt/lists/*

# 安装Python依赖（Armbian build可能需要）
RUN pip3 install --no-cache-dir \
    pyyaml \
    requests \
    || true

# 配置 root 用户的全局 Git 安全目录（防止挂载宿主机卷时报 ownership错）
RUN git config --global --add safe.directory '*'

# 创建用户并设置密码
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG DOCKER_GID=999
ARG USER_PASSWORD=1  # 在此处设置明文密码（仅测试用途）

# 确保docker组使用正确的GID（与宿主机匹配）
RUN if getent group docker > /dev/null 2>&1; then \
        groupmod -g ${DOCKER_GID} docker || \
        (groupdel docker 2>/dev/null || true; groupadd -g ${DOCKER_GID} docker); \
    else \
        groupadd -g ${DOCKER_GID} docker; \
    fi

RUN groupadd -g ${GROUP_ID} microrat && \
    useradd -u ${USER_ID} -g microrat -ms /bin/bash microrat && \
    # 设置密码（加密处理）
    echo "microrat:${USER_PASSWORD}" | chpasswd && \
    # 将用户添加到 sudo 组
    usermod -aG sudo microrat && \
    # 允许 sudo 无需密码（可选，根据需求）
    echo "microrat ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    # 将用户添加到docker组（确保GID匹配）
    usermod -aG docker microrat

# 设置工作目录权限
RUN mkdir -p /MicroSLAM-SDK && \
    chown -R microrat:microrat /MicroSLAM-SDK

# 切换到非 root 用户
USER microrat
WORKDIR /MicroSLAM-SDK
CMD /bin/bash
