#!/bin/bash

# 安装构建相关软件模块

set -e

packages=(build-essential pkg-config clang libclang-dev git curl wget vim htop fzf net-tools software-properties-common ca-certificates gnupg lsb-release python3 openssh-client)
if [ "${1:-}" = --check ]; then
    for package in "${packages[@]}"; do dpkg-query -W -f='${db:Status-Status}\n' "$package" 2>/dev/null | grep -qx installed || exit 1; done
    command -v pkg-config >/dev/null && command -v clang >/dev/null && command -v fzf >/dev/null
    exit 0
fi

echo ""
echo "安装构建相关软件..."
apt-get update
apt-get install -y "${packages[@]}"
command -v pkg-config >/dev/null && command -v clang >/dev/null && command -v fzf >/dev/null || {
    echo "错误: pkg-config、clang 或 fzf 安装后仍不可用" >&2
    exit 1
}
echo "构建工具安装完成"
