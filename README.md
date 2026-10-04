# coding-vm.nix

用NixOS和QEMU运行开发虚拟机，给开发工具和coding agent提供固定的Linux环境。

预装Git、Node.js、Python、GitHub CLI、VS Code和Claude Code。通过SSH或串口控制台连接。默认不自动打开桌面客户端。

## 使用

宿主机需要支持KVM和systemd用户服务，并提供可用的GPU渲染节点。默认配置使用`x86_64-linux`架构和`/dev/dri/renderD128`节点。

默认启用Tailscale出口预设，启动前需要在宿主机选中在线出口节点。

```sh
git clone https://github.com/MiRinChan/coding-vm.nix.git
cd coding-vm.nix
./start.sh
```

默认分配8个CPU、16GiB内存和80GiB磁盘，使用CachyOS BORE内核。首次启动会创建稀疏磁盘，宿主磁盘占用随虚拟机写入增长。

启动器会配置SSH连接，并用SSHFS挂载虚拟机家目录。需要正常关机时，运行`./stop.sh`。退出启动器会停止虚拟机。

| 项目 | 默认值 |
|---|---|
| SSH别名 | `coding-vm` |
| SSH端口 | `2223` |
| SSH私钥 | `~/.ssh/coding-vm_ed25519` |
| 磁盘及日志 | `~/.local/state/coding-vm/` |
| 文件系统入口 | `virtualMachine` |
| systemd用户服务 | `coding-vm-qemu-<PID>` |

家目录和工作文件保存在磁盘中。可写store使用tmpfs，新增store内容不跨重启保存。可通过实例设置中的`storage.writableStoreUseTmpfs`调整。

### 桌面客户端

默认使用`OPEN_VSCODE=0 OPEN_KITTY_SSH=0`。需要自动打开客户端时，运行：

```sh
OPEN_VSCODE=1 OPEN_KITTY_SSH=1 ./start.sh
```

启用VS Code时，启动器会安装Remote-SSH扩展。只需SSH连接时，可用`MOUNT_SSHFS=0 ./start.sh`关闭文件挂载。

启动器仍会检查虚拟机的Nix数据库。SSH设置写入宿主`~/.ssh/config`中的`coding-vm`块。

`VM_SSH_PORT`、`VM_STATE_DIR`、`VM_SSH_KEY`和`VM_FS_MOUNT_DIR`可以覆盖默认值。多个实例需要使用不同的磁盘目录、SSH端口和`launcher.sshAlias`。

默认状态目录位于`~/.local/state/coding-vm/`，磁盘和日志保存在源码目录之外。可以在本地`.instance-state`文件中保存其他实例目录路径。所有管理命令都会读取它，`VM_STATE_DIR`仍可覆盖该路径。此文件不会提交到Git。

已有项目中的`.vm-state/`会继续使用原路径。新实例才使用新的默认目录。多个项目默认共享`~/.local/state/coding-vm/`，独立实例需设置各自的`VM_STATE_DIR`或`.instance-state`。

## 关机、状态和控制台

```sh
./stop.sh             # 请求正常关机，并等待QEMU退出
./status.sh           # 查看当前开关机状态和控制台是否可用
./status.sh --json    # 输出机器可读的状态
./console.sh          # 连接本地串口终端
```

关机脚本通过QMP发送电源按钮事件，不需要SSH。默认等待120秒，超时后保留运行中的VM。可用`./stop.sh --timeout 300`延长等待时间。旧启动器没有QMP时，会尝试通过原SSH连接正常关机。

控制台可用于开机过程、网络故障和SSH服务不可用时。VM需要运行。按Enter显示登录提示，使用实例用户名和密码登录。新实例默认用户名为`alice`，初始密码为`change-me`。密码可在`security.initialPassword`中配置。

按`Ctrl-]`断开控制台，VM继续运行。`Ctrl-C`会发送给虚拟机里的程序。串口不传递窗口大小变化或SSH扩展功能，同一时刻只连接一个终端。

SSH等待超时或启动后的Nix检查失败时，启动器保留VM，供控制台排查。串口输出保存在实例的`logs/console.log`。旧启动器需在下次启动时加载新版本，才能提供串口控制台。

控制脚本使用启动时保存的Python解释器，不求值或构建flake。首次启动前，宿主需提供Python3；脚本也可通过项目的tools环境运行。

