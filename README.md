# MicroSLAM 固件编译仓库

这是一个独立的MicroSLAM固件编译仓库，基于 [Armbian Build Framework](https://github.com/armbian/build) 官方仓库，在编译阶段通过userpatches机制引入MicroSLAM配置，实现完全独立的构建流程。

## 项目结构

```
MicroSLAM-SDK/
├── .gitignore                    # Git忽略规则
├── .gitattributes               # Git属性配置
├── README.md                     # 项目说明文档
├── docker-compose.yml            # Docker Compose配置
├── Dockerfile                    # Docker镜像构建文件
├── configs/                      # MicroSLAM配置文件目录
│   ├── model_database.conf      # MicroSLAM配置行（参考用）
│   ├── kernel/                  # 内核相关配置
│   │   ├── config-6.1           # 内核配置文件
│   │   └── dts/                 # 设备树文件
│   │       └── rk3588-microslam.dts
│   ├── bootfs/                  # 启动文件系统配置
│   │   ├── armbianEnv.txt
│   │   ├── boot.cmd
│   │   └── boot.scr
│   └── rootfs/                  # 根文件系统配置
│       └── etc/
│           └── balance_irq
├── userpatches/                  # Armbian userpatches配置
│   ├── config-microslam.conf    # 板卡配置文件
│   ├── linux-rockchip64-current.config  # 内核配置文件
│   ├── sources/
│   │   └── rockchip.conf        # 内核源配置
│   ├── patch/
│   │   └── kernel/              # 内核补丁目录
│   └── customize-image.sh       # 镜像自定义脚本
├── scripts/                      # 构建脚本目录
│   ├── init-repos.sh            # 初始化仓库脚本
│   ├── integrate-dts.sh         # 设备树集成脚本
│   ├── build.sh                 # 构建固件脚本
│   └── compile-kernel.sh        # 内核编译脚本
└── repos/                        # 被引用仓库目录（git忽略）
    ├── armbian-build/            # Armbian官方构建框架
    └── linux-6.1.y-rockchip/    # Rockchip内核源码
```

## 核心特性

- **独立构建**：基于Armbian官方build框架，不依赖amlogic-s9xxx-armbian的rebuild脚本
- **编译阶段注入**：通过Armbian的userpatches机制，在编译阶段就引入MicroSLAM配置
- **完全控制**：所有配置文件都在本仓库管理，便于版本控制和定制

## 快速开始

### 1. 初始化仓库

首次使用前，需要初始化被引用的仓库：

```bash
./scripts/init-repos.sh
```

这个脚本会自动clone以下仓库到 `repos/` 目录：
- `armbian/build` - Armbian官方构建框架
- `unifreq/linux-6.1.y-rockchip` - Rockchip内核源码

### 2. 使用Docker环境（推荐）

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
# 构建完整固件镜像
./scripts/build.sh

# 仅编译内核
./scripts/compile-kernel.sh
```

### 3. 本地环境使用

如果不想使用Docker，也可以直接在本地环境使用：

```bash
# 确保已安装所有依赖（参考Dockerfile中的依赖列表）
# 然后直接运行脚本

./scripts/build.sh
./scripts/compile-kernel.sh
```

## 脚本说明

### init-repos.sh

初始化被引用的仓库。如果仓库不存在，会自动从GitHub clone。

```bash
./scripts/init-repos.sh
```

**下载的仓库：**
- `repos/armbian-build` - Armbian官方构建框架
- `repos/linux-6.1.y-rockchip` - Rockchip内核源码（6.1.y分支）

### integrate-dts.sh

将MicroSLAM设备树文件集成到内核源码树。这个脚本会：
1. 复制 `configs/kernel/dts/rk3588-microslam.dts` 到内核源码树
2. 更新内核源码树中的Makefile，添加dtb构建规则

```bash
./scripts/integrate-dts.sh
```

### build.sh

构建MicroSLAM固件镜像。这个脚本会：

1. 初始化仓库（如果未初始化）
2. 集成设备树文件到内核源码树
3. 准备userpatches配置（复制到armbian-build/userpatches）
4. 调用 `armbian/build/compile.sh` 进行编译
5. 在编译阶段通过customize-image.sh注入bootfs和rootfs配置

```bash
# 使用默认参数（RELEASE=noble, BRANCH=current）
./scripts/build.sh

# 指定Ubuntu/Debian版本
./scripts/build.sh -r jammy

# 指定内核分支
./scripts/build.sh -b edge

# 构建桌面版
./scripts/build.sh --desktop
```

**输出位置：** `repos/armbian-build/output/images/`

### compile-kernel.sh

单独编译MicroSLAM内核。这个脚本会：

1. 初始化仓库（如果未初始化）
2. 集成设备树文件到内核源码树
3. 准备userpatches配置
4. 调用 `armbian/build/compile.sh`，仅编译内核

```bash
# 使用默认参数
./scripts/compile-kernel.sh

# 指定内核分支
./scripts/compile-kernel.sh -b edge

# 启用内核配置界面
./scripts/compile-kernel.sh -c
```

**输出位置：** `repos/armbian-build/output/debs/`

## 配置文件说明

### userpatches/config-microslam.conf

MicroSLAM板卡配置文件，定义：
- `BOARD_NAME` - 板卡名称
- `BOARDFAMILY` - 板卡家族（rk3588）
- `BOOT_FDT_FILE` - 设备树文件路径
- `KERNEL_TARGET` - 支持的内核分支
- 其他板卡特定配置

### userpatches/linux-rockchip64-current.config

内核配置文件，从 `configs/kernel/config-6.1` 复制而来，用于覆盖Armbian默认的内核配置。

### userpatches/sources/rockchip.conf

内核源配置，指定使用 `unifreq/linux-6.1.y-rockchip` 仓库作为内核源码。

### userpatches/customize-image.sh

镜像自定义脚本，在Armbian构建系统的镜像打包前执行，用于：
- 复制bootfs配置（armbianEnv.txt, boot.cmd等）
- 复制rootfs配置（balance_irq等）
- 执行其他自定义操作

### configs/kernel/dts/rk3588-microslam.dts

MicroSLAM设备树主文件，会在构建时自动集成到内核源码树。

### configs/bootfs/

启动文件系统配置文件：
- `armbianEnv.txt` - Armbian环境变量配置
- `boot.cmd` - U-Boot启动脚本
- `boot.scr` - 编译后的启动脚本

### configs/rootfs/

根文件系统配置文件：
- `etc/balance_irq` - IRQ平衡配置

## 构建流程说明

### 完整构建流程

1. **初始化阶段**：下载armbian/build和linux-6.1.y-rockchip仓库
2. **准备阶段**：
   - 集成设备树文件到内核源码树
   - 复制userpatches配置到armbian-build/userpatches
3. **编译阶段**：
   - Armbian build系统读取userpatches配置
   - 使用指定的内核源和配置编译内核
   - 编译设备树文件
   - 打包根文件系统
4. **自定义阶段**：
   - 执行customize-image.sh注入bootfs和rootfs配置
5. **输出阶段**：生成最终的.img镜像文件

### 与原有流程的区别

| 特性 | 原流程（amlogic-s9xxx-armbian） | 新流程（armbian/build） |
|------|-------------------------------|------------------------|
| 构建方式 | 使用rebuild脚本，构建后替换文件 | 使用compile.sh，编译阶段注入配置 |
| 配置文件 | 需要model_database.conf | 使用userpatches配置 |
| 依赖关系 | 依赖外部rebuild脚本 | 完全独立，仅依赖官方框架 |
| 设备树处理 | 构建后复制 | 编译时集成到内核源码树 |
| 内核配置 | 构建后替换 | 编译时使用userpatches覆盖 |

## Docker环境配置

### 环境变量

可以通过环境变量自定义Docker配置：

```bash
# 设置用户ID和组ID（默认为1000）
export USER_ID=1000
export GROUP_ID=1000

# 设置用户密码（默认为1）
export USER_PASSWORD=your_password

docker compose build
```

### 挂载点

- `./` → `/MicroSLAM-SDK` - 项目根目录
- `./repos` → `/MicroSLAM-SDK/repos` - 被引用仓库目录

## 构建参数说明

### build.sh 参数

- `-r, --release` - 指定Ubuntu/Debian版本（noble, jammy, bookworm等）
- `-b, --branch` - 指定内核分支（current, edge等）
- `--desktop` - 构建桌面版镜像
- `--minimal` - 构建最小化镜像

### compile-kernel.sh 参数

- `-b, --branch` - 指定内核分支
- `-c, --configure` - 启用内核配置界面

## 注意事项

1. **首次使用**：首次使用前必须运行 `./scripts/init-repos.sh` 初始化仓库。

2. **磁盘空间**：构建过程需要大量磁盘空间（建议至少50GB可用空间）。

3. **构建时间**：完整构建可能需要数小时，取决于硬件性能。

4. **网络要求**：初始化仓库和编译过程需要网络连接以下载依赖和源码。

5. **权限问题**：如果遇到权限问题，确保Docker容器以privileged模式运行（已在docker-compose.yml中配置）。

6. **内核版本匹配**：确保configs/kernel/config-6.1与linux-6.1.y-rockchip内核版本兼容。

## 故障排除

### 仓库初始化失败

如果 `init-repos.sh` 失败，检查：
- 网络连接是否正常
- Git是否已安装
- GitHub访问是否正常

### 设备树集成失败

如果 `integrate-dts.sh` 失败，检查：
- 内核源码目录是否存在
- 源设备树文件是否存在
- 是否有写入权限

### 编译失败

如果编译失败，检查：
- 所有依赖是否已安装（参考Dockerfile）
- 磁盘空间是否充足（至少50GB）
- userpatches配置是否正确
- 查看构建日志：`repos/armbian-build/output/logs/`

### Docker问题

如果Docker相关操作失败，检查：
- Docker是否已安装（Docker Compose已集成在Docker中）
- 是否有足够的权限运行Docker
- 容器日志：`docker compose logs`

## 参考资源

- [Armbian Build Framework](https://github.com/armbian/build) - 官方构建框架
- [Armbian Documentation](https://docs.armbian.com/) - 官方文档
- [Armbian User Configurations](https://docs.armbian.com/Developer-Guide_User-Configurations/) - userpatches机制说明
- [linux-6.1.y-rockchip](https://github.com/unifreq/linux-6.1.y-rockchip) - Rockchip内核源码

## 许可证

本项目基于以下项目：
- [armbian/build](https://github.com/armbian/build) - GPL-2.0
- [linux-6.1.y-rockchip](https://github.com/unifreq/linux-6.1.y-rockchip) - GPL-2.0

## 贡献

欢迎提交Issue和Pull Request。
