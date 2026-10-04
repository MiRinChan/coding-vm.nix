# coding-vm.nix

用NixOS和QEMU运行开发虚拟机，给开发工具和coding agent提供固定的Linux环境。

预装Git、Node.js、Python、GitHub CLI、VS Code和Claude Code。通过SSH连接，桌面客户端可以单独关闭。

## 使用

宿主机需要支持KVM和systemd用户服务，并提供可用的GPU渲染节点。默认配置使用`x86_64-linux`架构和`/dev/dri/renderD128`节点。

默认启用Tailscale出口预设，启动前需要在宿主机选中在线出口节点。

```sh
git clone https://github.com/MiRinChan/coding-vm.nix.git
cd coding-vm.nix
./start.sh
```

默认分配8个CPU、16GiB内存和80GiB磁盘，使用CachyOS BORE内核。首次启动会创建磁盘并预分配宿主磁盘空间。

启动器会配置SSH连接、安装VS Code Remote-SSH扩展、打开kitty和VS Code，并用SSHFS挂载虚拟机家目录。退出启动器会停止虚拟机。

| 项目 | 默认值 |
|---|---|
| SSH别名 | `coding-vm` |
| SSH端口 | `2223` |
| SSH私钥 | `~/.ssh/coding-vm_ed25519` |
| 磁盘及日志 | `.vm-state/` |
| 文件系统入口 | `virtualMachine` |
| systemd用户服务 | `coding-vm-qemu-<PID>` |

家目录和工作文件保存在磁盘中。可写store使用tmpfs，新增store内容不跨重启保存。此设置位于`modules/vm/storage.nix`中的`writableStoreUseTmpfs`。

### 只使用SSH

```sh
OPEN_VSCODE=0 OPEN_KITTY_SSH=0 MOUNT_SSHFS=0 ./start.sh
```

启动器仍会检查虚拟机的Nix数据库。SSH设置写入宿主`~/.ssh/config`中的`coding-vm`块。

`VM_SSH_PORT`、`VM_STATE_DIR`、`VM_SSH_KEY`和`VM_FS_MOUNT_DIR`可以覆盖默认值。多个实例需要使用不同的磁盘目录和SSH端口。

## 修改配置

用户、资源、GPU节点和地区预设在`settings.nix`中。预装软件在`modules/environment/development.nix`中。

### 地区和网络

```nix
spoofSettings.enable = true;
```

开启时，应用`spoofSettings.region`中的时区、语言和静态位置，并设置Firefox地区偏好。默认地区为旧金山，使用美国英语和`America/Los_Angeles`时区。

网络出口绑定到宿主的Tailscale接口。宿主机需要选中在线出口节点，启动器持续检查出口和IPv4、IPv6路由。

关闭时，使用NixOS默认地区设置和QEMU用户网络，出口跟随宿主路由。

`spoofSettings.network`中的地址用于虚拟机内网。公网IP取决于选中的出口节点，地区预设不会改变公网IP的位置。

`./start.sh`、`nix run`和开发环境中的`run-vm`都读取构建时的配置。修改后需要重新构建并启动虚拟机。

## 检查

在项目目录运行：

```sh
nix develop --accept-flake-config path:.#tools --command bash -c 'nix flake check path:. --no-build'
nix develop --accept-flake-config path:.#tools --command bash tests/run.sh
nix develop --accept-flake-config path:.#tools --command bash tests/passt-bind-failure.sh
```

这些检查不会启动虚拟机。磁盘测试使用临时目录。

启用Tailscale出口预设后，检查运行中实例的IPv4、IPv6和DNS：

```sh
nix develop --accept-flake-config path:.#tools --command bash scripts/vm-leak-test.sh
```

## 文件

```text
flake.nix、flake.lock          构建入口和依赖版本
settings.nix                  实例参数和spoofSettings
hosts/coding-vm.nix            模块组合
modules/system/               Nix基础设置、用户和SSH
modules/environment/          开发工具、桌面和地区
modules/vm/                   内核、磁盘、GPU、宿主工具和网络
scripts/                      启动、磁盘准备和出口检查
patches/                      passt绑定失败时退出的补丁
tests/                        配置、磁盘、网络和GPU测试
```

`.gitignore`排除虚拟机状态、挂载入口、构建链接和Python缓存。凭据在运行时注入。

## 许可证

待定，尚未添加LICENSE文件或授予开源许可证。
