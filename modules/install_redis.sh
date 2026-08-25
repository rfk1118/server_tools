#!/bin/bash
set -e

SOCKET_PATH=/var/run/redis/redis-server.sock
target_user="${TARGET_USER:-}"
key_tmp=""; keyring_tmp=""; conf_backup=""; conf=""; config_pending=0
cleanup() {
    [ -z "$key_tmp" ] || rm -f "$key_tmp"
    [ -z "$keyring_tmp" ] || rm -f "$keyring_tmp"
    if [ "$config_pending" -eq 1 ] && [ -n "$conf_backup" ] && [ -n "$conf" ]; then cp -p "$conf_backup" "$conf"; fi
    [ -z "$conf_backup" ] || rm -f "$conf_backup"
}
trap cleanup EXIT
find_conf() { for f in /etc/redis/redis.conf /etc/redis-server.conf /etc/redis.conf; do [ -f "$f" ] && { printf '%s\n' "$f"; return; }; done; return 1; }
conf_value() { awk -v key="$2" '$1 == key {print $2; exit}' "$1"; }
set_port() {
    local value="$1"
    if grep -qE '^[[:space:]]*#?[[:space:]]*port[[:space:]]+' "$conf"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*port[[:space:]]+.*|port $value|" "$conf"
    else
        printf '\nport %s\n' "$value" >> "$conf"
    fi
}
redis_ping() {
    if [ -S "$SOCKET_PATH" ]; then
        if [ -n "$target_user" ] && id "$target_user" >/dev/null 2>&1; then runuser -u "$target_user" -- redis-cli -s "$SOCKET_PATH" ping 2>/dev/null | grep -qx PONG
        else redis-cli -s "$SOCKET_PATH" ping 2>/dev/null | grep -qx PONG; fi
    else redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -qx PONG; fi
}
socket_ready() {
    local conf
    conf=$(find_conf) || return 1
    [ "$(conf_value "$conf" port)" = 0 ] && [ "$(conf_value "$conf" unixsocket)" = "$SOCKET_PATH" ] &&
        [ "$(conf_value "$conf" unixsocketperm)" = 770 ] && [ -S "$SOCKET_PATH" ] &&
        [ "$(stat -c %a "$SOCKET_PATH" 2>/dev/null)" = 770 ] &&
        id -nG "$target_user" | tr ' ' '\n' | grep -qx redis && redis_ping
}
if [ "${1:-}" = --check ]; then
    command -v redis-server >/dev/null && systemctl is-enabled --quiet redis-server &&
        systemctl is-active --quiet redis-server && redis_ping || exit 1
    if [ "${SERVER_TOOLS_AUTO:-0}" = 1 ]; then
        socket_ready || exit 1
    fi
    exit
fi

if ! command -v redis-server >/dev/null; then
    command -v curl >/dev/null && command -v gpg >/dev/null || { echo "错误: Redis 安装需要 curl 和 gpg；请先运行 install_build_tools。" >&2; exit 1; }
    apt-get update
    key_tmp=$(mktemp); keyring_tmp=$(mktemp)
    curl -fsSL https://packages.redis.io/gpg -o "$key_tmp"
    gpg --batch --yes --dearmor -o "$keyring_tmp" "$key_tmp"
    install -m 644 "$keyring_tmp" /usr/share/keyrings/redis-archive-keyring.gpg
    . /etc/os-release
    printf 'deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb %s main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/redis.list
    apt-get update; apt-get install -y redis
fi
systemctl enable --now redis-server
conf=$(find_conf) || { echo "错误: 未找到 Redis 配置文件" >&2; exit 1; }

if [ "${SERVER_TOOLS_AUTO:-0}" = 1 ]; then mode=socket
else
    read -r -p "使用 Unix socket（更适合本机服务）? (Y/n): " answer
    [ "${answer:-Y}" = n ] || [ "${answer:-Y}" = N ] && mode=tcp || mode=socket
fi
conf_backup=$(mktemp)
cp -p "$conf" "$conf_backup"
config_pending=1
if [ "$mode" = socket ]; then
    [ -n "$target_user" ] && id "$target_user" >/dev/null 2>&1 || { echo "错误: Unix socket 模式需要存在的 TARGET_USER。" >&2; exit 1; }
    mkdir -p "$(dirname "$SOCKET_PATH")"
    set_port 0
    grep -qE '^[[:space:]]*unixsocket[[:space:]]+' "$conf" && sed -i -E "s|^[[:space:]]*unixsocket[[:space:]]+.*|unixsocket $SOCKET_PATH|" "$conf" || printf '\nunixsocket %s\n' "$SOCKET_PATH" >> "$conf"
    grep -qE '^[[:space:]]*unixsocketperm[[:space:]]+' "$conf" && sed -i -E 's|^[[:space:]]*unixsocketperm[[:space:]]+.*|unixsocketperm 770|' "$conf" || printf 'unixsocketperm 770\n' >> "$conf"
    getent group redis >/dev/null || { echo "错误: Redis 组不存在。" >&2; exit 1; }
    usermod -aG redis "$target_user"
else
    set_port 6379
    sed -i -E 's|^[[:space:]]*unixsocket[[:space:]]+|# unixsocket |; s|^[[:space:]]*unixsocketperm[[:space:]]+|# unixsocketperm |' "$conf"
fi
valid=false
if systemctl restart redis-server && systemctl is-active --quiet redis-server; then
    if [ "$mode" = socket ]; then socket_ready && valid=true
    else redis_ping && valid=true; fi
fi
if [ "$valid" != true ]; then
    cp -p "$conf_backup" "$conf"
    config_pending=0
    systemctl restart redis-server || true
    if [ "$mode" = socket ]; then echo "错误: Redis Unix socket、目标用户组或 PING 验证失败，已恢复旧配置" >&2
    else echo "错误: Redis TCP PING 验证失败，已恢复旧配置" >&2; fi
    exit 1
fi
config_pending=0
echo "Redis 已就绪（$mode）。"
