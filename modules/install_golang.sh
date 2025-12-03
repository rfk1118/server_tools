#!/bin/bash

# 安装 Golang 模块

set -e

echo ""
echo "安装 Golang..."

# 提示用户输入版本号，默认为 1.25.5
read -p "请输入 Go 版本号 (默认: 1.25.5): " go_version
go_version=${go_version:-1.25.5}

# 构建下载链接
GO_DOWNLOAD_URL="https://go.dev/dl/go${go_version}.linux-amd64.tar.gz"
GO_TAR_FILE="go${go_version}.linux-amd64.tar.gz"

echo "将下载: $GO_DOWNLOAD_URL"

# 下载 Go
cd /tmp
if [ -f "$GO_TAR_FILE" ]; then
    echo "文件已存在，跳过下载"
else
    echo "正在下载 Go ${go_version}..."
    wget "$GO_DOWNLOAD_URL" || {
        echo "错误: 下载失败，请检查版本号是否正确"
        exit 1
    }
fi

# 安装 Go
echo "正在安装 Go ${go_version}..."
rm -rf /usr/local/go
tar -C /usr/local -xzf "$GO_TAR_FILE"

# 添加到 PATH（临时，当前会话有效）
export PATH=$PATH:/usr/local/go/bin

# 添加到系统 PATH（永久）
if ! grep -q "/usr/local/go/bin" /etc/profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
fi

# 如果设置了 TARGET_USER，也为该用户添加到 PATH
if [ -n "$TARGET_USER" ] && id "$TARGET_USER" &>/dev/null; then
    user_home=$(eval echo ~$TARGET_USER)
    bashrc_file="$user_home/.bashrc"
    
    if [ -f "$bashrc_file" ]; then
        if ! grep -q "/usr/local/go/bin" "$bashrc_file"; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> "$bashrc_file"
        fi
    fi
fi

# 验证安装
if /usr/local/go/bin/go version; then
    echo ""
    echo "Go ${go_version} 安装成功！"
    echo "注意: 新终端会话中需要重新加载环境变量或执行: source /etc/profile"
else
    echo "警告: Go 安装可能未成功，请检查"
    exit 1
fi
