#!/bin/bash
set -e

ssh_port() { sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}'; }
rule_exists() { ufw status 2>/dev/null | awk -v rule="$1" '$1 == rule { found = 1 } END { exit !found }'; }
valid_port_spec() {
    local value="$1" first last
    [[ "$value" =~ ^([0-9]{1,5})(:([0-9]{1,5}))?(/(tcp|udp))?$ ]] || return 1
    first="${BASH_REMATCH[1]}"; last="${BASH_REMATCH[3]:-$first}"
    [ "$first" -ge 1 ] && [ "$first" -le 65535 ] && [ "$last" -ge "$first" ] && [ "$last" -le 65535 ]
}
if [ "${1:-}" = --check ]; then command -v ufw >/dev/null && rule_exists "$(ssh_port)/tcp"; exit; fi

if ! command -v ufw >/dev/null; then apt-get update; apt-get install -y ufw; fi
port=$(ssh_port); [ -n "$port" ] || { echo "错误: 无法检测 sshd 端口；请先检查 sshd 配置。" >&2; exit 1; }
echo "SSH 端口: $port"
echo "请选择配置: 1) Geth P2P（不公开 RPC） 2) Web 3) 自定义 4) 取消"
read -r -p '选择: ' choice
rules=("$port/tcp")
case "$choice" in
    1|geth) rules+=(30000:31000/tcp 30000:31000/udp);;
    2|web) rules+=(80/tcp 443/tcp);;
    3|custom)
        read -r -p '开放端口（空格分隔；RPC 8545/8546 请确认风险）: ' custom
        [ -n "$custom" ] || { echo "未添加自定义端口。"; }
        read -r -a custom_rules <<< "$custom"
        for item in "${custom_rules[@]}"; do
            valid_port_spec "$item" || { echo "错误: 无效端口规则: $item" >&2; exit 1; }
            [[ "$item" == */* ]] && rules+=("$item") || rules+=("$item/tcp")
        done;;
    4|cancel|'') echo "已取消。"; exit 2;;
    *) echo "错误: 无效选择。" >&2; exit 1;;
esac
echo "计划：保留现有 UFW 规则，仅新增以下缺失规则："
for rule in "${rules[@]}"; do rule_exists "$rule" && echo "  已满足 $rule" || echo "  新增 $rule"; done
read -r -p '确认应用该计划? (y/N): ' confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "已取消。"; exit 2; }
for rule in "${rules[@]}"; do rule_exists "$rule" || ufw allow "$rule"; done
echo "当前规则："; ufw status numbered
if ! ufw status | grep -q 'Status: active'; then
    read -r -p '是否启用 UFW? (y/N): ' enable
    [[ "$enable" =~ ^[Yy]$ ]] && ufw --force enable
fi
