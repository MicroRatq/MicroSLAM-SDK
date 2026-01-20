# MicroSLAM 固件编译仓库

这是一个独立的MicroSLAM固件编译仓库，基于 [Armbian Build Framework](https://github.com/armbian/build) 官方仓库，实现了 U-Boot、Kernel、RootFS 的独立构建系统，支持精确的增量构建控制。

## 1. 核心特性

- **独立构建系统**：U-Boot、Kernel、RootFS 完全独立构建，互不依赖
- **增量构建支持**：基于 `make clean`/`make mrproper` 的增量构建机制，支持快速迭代开发
- **直接模块集成**：Kernel 模块直接使用 `.ko` 文件，无需 deb 包安装
- **RootFS 缓存**：利用 Armbian artifact 系统的缓存机制，加速 RootFS 构建
- **完全控制**：所有配置文件都在本仓库管理，便于版本控制和定制

## 2. 快速开始

### 2.1 初始化仓库

首次使用前，需要初始化被引用的仓库：

```bash
./scripts/init-repos.sh
```

这个脚本会自动 clone 以下仓库到 `repos/` 目录：
- `armbian/build` - Armbian官方构建框架
- `radxa/u-boot` - U-Boot 源码（next-dev-v2024.10 分支）
- `unifreq/linux-6.1.y-rockchip` - Rockchip内核源码

### 2.2 使用Docker环境（推荐）

#### 构建Docker镜像

```bash
docker compose build
```

#### 启动容器

```bash
docker compose up -d
```

#### 进入容器

```bash
docker compose exec microslam-builder bash
```

#### 在容器内编译

```bash
# 默认构建（所有组件增量构建 + 打包）
./scripts/build.sh
```

### 2.3 本地环境使用

如果不想使用Docker，也可以直接在本地环境使用：

```bash
./scripts/build.sh
```

## 3. 脚本说明

### 3.1 build.sh

主构建脚本，支持独立构建各个组件或全量构建，提供精细的增量构建控制。

**参数说明：**

| 参数 | 说明 | 默认值 | 可选项 |
|------|------|--------|--------|
| `-u` / `-uc` | 构建 U-Boot（`-u` 增量，`-uc` 全量） | 增量 | `-u`（增量）<br>`-uc`（全量） |
| `-k` / `-kc` | 构建 Kernel（`-k` 增量，`-kc` 全量） | 增量 | `-k`（增量）<br>`-kc`（全量） |
| `-f` / `-fc` | 构建 RootFS（`-f` 增量，`-fc` 全量） | 增量 | `-f`（增量）<br>`-fc`（全量） |
| `-p, --package` | 在构建流程最后执行打包 | 自动 | 可选 |
| `--clean-cache` | 仅清理缓存，不进行构建 | - | 可选 |
| `-r, --release RELEASE` | 指定 Ubuntu/Debian 版本 | noble | noble, jammy, bookworm 等 |
| `-b, --branch BRANCH` | 指定 Armbian 分支 | current | current, edge 等 |
| `--desktop` | 构建桌面版镜像 | no | 可选 |
| `--minimal` | 构建最小化镜像 | no | 可选 |
| `-j, --threads N` | 编译线程数 | 自动计算 | 正整数 |
| `-h, --help` | 显示帮助信息 | - | 可选 |

**注意：**
- `-u` 和 `-uc` 互斥，`-k` 和 `-kc` 互斥，`-f` 和 `-fc` 互斥
- 可以任意组合，如 `-u -kc -f`
- 如果不指定 `-u/-k/-f`，默认构建所有组件且使用增量构建模式
- 如果构建了所有组件，自动启用打包（无需指定 `-p`）

**输出位置：**
- U-Boot: `output/uboot/`
- Kernel: `output/kernel/`
- RootFS: `output/rootfs/`
- 镜像: `output/images/`

### 3.2 build-uboot.sh

独立构建 U-Boot，支持增量构建。

**特性：**
- 自动应用 MicroSLAM 配置（defconfig、DTS、Kconfig、board 目录）
- 支持增量构建（基于 `make clean`）
- 自动生成 `u-boot.itb` FIT 镜像

**用法：**
```bash
./scripts/build-uboot.sh [-j N] [--incremental]
```

### 3.3 build-kernel.sh

独立构建 Kernel，支持增量构建。

**特性：**
- 自动应用 MicroSLAM 设备树文件
- 支持增量构建（基于 `make mrproper`）
- 直接安装 `.ko` 模块文件，无需 deb 包
- 自动打包模块为 `modules-*.tar.gz`

**用法：**
```bash
./scripts/build-kernel.sh [-j N] [--incremental]
```

### 3.4 build-rootfs.sh

独立构建 RootFS，使用 Armbian artifact 系统。

**特性：**
- 完全跳过 U-Boot 和 Kernel 构建
- 使用 Armbian artifact 缓存机制加速构建
- 手动构建必要的 artifact 包
- 支持桌面版和最小版本

**用法：**
```bash
./scripts/build-rootfs.sh [-r RELEASE] [-b BRANCH] [--desktop] [--minimal]
```

### 3.5 package-image.sh

打包最终镜像，合并独立构建的组件。

**特性：**
- 合并 U-Boot、Kernel、RootFS 到最终镜像
- 支持 ext4 和 btrfs 文件系统
- 自动分区和格式化
- 直接复制 `.ko` 模块到 RootFS

**用法：**
```bash
./scripts/package-image.sh
```

### 3.6 init-repos.sh

初始化被引用的仓库。如果仓库不存在，会自动从 GitHub clone。

```bash
./scripts/init-repos.sh
```

**下载的仓库：**
- `repos/armbian-build` - Armbian官方构建框架
- `repos/u-boot-radxa` - Radxa U-Boot 源码
- `repos/linux-6.1.y-rockchip` - Rockchip内核源码（6.1.y分支）

### 3.7 apply-patches.sh

应用 MicroSLAM 特定的补丁和配置到源码树。

**功能：**
- 复制 U-Boot 配置到源码树
- 复制 Kernel 设备树到源码树
- 应用必要的补丁

**用法：**
```bash
./scripts/apply-patches.sh
```

### 3.8 common.sh

公共函数库，包含工具链管理、路径管理、构建输出检查等通用功能。

## 4. 配置文件说明

### 4.1 configs/uboot/

U-Boot 配置文件目录：
- `rk3588-microslam_defconfig` - U-Boot 默认配置
- `dts/rk3588-microslam.dts` - U-Boot 设备树文件
- `arch/arm/mach-rockchip/rk3588/Kconfig` - Kconfig 配置
- `board/rockchip/microslam/` - 板卡特定文件
- `include/configs/microslam.h` - 板卡头文件

### 4.2 configs/kernel/

Kernel 配置文件目录：
- `config-6.1` - 内核配置文件
- `dts/rk3588-microslam.dts` - 内核设备树文件

### 4.3 configs/bootfs/

启动文件系统配置文件：
- `armbianEnv.txt` - Armbian环境变量配置
- `boot.cmd` - U-Boot启动脚本
- `boot.scr` - 编译后的启动脚本

### 4.4 configs/rootfs/

根文件系统配置文件：
- `etc/balance_irq` - IRQ平衡配置

## 5. 构建流程说明

### 5.1 独立构建流程

1. **U-Boot 构建**：
   - 初始化 U-Boot 源码（从 `repos/u-boot-radxa`）
   - 应用 MicroSLAM 配置（defconfig、DTS、Kconfig、board 目录）
   - 执行 `make clean`（全量构建）或跳过（增量构建）
   - 编译 U-Boot 并生成 `u-boot.itb` FIT 镜像
   - 输出到 `output/uboot/`

2. **Kernel 构建**：
   - 初始化 Kernel 源码（从 `repos/linux-6.1.y-rockchip`）
   - 应用 MicroSLAM 设备树文件
   - 执行 `make mrproper`（全量构建）或跳过（增量构建）
   - 编译内核镜像和设备树
   - 编译并安装内核模块（`.ko` 文件）
   - 打包模块为 `modules-*.tar.gz`
   - 输出到 `output/kernel/`

3. **RootFS 构建**：
   - 使用 Armbian artifact 系统获取或创建 rootfs cache
   - 手动构建必要的 artifact 包（fake-ubuntu-advantage-tools、armbian-base-files 等）
   - 安装发行版特定包和发行版无关包
   - 应用 MicroSLAM 自定义配置
   - 打包 rootfs 为 tarball
   - 输出到 `output/rootfs/`

4. **镜像打包**：
   - 创建镜像文件并分区
   - 写入 U-Boot 到镜像
   - 复制 Kernel 镜像和设备树到 boot 分区
   - 解压 RootFS 到根分区
   - 复制内核模块到 RootFS
   - 生成最终镜像文件
   - 输出到 `output/images/`

## 6. Docker环境配置

### 6.1 环境变量

可以通过环境变量自定义Docker配置：

```bash
# 设置用户ID和组ID（默认为1000）
export USER_ID=1000
export GROUP_ID=1000

# 设置用户密码（默认为1）
export USER_PASSWORD=your_password

docker compose build
```

### 6.2 挂载点

- `./` → `/MicroSLAM-SDK` - 项目根目录
- `./repos` → `/MicroSLAM-SDK/repos` - 被引用仓库目录
- `./output` → `/MicroSLAM-SDK/output` - 构建输出目录

### 6.3 Privileged 模式

Docker 容器以 privileged 模式运行，以支持：
- 文件系统挂载和分区操作
- binfmt_misc 配置（用于交叉编译）
- 其他需要特权权限的操作

## 7. 参考资源

- [Armbian Build Framework](https://github.com/armbian/build) - 官方构建框架
- [Armbian Documentation](https://docs.armbian.com/) - 官方文档
- [Armbian User Configurations](https://docs.armbian.com/Developer-Guide_User-Configurations/) - userpatches 机制说明
- [linux-6.1.y-rockchip](https://github.com/unifreq/linux-6.1.y-rockchip) - Rockchip 内核源码
- [Radxa U-Boot](https://github.com/radxa/u-boot) - Radxa U-Boot 源码

## 8. 许可证

本项目基于以下项目：
- [armbian/build](https://github.com/armbian/build) - GPL-2.0
- [linux-6.1.y-rockchip](https://github.com/unifreq/linux-6.1.y-rockchip) - GPL-2.0
- [radxa/u-boot](https://github.com/radxa/u-boot) - GPL-2.0

## 9. 贡献

欢迎提交 Issue 和 Pull Request。
