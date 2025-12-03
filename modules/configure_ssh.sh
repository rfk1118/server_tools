#!/bin/bash

# 配置 SSH 模块
# 先提示用户输入 SSH key，如果未输入则跳过整个配置

set -e

echo ""
echo "配置 SSH..."
echo ""
echo "请先输入用于登录的 SSH 公钥内容:"
echo "提示: 可以从本地执行 'cat ~/.ssh/id_rsa.pub' 或 'cat ~/.ssh/id_ed25519.pub' 获取公钥内容"
echo "示例: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... user@hostname"
echo ""
echo "说明: 支持单行或多行输入"
echo "      - 直接按回车: 跳过 SSH 配置"
echo "      - 输入公钥内容后按回车，然后在下一行输入 END 结束"
echo ""
read -p "请粘贴 SSH 公钥（或直接按回车跳过）: " -r first_line

# 如果第一行直接是空（用户直接按回车），则跳过
if [ -z "$first_line" ]; then
    echo ""
    echo "未输入 SSH 公钥，跳过 SSH 配置"
    exit 0
fi

SSH_KEY="$first_line"

# 继续读取多行，直到输入 END
while IFS= read -r line; do
    if [ "$line" = "END" ]; then
        break
    fi
    if [ -n "$line" ]; then
        SSH_KEY="${SSH_KEY}
${line}"
    fi
done

# 清理首尾空白
SSH_KEY=$(echo "$SSH_KEY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$SSH_KEY" ]; then
    echo ""
    echo "未输入 SSH 公钥，跳过 SSH 配置"
    exit 0
fi

# 如果输入了 SSH key，则继续配置 SSH
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# 备份原始配置
cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
echo "已备份 SSH 配置到: $SSH_CONFIG_BACKUP"

# 删除 /etc/ssh/ssh_config.d/ 中的配置文件
echo ""
echo "删除 /etc/ssh/ssh_config.d/ 中的配置文件..."
if [ -d "/etc/ssh/ssh_config.d" ]; then
    SSH_CONFIG_D_COUNT=$(find /etc/ssh/ssh_config.d -type f 2>/dev/null | wc -l)
    if [ "$SSH_CONFIG_D_COUNT" -gt 0 ]; then
        rm -f /etc/ssh/ssh_config.d/*
        echo "已删除 $SSH_CONFIG_D_COUNT 个配置文件"
    else
        echo "/etc/ssh/ssh_config.d/ 目录为空，无需删除"
    fi
else
    echo "/etc/ssh/ssh_config.d/ 目录不存在，跳过"
fi

# 修改 SSH 配置
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$SSH_CONFIG"
sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' "$SSH_CONFIG"

# 如果不存在则添加配置
if ! grep -q "^PubkeyAuthentication" "$SSH_CONFIG"; then
    echo "PubkeyAuthentication yes" >> "$SSH_CONFIG"
fi

# 禁用密码认证
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG"
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG"

if ! grep -q "^PasswordAuthentication" "$SSH_CONFIG"; then
    echo "PasswordAuthentication no" >> "$SSH_CONFIG"
fi

# 确保 PermitRootLogin 配置（可选，建议禁用 root 登录）
if ! grep -q "^PermitRootLogin" "$SSH_CONFIG"; then
    echo "PermitRootLogin no" >> "$SSH_CONFIG"
fi

echo ""
echo "SSH 配置已更新:"
echo "  - PubkeyAuthentication: yes"
echo "  - PasswordAuthentication: no"

# 设置用户的 SSH 目录和公钥
# 优先使用环境变量 TARGET_USER，其次从文件读取，最后使用默认值 four
if [ -z "$TARGET_USER" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TARGET_USER_FILE="$SCRIPT_DIR/../.target_user"
    if [ -f "$TARGET_USER_FILE" ]; then
        TARGET_USER=$(cat "$TARGET_USER_FILE" 2>/dev/null | head -1)
    fi
    # 如果文件不存在或为空，使用默认值
    if [ -z "$TARGET_USER" ]; then
        TARGET_USER="four"
    fi
fi

if id "$TARGET_USER" &>/dev/null; then
    echo ""
    echo "配置 $TARGET_USER 用户的 SSH 公钥..."
    mkdir -p "/home/$TARGET_USER/.ssh"
    chmod 700 "/home/$TARGET_USER/.ssh"
    chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.ssh"
    echo "$SSH_KEY" > "/home/$TARGET_USER/.ssh/authorized_keys"
    chmod 600 "/home/$TARGET_USER/.ssh/authorized_keys"
    chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.ssh/authorized_keys"
    echo "SSH 公钥已保存到 /home/$TARGET_USER/.ssh/authorized_keys"
else
    echo ""
    echo "警告: 用户 $TARGET_USER 不存在，跳过该用户的 SSH 公钥配置"
fi

# 设置 root 用户的 SSH 目录和公钥
echo ""
echo "配置 root 用户的 SSH 公钥..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "$SSH_KEY" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "SSH 公钥已保存到 /root/.ssh/authorized_keys"

echo ""
read -p "是否现在重启 SSH 服务? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart sshd
    echo "SSH 服务已重启"
else
    echo "请稍后手动重启 SSH 服务: systemctl restart sshd"
fi

echo "SSH 配置模块完成"

