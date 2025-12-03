#!/bin/bash

# 安装 cpupower 工具模块

set -e

echo ""
echo "安装 cpupower 工具..."
apt-get install -y linux-tools-$(uname -r)
echo "cpupower 工具安装完成"

