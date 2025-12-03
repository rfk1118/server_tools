#!/bin/bash

# 安装 Redis 模块

set -e

echo ""
echo "安装 Redis..."
if command -v redis-server &> /dev/null; then
    echo "Redis 已安装，版本: $(redis-server --version)"
else
    echo "配置 Redis 官方仓库..."
    
    # 下载并添加 Redis GPG 密钥
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
    
    # 添加 Redis 仓库
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    
    # 更新软件包列表并安装 Redis
    apt-get update
    apt-get install -y redis
    
    # 启用并启动 Redis 服务
    systemctl enable redis-server
    systemctl start redis-server
    echo "Redis 安装完成"
fi

