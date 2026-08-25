# server_tools

适用于 Ubuntu 24.04 的交互式服务器初始化工具。以 root 运行：

```bash
sudo ./tools.sh
```

## 菜单

`A` / `all` 是保守的基础配置：创建目标用户、构建工具、cpupower/可选 performance governor、Redis、SSH、Go、Rust、Node.js 和 fail2ban。它不包含 UFW、防火墙规则重置、Redis RDB 恢复、sysctl 调优或 MySQL 安装；这些项目需要从菜单显式选择。

构建工具模块通过 APT 安装 `build-essential`、`pkg-config`、`clang` 和 `libclang-dev` 等软件包；`fzf` 不使用 Ubuntu 软件包，而是为目标用户执行 `git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf` 和 `~/.fzf/install --all`。旧机器再次执行 `A` 时，完整的 `fzf` 安装会跳过；仓库或二进制不完整时会自动重新执行安装器。

第一次执行 `A` 仍会询问用户名、密码策略和 SSH 公钥。默认版本为 Go `1.25.5`、Rust `1.98.0`、Node.js `24.19.0` 和 nvm `0.40.6`；可分别用 `GO_VERSION`、`RUST_VERSION`、`NODE_VERSION`、`NVM_VERSION` 覆盖。

Redis RDB 恢复会覆盖数据，只能通过 `[13]` 显式执行并再次输入 `yes`。脚本会读取 Redis 当前生效的 `dir`/`dbfilename`，校验源文件和临时副本，备份旧 RDB，并在新文件无法启动时自动回滚；启用 AOF 时会拒绝 RDB 恢复。也可直接执行 `sudo bash modules/restore_redis_rdb.sh /path/to/dump.rdb`，但仍需输入 `yes`。UFW 只能通过 `[7]` 交互式执行：脚本先展示计划，保留既有规则，自动识别 SSH 端口；Geth 模板只开放 P2P，不会公开 8545/8546 RPC。

## 重复执行

每个成功的基础模块会在 `/var/lib/server_tools/` 留下成功标记。再次执行 `A` 时，只有“有成功标记且模块的实际检查仍满足”的模块会跳过；旧标记不能掩盖被人为修改或状态漂移的配置。模块失败、或命令退出成功但最终检查失败，都不会被标记成功，`tools.sh` 会以失败状态退出。

从不带状态标记的旧版脚本升级后，第一次运行新版 `A` 会重新检查并在必要时修复各模块；此后的运行才会使用这些标记。版本环境变量属于期望状态：下次运行时若改用不同的 `GO_VERSION`、`RUST_VERSION`、`NODE_VERSION` 或 `NVM_VERSION`，对应模块会重新执行。

模块自身也会检查已安装的软件和已满足的配置，避免无谓重装或重复写入。可用 `SERVER_TOOLS_STATE_DIR` 在测试时指定其他状态目录。

## 安全行为

- SSH 使用较早加载的 `/etc/ssh/sshd_config.d/00-server-tools.conf`，不会删除任何 `/etc/ssh/ssh_config.d` 文件；公钥仅追加到目标用户的 `authorized_keys`，默认不会写入 root。
- SSH 配置会先通过 `sshd -t`，失败会回滚 drop-in；Ubuntu 24.04 的 `ssh.socket`/`ssh.service` 均会被识别。
- Redis Unix socket 模式使用 `port 0` 和目标用户的 `redis` 组权限；TCP 模式恢复为 `port 6379`。
- CPU performance 模块会启用 `set-cpu-performance.service`，当前立即生效，并在每次重启时等待内核模块加载后重新设置 governor；虚拟机或不支持 `performance` governor 的 CPU 会跳过。
- Go 下载在替换 `/usr/local/go` 前校验 Go 官方下载元数据中的 SHA-256；Rust `1.98.0`、Node.js `24.19.0` 均只为目标用户安装（可用环境变量覆盖）。Node 使用 nvm `v0.40.6`。

`[12]` 的 sysctl 参数面向 BSC 等高性能节点，应按实际业务需求选择，不属于通用基础配置。
