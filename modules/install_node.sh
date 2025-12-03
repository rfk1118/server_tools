#!/bin/bash

# 安装 Node.js 模块（使用 nvm）

set -e

echo ""
echo "安装 Node.js (使用 nvm)..."

# 确定目标用户
INSTALL_USER="${TARGET_USER:-root}"
user_home=$(eval echo ~$INSTALL_USER)

# 检查 nvm 是否已安装
NVM_DIR="$user_home/.nvm"

if [ -d "$NVM_DIR" ]; then
    echo "检测到 nvm 已安装在 $NVM_DIR"
    read -p "是否要重新安装 nvm? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$NVM_DIR"
    else
        # 使用现有的 nvm
        export NVM_DIR="$NVM_DIR"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        # 检查是否已安装 Node.js
        if command -v node &>/dev/null; then
            echo "检测到 Node.js 已安装:"
            node --version
            npm --version
            read -p "是否要安装最新的稳定版本? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "跳过 Node.js 安装"
                exit 0
            fi
        fi
        
        # 安装最新的稳定版本
        echo "正在安装最新的稳定版 Node.js..."
        if [ "$INSTALL_USER" = "root" ]; then
            nvm install --lts
            nvm use --lts
            nvm alias default lts/*
        else
            sudo -u "$INSTALL_USER" bash -c "source $NVM_DIR/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default lts/*"
        fi
        
        echo ""
        echo "Node.js 安装成功！"
        if [ "$INSTALL_USER" = "root" ]; then
            node --version
            npm --version
        else
            sudo -u "$INSTALL_USER" bash -c "source $NVM_DIR/nvm.sh && node --version && npm --version"
        fi
        exit 0
    fi
fi

# 安装 nvm
echo "正在安装 nvm..."
if [ "$INSTALL_USER" = "root" ]; then
    # 为 root 用户安装
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    
    # 加载 nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
else
    # 为目标用户安装（nvm 安装脚本会自动添加到用户的 .bashrc）
    sudo -u "$INSTALL_USER" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash' || {
        echo "错误: nvm 安装失败"
        exit 1
    }
    
    # 等待一下确保文件已创建
    sleep 1
    
    # 验证 nvm 目录是否存在
    if [ ! -d "$NVM_DIR" ]; then
        echo "错误: nvm 目录未找到: $NVM_DIR"
        exit 1
    fi
fi

# 安装最新的稳定版 Node.js
echo "正在安装最新的稳定版 Node.js..."
if [ "$INSTALL_USER" = "root" ]; then
    # 确保 nvm 已加载
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    nvm alias default lts/*
else
    # 为目标用户安装 Node.js
    sudo -u "$INSTALL_USER" bash <<EOF
export NVM_DIR="$NVM_DIR"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
nvm alias default lts/*
EOF
fi

# 验证安装
echo ""
echo "验证安装..."
if [ "$INSTALL_USER" = "root" ]; then
    if command -v node &>/dev/null; then
        echo "Node.js 安装成功！"
        node --version
        npm --version
    else
        echo "警告: Node.js 安装可能未成功，请检查"
        exit 1
    fi
else
    if sudo -u "$INSTALL_USER" bash -c "source $NVM_DIR/nvm.sh && command -v node" &>/dev/null; then
        echo "Node.js 安装成功！"
        sudo -u "$INSTALL_USER" bash -c "source $NVM_DIR/nvm.sh && node --version && npm --version"
    else
        echo "警告: Node.js 安装可能未成功，请检查"
        exit 1
    fi
fi

echo ""
echo "注意: 新终端会话中需要执行: source ~/.nvm/nvm.sh"
echo "或者将以下内容添加到 ~/.bashrc:"
echo '  export NVM_DIR="$HOME/.nvm"'
echo '  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
echo '  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
