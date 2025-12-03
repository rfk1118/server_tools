#!/bin/bash

# 安装构建相关软件模块

set -e

echo ""
echo "安装构建相关软件..."
apt-get update
apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    vim \
    htop \
    net-tools \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release
echo "构建工具安装完成"

