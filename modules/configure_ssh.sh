#!/bin/bash
set -e

DROPIN_DIR=/etc/ssh/sshd_config.d
DROPIN="$DROPIN_DIR/00-server-tools.conf"
target_user="${TARGET_USER:-}"
if [ -z "$target_user" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    target_user=$(head -n 1 "$script_dir/../.target_user" 2>/dev/null || true)
fi
user_home() { getent passwd "$1" | awk -F: '{print $6}'; }
sshd_setting() { sshd -T 2>/dev/null | awk -v key="$1" '$1 == key {print $2; exit}'; }
ssh_hardened() {
    [ "$(sshd_setting pubkeyauthentication)" = yes ] && [ "$(sshd_setting passwordauthentication)" = no ] &&
        [ "$(sshd_setting kbdinteractiveauthentication)" = no ] && [ "$(sshd_setting permitrootlogin)" = no ]
}
sshd_active() {
    systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet ssh.service 2>/dev/null ||
        systemctl is-active --quiet sshd.service 2>/dev/null
}
key_content_valid() {
    local home keys
    home=$(user_home "$target_user") || return 1
    keys="$home/.ssh/authorized_keys"
    [ ! -L "$home/.ssh" ] && [ ! -L "$keys" ] && [ -s "$keys" ] && ssh-keygen -lf "$keys" >/dev/null 2>&1
}
has_key() {
    local home keys
    home=$(user_home "$target_user") || return 1
    keys="$home/.ssh/authorized_keys"
    key_content_valid &&
        [ "$(stat -c %a "$home/.ssh" 2>/dev/null)" = 700 ] && [ "$(stat -c %a "$keys" 2>/dev/null)" = 600 ] &&
        [ "$(stat -c %U "$home/.ssh" 2>/dev/null)" = "$target_user" ] && [ "$(stat -c %U "$keys" 2>/dev/null)" = "$target_user" ]
}
reload_sshd() {
    if systemctl list-unit-files --type=socket | grep -q '^ssh\.socket'; then
        systemctl reload ssh.service 2>/dev/null || systemctl restart ssh.service
    elif systemctl list-unit-files --type=service | grep -q '^sshd\.service'; then
        systemctl reload sshd.service
    elif systemctl list-unit-files --type=service | grep -q '^ssh\.service'; then
        systemctl reload ssh.service
    else
        return 1
    fi
}
if [ "${1:-}" = --check ]; then
    id "$target_user" >/dev/null 2>&1 && ssh_hardened && has_key && sshd_active
    exit
fi

id "$target_user" >/dev/null 2>&1 || { echo "错误: 目标用户不存在: $target_user" >&2; exit 1; }
if ! command -v sshd >/dev/null; then
    echo "未找到 sshd，安装 openssh-server。"
    apt-get update
    apt-get install -y openssh-server
fi
command -v sshd >/dev/null || { echo "错误: openssh-server 安装后仍未找到 sshd" >&2; exit 1; }
if ! systemctl list-unit-files --type=socket | grep -q '^ssh\.socket' && ! systemctl list-unit-files --type=service | grep -qE '^(ssh|sshd)\.service'; then
    echo "错误: 未找到 ssh/sshd 服务。" >&2; exit 1
fi
home=$(user_home "$target_user")
ssh_dir="$home/.ssh"; keys="$ssh_dir/authorized_keys"
target_group=$(id -gn "$target_user")
[ ! -L "$ssh_dir" ] && [ ! -L "$keys" ] || { echo "错误: 拒绝写入符号链接形式的 .ssh 或 authorized_keys。" >&2; exit 1; }
if key_content_valid; then
    chmod 700 "$ssh_dir"; chown "$target_user:$target_group" "$ssh_dir"
    chmod 600 "$keys"; chown "$target_user:$target_group" "$keys"
fi
if [ "${SERVER_TOOLS_AUTO:-0}" = 1 ] && ssh_hardened && has_key && sshd_active; then
    echo "SSH 加固和 $target_user 的公钥已满足，跳过。"; exit 0
fi
ssh_key=""
if [ "${SERVER_TOOLS_AUTO:-0}" = 1 ] && key_content_valid; then
    echo "复用 $target_user 已有的有效 authorized_keys。"
elif has_key; then
    printf '请粘贴要追加给 %s 的单行 SSH 公钥（留空取消）: ' "$target_user"
else
    printf '请粘贴 %s 的单行 SSH 公钥（留空取消）: ' "$target_user"
fi
if [ "${SERVER_TOOLS_AUTO:-0}" != 1 ] || ! key_content_valid; then
    IFS= read -r ssh_key
    if [ -z "$ssh_key" ]; then
        echo "未提供公钥，未修改 SSH 配置。"
        [ "${SERVER_TOOLS_AUTO:-0}" = 1 ] && exit 1 || exit 2
    fi
    printf '%s\n' "$ssh_key" | ssh-keygen -lf - >/dev/null 2>&1 || { echo "错误: 无效 SSH 公钥" >&2; exit 1; }
fi
mkdir -p "$ssh_dir"; chmod 700 "$ssh_dir"; chown "$target_user:$target_group" "$ssh_dir"
touch "$keys"; chmod 600 "$keys"; chown "$target_user:$target_group" "$keys"
if [ -n "$ssh_key" ] && ! grep -Fqx -- "$ssh_key" "$keys"; then
    printf '%s\n' "$ssh_key" >> "$keys"
fi

mkdir -p "$DROPIN_DIR"
previous=$(mktemp)
if [ -f "$DROPIN" ]; then cp "$DROPIN" "$previous"; else : > "$previous"; fi
cat > "$DROPIN" <<'EOF'
# Managed by server_tools. Ubuntu 24.04 reads sshd_config.d drop-ins.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
chmod 644 "$DROPIN"
if ! sshd -t || ! ssh_hardened; then
    if [ -s "$previous" ]; then cp "$previous" "$DROPIN"; else rm -f "$DROPIN"; fi
    rm -f "$previous"
    echo "错误: sshd 配置验证失败或未达到预期，已回滚 drop-in。" >&2
    exit 1
fi
if ! reload_sshd; then
    if [ -s "$previous" ]; then cp "$previous" "$DROPIN"; else rm -f "$DROPIN"; fi
    sshd -t || true
    reload_sshd || true
    rm -f "$previous"
    echo "错误: SSH 服务未能重载，已恢复旧 drop-in 并尝试恢复服务。" >&2
    exit 1
fi
rm -f "$previous"
echo "SSH 已配置为仅允许目标用户的公钥登录；未写入 root 公钥。"
