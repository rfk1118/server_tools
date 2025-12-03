#!/bin/bash

# 安装 Rust 模块

set -e

echo ""
echo "安装 Rust..."

# 检查是否已经安装了 rust
if command -v rustc &>/dev/null; then
    echo "检测到 Rust 已安装:"
    rustc --version
    read -p "是否要重新安装? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "跳过 Rust 安装"
        exit 0
    fi
fi

# 使用 rustup 安装 Rust
echo "正在通过 rustup 安装 Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# 加载 Rust 环境变量
source "$HOME/.cargo/env"

# 如果设置了 TARGET_USER，也为该用户安装
if [ -n "$TARGET_USER" ] && id "$TARGET_USER" &>/dev/null; then
    user_home=$(eval echo ~$TARGET_USER)
    
    echo "为用户 $TARGET_USER 安装 Rust..."
    # 切换到目标用户并安装
    sudo -u "$TARGET_USER" bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" || {
        echo "警告: 为用户 $TARGET_USER 安装 Rust 失败，但 root 用户安装成功"
    }
fi

# 验证安装
if command -v rustc &>/dev/null; then
    echo ""
    echo "Rust 安装成功！"
    rustc --version
    cargo --version
    echo ""
    echo "注意: 新终端会话中需要执行: source ~/.cargo/env"
else
    echo "警告: Rust 安装可能未成功，请检查"
    exit 1
fi
