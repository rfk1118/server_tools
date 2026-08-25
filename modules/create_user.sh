#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER_FILE="$SCRIPT_DIR/../.target_user"
[ ! -L "$TARGET_USER_FILE" ] || { echo "错误: 拒绝使用符号链接形式的 .target_user。" >&2; exit 1; }
valid_user() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}[a-z0-9_]$ ]] || [[ "$1" =~ ^[a-z_]$ ]]; }
home_for() { getent passwd "$1" | awk -F: '{print $6}'; }

if [ "${1:-}" = --check ]; then
    user="${TARGET_USER:-$(head -n 1 "$TARGET_USER_FILE" 2>/dev/null || true)}"
    valid_user "$user" && command -v sudo >/dev/null 2>&1 && id "$user" >/dev/null 2>&1 && [ -d "$(home_for "$user")" ] && id -nG "$user" | tr ' ' '\n' | grep -qx sudo
    exit
fi

if [ -n "${TARGET_USER:-}" ]; then
    USERNAME="$TARGET_USER"
else
    DEFAULT_USER=$(head -n 1 "$TARGET_USER_FILE" 2>/dev/null || printf four)
    read -r -p "请输入用户名 (默认: $DEFAULT_USER): " USERNAME
    USERNAME="${USERNAME:-$DEFAULT_USER}"
    USERNAME=$(printf '%s' "$USERNAME" | tr -d '[:space:]')
fi
valid_user "$USERNAME" || { echo "错误: 用户名不符合 Linux 用户名规范" >&2; exit 1; }

if id "$USERNAME" >/dev/null 2>&1; then
    echo "用户 $USERNAME 已存在。"
    read -r -p "是否为 $USERNAME 设置或修改密码? (y/N): " change_password
    if [[ "$change_password" =~ ^[Yy]$ ]]; then passwd "$USERNAME"; fi
else
    useradd -m -s /bin/bash "$USERNAME"
    echo "请为用户 $USERNAME 设置密码："
    passwd "$USERNAME"
fi

USER_HOME=$(home_for "$USERNAME")
[ -n "$USER_HOME" ] && [ -d "$USER_HOME" ] || { echo "错误: 无法获取 $USERNAME 的 home 目录" >&2; exit 1; }
if ! command -v sudo >/dev/null 2>&1 || ! command -v visudo >/dev/null 2>&1 || ! getent group sudo >/dev/null; then
    apt-get update
    apt-get install -y sudo
fi
usermod -aG sudo "$USERNAME"

read -r -p "是否明确为 $USERNAME 启用 sudo 免密码? (yes/NO): " enable_nopasswd
if [ "$enable_nopasswd" = yes ]; then
    sudoers_file="/etc/sudoers.d/${USERNAME}_nopasswd"
    tmp_file=$(mktemp)
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USERNAME" > "$tmp_file"
    chmod 440 "$tmp_file"
    if visudo -c -f "$tmp_file" >/dev/null; then
        install -m 440 "$tmp_file" "$sudoers_file"
    else
        rm -f "$tmp_file"; echo "错误: sudoers 验证失败" >&2; exit 1
    fi
    rm -f "$tmp_file"
fi
printf '%s\n' "$USERNAME" > "$TARGET_USER_FILE"
echo "用户 $USERNAME 已就绪。"
