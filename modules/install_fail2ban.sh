#!/bin/bash
set -e

JAIL=/etc/fail2ban/jail.d/server-tools.local
ssh_port() { sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}'; }
configured() {
    [ -f "$JAIL" ] && grep -q '^\[sshd\]$' "$JAIL" && grep -qE '^enabled = (true|false)$' "$JAIL"
}
configured_for_port() { configured && grep -q "^port = $(ssh_port)$" "$JAIL"; }
restore_config() {
    if [ -s "$backup" ]; then cp "$backup" "$JAIL"; else rm -f "$JAIL"; fi
    fail2ban-client -t >/dev/null 2>&1 && systemctl restart fail2ban >/dev/null 2>&1 || true
}
if [ "${1:-}" = --check ]; then
    configured_for_port && fail2ban-client -t >/dev/null && systemctl is-enabled --quiet fail2ban &&
        systemctl is-active --quiet fail2ban
    exit
fi

if ! command -v fail2ban-client >/dev/null; then apt-get update; apt-get install -y fail2ban; fi
port=$(ssh_port); [ -n "$port" ] || { echo "错误: 无法识别 SSH 端口" >&2; exit 1; }
# In A, preserve existing managed limits and optional mail settings. Only
# repair a changed SSH port and ensure the service is running.
if [ "${SERVER_TOOLS_AUTO:-0}" = 1 ] && configured; then
    backup=$(mktemp)
    cp "$JAIL" "$backup"
    if ! configured_for_port; then sed -i -E "s|^port = .*|port = $port|" "$JAIL"; fi
    if ! fail2ban-client -t >/dev/null || ! systemctl enable --now fail2ban || ! systemctl restart fail2ban || ! systemctl is-active --quiet fail2ban; then
        restore_config; rm -f "$backup"; echo "错误: fail2ban 未能修复或启动，已回滚。" >&2; exit 1
    fi
    rm -f "$backup"
    echo "fail2ban 已保留现有参数，并确认 SSH 端口 $port 和服务状态。"
    exit 0
fi

bantime=3600; findtime=600; maxretry=3; email=false; destemail=; enable_sshd=true
if [ "${SERVER_TOOLS_AUTO:-0}" != 1 ]; then
    read -r -p "封禁时间秒数 (默认 3600): " input; bantime="${input:-$bantime}"
    read -r -p "查找窗口秒数 (默认 600): " input; findtime="${input:-$findtime}"
    read -r -p "最大尝试次数 (默认 3): " input; maxretry="${input:-$maxretry}"
    read -r -p "是否启用邮件通知? (y/N): " input
    if [[ "$input" =~ ^[Yy]$ ]]; then
        command -v sendmail >/dev/null || { echo "错误: 邮件通知需要已配置的 MTA (sendmail)" >&2; exit 1; }
        read -r -p "接收邮箱: " destemail; [ -n "$destemail" ] || { echo "错误: 未提供邮箱" >&2; exit 1; }; email=true
    fi
    read -r -p "是否启用 sshd jail? (Y/n): " input
    [[ "${input:-Y}" =~ ^[Nn]$ ]] && enable_sshd=false
fi
[[ "$bantime" =~ ^[0-9]+$ && "$findtime" =~ ^[0-9]+$ && "$maxretry" =~ ^[0-9]+$ ]] || { echo "错误: fail2ban 数值无效" >&2; exit 1; }
mkdir -p /etc/fail2ban/jail.d
backup=$(mktemp)
if [ -f "$JAIL" ]; then cp "$JAIL" "$backup"; else : > "$backup"; fi
{
    echo '[DEFAULT]'; echo "bantime = $bantime"; echo "findtime = $findtime"; echo "maxretry = $maxretry"
    if [ "$email" = true ]; then echo "destemail = $destemail"; echo 'mta = sendmail'; echo 'action = %(action_mwl)s'; fi
    printf '\n[sshd]\nenabled = %s\nport = %s\n' "$enable_sshd" "$port"
} > "$JAIL"
if ! fail2ban-client -t >/dev/null; then
    restore_config; rm -f "$backup"; echo "错误: fail2ban 配置验证失败，已回滚。" >&2; exit 1
fi
if ! systemctl enable --now fail2ban || ! systemctl restart fail2ban || ! systemctl is-active --quiet fail2ban; then
    restore_config; rm -f "$backup"; echo "错误: fail2ban 服务未能应用新配置，已回滚。" >&2; exit 1
fi
rm -f "$backup"
echo "fail2ban 已配置 SSH 端口 $port（sshd jail: $enable_sshd）。"
