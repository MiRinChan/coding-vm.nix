# coding-vm.nix

基于NixOS和QEMU的模块化开发虚拟机。提供可重复构建的工具环境、SSH访问、可选的桌面客户端，以及可切换的地区和网络预设。

预装工具包括Git、Node.js、Python、GitHub CLI、VS Code和Claude Code。软件包在`modules/environment/development.nix`中配置。

## 目录

- `flake.nix`：依赖、NixOS实例、启动程序和开发环境。

- `settings.nix`：架构、用户名、主机名、资源、GPU节点及`spoofSettings`。

- `hosts/coding-vm.nix`：组合虚拟机模块。

- `modules/system/`：Nix基础设置、用户和SSH。

- `modules/environment/`：开发工具、桌面及地区预设。

- `modules/vm/`：内核、磁盘、GPU、宿主工具和网络。

- `scripts/`：启动器、磁盘准备及出口检查。

- `patches/`：passt接口绑定失败时退出的补丁。

- `tests/`：SSH配置、网络预设、磁盘和passt绑定失败检查。

## 默认配置

默认配置为8个CPU、16GiB内存和80GiB磁盘，使用CachyOS BORE内核及宿主GPU渲染。宿主机需要支持KVM，并提供`settings.nix`中指定的GPU渲染节点。默认架构为`x86_64-linux`，默认渲染节点为`/dev/dri/renderD128`。

虚拟机通过QEMU启动。`writableStoreUseTmpfs = true`将可写store放在tmpfs中，新增store内容不跨重启保存。家目录和工作文件保存在虚拟机磁盘中。

## 地区和网络预设

在`settings.nix`中设置总开关：

```nix
spoofSettings.enable = true;
```

`true`启用`spoofSettings.region`中的地区参数、Firefox地区偏好、静态定位及Tailscale出口绑定。默认地区预设为旧金山，使用`America/Los_Angeles`时区、美国英语及旧金山坐标。宿主机必须选中在线Tailscale出口节点，启动器持续检查出口和路由状态。

`false`使用NixOS默认地区设置和QEMU用户网络，不要求Tailscale出口。实际出口仍受宿主路由影响。

`spoofSettings.network`中的IPv4和IPv6地址用于虚拟机内网。公网IP由宿主机选中的出口节点决定。地区预设不会决定公网IP的位置，开关也不会自行选择出口节点。

`./start.sh`、`nix run`和开发环境中的`run-vm`均读取构建时的开关值。修改设置后需要重新构建并启动虚拟机。

## 启动

在项目目录运行：

```sh
./start.sh
```

默认连接参数：

| 项目 | 值 |
|---|---|
| SSH别名 | `coding-vm` |
| SSH端口 | `2223` |
| SSH私钥 | `~/.ssh/coding-vm_ed25519` |
| 磁盘及日志 | `.vm-state/` |
| 文件系统入口 | `virtualMachine` |
| systemd用户服务 | `coding-vm-qemu-<PID>` |

首次启动会创建80GiB磁盘并预分配宿主磁盘空间。启动器会更新宿主`~/.ssh/config`中的`coding-vm`块，安装VS Code Remote-SSH扩展，打开kitty及VS Code，并通过SSHFS挂载虚拟机家目录。退出启动器会停止它创建的虚拟机服务。

`VM_SSH_PORT`、`VM_STATE_DIR`、`VM_SSH_KEY`和`VM_FS_MOUNT_DIR`等变量可以覆盖默认值。多个实例需要使用不同的磁盘目录和SSH端口。

设置`OPEN_VSCODE=0`、`OPEN_KITTY_SSH=0`和`MOUNT_SSHFS=0`可以关闭桌面客户端和文件系统挂载。SSH仍可连接，启动器仍检查虚拟机的Nix数据库。

## 检查

```sh
nix develop --accept-flake-config path:.#tools --command bash -c 'nix flake check path:. --no-build'
nix develop --accept-flake-config path:.#tools --command bash tests/run.sh
nix develop --accept-flake-config path:.#tools --command bash tests/passt-bind-failure.sh
```

这些命令不会启动虚拟机。磁盘测试只使用临时目录。

启用Tailscale出口预设后，可以检查运行中实例的IPv4、IPv6和DNS：

```sh
nix develop --accept-flake-config path:.#tools --command bash scripts/vm-leak-test.sh
```

## 仓库内容

源码包括配置、脚本、补丁、测试及锁文件。`.gitignore`排除虚拟机状态、文件系统入口、构建链接和Python缓存。凭据在运行时注入，不写入Nix配置。

## 许可证

许可证待定。目前未添加LICENSE文件，也未授予开源许可证。