## 修改配置

首次启动会把默认值保存到`~/.local/state/coding-vm/manager/settings.nix`。用户、资源、软件、GPU节点和地区预设都在这个实例文件中。

```sh
./vm config  # 显示实例设置路径
# 编辑该文件后，检查并构建修改
./vm update --no-fetch --accept-behavior-changes
```

仓库中的`settings.nix`是新实例模板。已有实例使用自己的设置和依赖锁文件。

### 磁盘预分配

默认关闭预分配。需要预留宿主磁盘空间时，在实例设置文件中设置：

```nix
resources.preallocateDisk = true;
```

此设置用于创建、扩容和准备已有磁盘。关闭它不会回收已有磁盘分配的空间，也不会缩小磁盘。

### 地区和网络

```nix
spoofSettings.enable = true;
```

开启时，应用`spoofSettings.region`中的时区、语言和静态位置，并设置Firefox地区偏好。默认地区为旧金山，使用美国英语和`America/Los_Angeles`时区。

网络出口绑定到宿主的Tailscale接口。宿主机需要选中在线出口节点，启动器持续检查出口和IPv4、IPv6路由。

关闭时，使用NixOS默认地区设置和QEMU用户网络，出口跟随宿主路由。

`spoofSettings.network`中的地址用于虚拟机内网。公网IP取决于选中的出口节点，地区预设不会改变公网IP的位置。

`./start.sh`、`nix run`和开发环境中的`run-vm`都使用当前选中的实例版本。配置修改在下次启动时生效。

## 更新与回滚

```sh
./vm update           # 拉取main，保留实例设置，构建并选择新版本
./vm status           # 查看下次启动使用的版本和设置
./vm upgrade-defaults # 查看差异，确认后采用最新默认值
./vm rollback         # 恢复上一版构建和实例设置
```

`defaultsVersion`选择一份固定的默认配置。新实例使用`2`，默认关闭桌面客户端。`1`保留原默认值。普通更新保留此版本及全部实例设置。新增默认值应放在新的`profiles/vN.nix`中，保留已有版本。

更新会比较资源、存储、网络、地区、SSH、权限、软件列表和启动器策略。如果行为发生变化，会显示差异并停止。确认差异后，可执行`./vm update --accept-behavior-changes`。软件版本变化单独显示。构建失败时继续使用原版本。

采用新版默认值会保留用户名、主机名、架构、连接设置及`systemStateVersion`，其余设置可能改变。命令会先显示这些变化，需确认后才构建。

这些命令不会停止运行中的虚拟机。需要应用新版本时，运行`./stop.sh`，再运行`./start.sh`。回滚恢复配置和构建，不恢复磁盘内容，也不撤销已经执行的磁盘扩容。

实例文件、依赖锁文件和构建记录保存在`~/.local/state/coding-vm/manager/`。每次成功更新保留当前和上一版构建的GC引用。Git工作区有未提交修改时，更新会停止。

## 检查

在项目目录运行：

```sh
nix develop --accept-flake-config path:.#tools --command bash -c 'nix flake check path:. --no-build'
nix develop --accept-flake-config path:.#tools --command bash tests/run.sh
nix develop --accept-flake-config path:.#tools --command bash tests/passt-bind-failure.sh
nix develop --accept-flake-config path:.#tools --command python3 tests/test-manager.py
nix develop --accept-flake-config path:.#tools --command python3 tests/test-runtime.py
nix develop --accept-flake-config path:.#tools --command python3 tests/update-integration.py
nix develop --accept-flake-config path:.#tools --command python3 tests/console-integration.py
```

这些检查不会启动虚拟机。磁盘测试使用临时目录。

启用Tailscale出口预设后，检查运行中实例的IPv4、IPv6和DNS：

```sh
nix develop --accept-flake-config path:.#tools --command bash scripts/vm-leak-test.sh
```

## 文件

```text
flake.nix、flake.lock          构建入口和依赖版本
settings.nix                  新实例模板
profiles/                     按defaultsVersion固定的默认值
lib/                          实例构建和设置合并
vm                            实例更新与配置管理
start.sh、stop.sh、status.sh   启动、正常关机和当前状态
console.sh                    串口终端
templates/instance/           独立flake模板
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
