# 服务器初始化脚本

适用于 Debian/Ubuntu 系统的模块化服务器初始化脚本。

## 脚本结构

```
server_tools/
├── tools.sh                # 主脚本（菜单式选择）
├── modules/                # 功能模块目录
│   ├── create_user.sh           # 创建用户模块
│   ├── install_build_tools.sh   # 安装构建工具模块
│   ├── install_cpupower.sh      # 安装 cpupower 工具模块
│   ├── set_cpu_performance.sh   # 设置 CPU 性能模式模块
│   ├── install_redis.sh         # 安装 Redis 模块
│   ├── configure_ssh.sh         # 配置 SSH 模块
│   └── configure_firewall.sh    # 配置防火墙模块
└── README.md              # 说明文档
```

## 功能模块

1. **创建用户** - 创建用户并添加到 sudo 组（支持自定义用户名）
2. **安装构建工具** - 安装 build-essential, git, curl, vim 等
3. **安装 cpupower** - 安装 CPU 频率管理工具
4. **设置 CPU 性能模式** - 使用 cpupower 设置 CPU 为 performance 模式（依赖 install_cpupower）
5. **安装 Redis** - 从 Redis 官方仓库安装 Redis
6. **配置 SSH** - 配置 SSH 仅允许密钥登录（依赖 create_user，需要先输入 SSH 公钥）
7. **配置防火墙** - 配置 UFW 防火墙，支持预定义模板和自定义端口（默认开放22端口）

## 使用方法

```bash
sudo ./tools.sh
```

运行后会显示交互式菜单，您可以选择：

- **单个功能**: 输入数字编号，例如 `1` 或 `1 2 3`
- **全部执行**: 输入 `A` 或 `a`，将按依赖顺序执行所有功能
- **退出**: 输入 `Q` 或 `q`

## 依赖关系

脚本会自动处理依赖关系，确保模块按正确顺序执行：

- `set_cpu_performance` 依赖于 `install_cpupower`
- `configure_ssh` 依赖于 `create_user`

选择全部执行时，脚本会自动按依赖顺序排序：
1. create_user
2. install_build_tools
3. install_cpupower
4. set_cpu_performance
5. install_redis
6. configure_ssh
7. configure_firewall

## SSH 配置说明

配置 SSH 模块时：
1. 脚本会先提示输入 SSH 公钥
2. 如果直接按回车（不输入任何内容），将跳过整个 SSH 配置
3. 如果输入了 SSH 公钥：
   - 单行：直接粘贴公钥内容，然后按回车，在下一行输入 `END` 结束
   - 多行：粘贴第一行后按回车，继续粘贴后续行，最后输入 `END` 结束
4. SSH 公钥会自动保存到 `/home/<用户名>/.ssh/authorized_keys` 和 `/root/.ssh/authorized_keys`

## 自定义用户名

创建用户模块会在执行时提示输入用户名：
- 用户名必须符合 Linux 用户名规范
- 只能包含小写字母、数字、下划线(_)、连字符(-)
- 必须以字母或下划线开头
- 不能以连字符结尾
- 长度限制: 1-32 个字符
- 默认用户名: `four`
- 如果之前设置过用户名，会自动读取作为默认值

## 防火墙配置说明

防火墙模块支持以下功能：

### 预定义模板

1. **Geth (默认)** - 开放端口: 22, 30000:31000 (TCP/UDP P2P), 8545, 8546 (RPC)
2. **Web** - 开放端口: 22, 80 (HTTP), 443 (HTTPS)

### 自定义端口配置

- 支持单个端口: `8080`
- 支持端口范围: `8000:9000`
- 支持指定协议: `8080/tcp` 或 `8080/udp`
- 支持多个端口: `8080 9090 10000`
- 默认开放 SSH 端口 (22)

### 注意事项

- 防火墙默认策略: 禁止所有入站连接，允许所有出站连接
- SSH 端口 (22) 会自动开放，确保不会断开连接
- 可以重置现有防火墙规则后重新配置
- 配置完成后可选择是否立即启用防火墙

## 注意事项

- 脚本必须以 root 权限运行
- 每个模块可以独立运行，也可以跳过
- CPU 性能设置需要先安装 cpupower 工具
- SSH 配置如果未输入公钥，将跳过整个配置过程
- 如果某个模块执行失败，可以选择继续执行其他模块
# server_tools
