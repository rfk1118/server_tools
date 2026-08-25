#!/bin/bash
set -eo pipefail

service=redis-server
conf=""
tmp=""
target=""
backup=""
redis_stopped=0
target_replaced=0
had_target=0
REDIS_CLI_ARGS=()

find_conf() {
    local file
    for file in /etc/redis/redis.conf /etc/redis-server.conf /etc/redis.conf; do
        [ -f "$file" ] && { printf '%s\n' "$file"; return 0; }
    done
    return 1
}

conf_value() {
    awk -v key="$2" '
        $1 == key { value = $2 }
        END { gsub(/^"|"$/, "", value); print value }
    ' "$1"
}

configure_redis_cli() {
    local socket port
    socket=$(conf_value "$conf" unixsocket)
    port=$(conf_value "$conf" port)
    REDIS_CLI_ARGS=()
    if [ -n "$socket" ] && [ -S "$socket" ]; then
        REDIS_CLI_ARGS=(-s "$socket")
    elif [ "${port:-6379}" != 0 ]; then
        REDIS_CLI_ARGS=(-h 127.0.0.1 -p "${port:-6379}")
    else
        return 1
    fi
}

redis_cli() { redis-cli "${REDIS_CLI_ARGS[@]}" "$@"; }
redis_ping() { redis_cli --raw PING 2>/dev/null | tr -d '\r' | grep -qx PONG; }
redis_config_get() {
    local output value
    output=$(redis_cli --raw CONFIG GET "$1" 2>/dev/null) || return 1
    value=$(printf '%s\n' "$output" | tr -d '\r' | tail -n 1)
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

restored_instance_ready() {
    local info current_dir current_file
    configure_redis_cli && redis_ping || return 1
    current_dir=$(redis_config_get dir) || return 1
    current_file=$(redis_config_get dbfilename) || return 1
    [ "$current_dir" = "$rdb_dir" ] && [ "$current_file" = "$rdb_file" ] || return 1
    info=$(redis_cli --raw INFO persistence 2>/dev/null | tr -d '\r') || return 1
    grep -qx 'loading:0' <<< "$info" && grep -qx 'aof_enabled:0' <<< "$info"
}

rollback_after_failure() {
    systemctl stop "$service" >/dev/null 2>&1 || true
    if [ "$target_replaced" -eq 1 ]; then
        if [ "$had_target" -eq 1 ] && [ -f "$backup" ]; then
            if ! cp -p -- "$backup" "$target"; then
                echo "严重错误: 无法把备份恢复到 $target；备份仍位于 $backup" >&2
                return 1
            fi
        else
            rm -f -- "$target"
        fi
    fi
    if systemctl start "$service" && systemctl is-active --quiet "$service"; then
        echo "旧 Redis 数据文件和服务状态已恢复。" >&2
        return 0
    fi
    echo "严重错误: Redis 回滚后未能启动，请使用备份手动恢复: ${backup:-无旧 RDB}" >&2
    return 1
}

cleanup() {
    local status=$?
    [ -z "$tmp" ] || rm -f -- "$tmp"
    if [ "$status" -ne 0 ] && [ "$redis_stopped" -eq 1 ]; then
        rollback_after_failure || true
    fi
}
trap cleanup EXIT

if [ "${1:-}" = --check ]; then
    command -v redis-server >/dev/null && systemctl is-active --quiet "$service"
    exit
fi
[ "$#" -le 1 ] || { echo "用法: $0 [RDB 文件路径]" >&2; exit 1; }

command -v redis-server >/dev/null || { echo "错误: Redis 未安装" >&2; exit 1; }
command -v redis-cli >/dev/null || { echo "错误: 缺少 redis-cli" >&2; exit 1; }
command -v redis-check-rdb >/dev/null || { echo "错误: 缺少 redis-check-rdb" >&2; exit 1; }
systemctl is-active --quiet "$service" || { echo "错误: Redis 服务未运行；请先安装并启动 Redis。" >&2; exit 1; }

conf=$(find_conf) || { echo "错误: 未找到 Redis 配置文件" >&2; exit 1; }
configure_redis_cli && redis_ping || { echo "错误: 无法连接当前 Redis，未执行恢复。" >&2; exit 1; }
rdb_dir=$(redis_config_get dir) || { echo "错误: 无法读取 Redis 的有效 dir 配置。" >&2; exit 1; }
rdb_file=$(redis_config_get dbfilename) || { echo "错误: 无法读取 Redis 的有效 dbfilename 配置。" >&2; exit 1; }
appendonly=$(redis_config_get appendonly) || { echo "错误: 无法确认 Redis 的 AOF 状态。" >&2; exit 1; }
configured_appendonly=$(conf_value "$conf" appendonly)

if [ "$appendonly" = yes ] || [ "$configured_appendonly" = yes ]; then
    echo "错误: 当前 Redis 启用了 AOF；重启时 AOF 会优先于 RDB，已拒绝执行可能无效的 RDB 恢复。" >&2
    exit 1
fi
case "$rdb_dir" in /*) ;; *) echo "错误: Redis dir 不是绝对路径: $rdb_dir" >&2; exit 1;; esac
[ -n "$rdb_file" ] && [[ "$rdb_file" != */* ]] || { echo "错误: Redis dbfilename 无效: $rdb_file" >&2; exit 1; }
target="$rdb_dir/$rdb_file"

source="${1:-}"
if [ -z "$source" ]; then read -r -p "要恢复的 RDB 文件路径: " source; fi
[ -f "$source" ] || { echo "错误: RDB 文件不存在或不是普通文件: $source" >&2; exit 1; }
if [ -e "$target" ] && [ "$source" -ef "$target" ]; then
    echo "错误: 源文件就是当前 Redis RDB 文件，无需恢复。" >&2
    exit 1
fi
redis-check-rdb "$source" >/dev/null || { echo "错误: RDB 预检失败，未修改数据。" >&2; exit 1; }

echo "RDB 源文件: $source"
echo "Redis 目标: $target"
echo "恢复期间 Redis 会停止；当前目标文件会先备份。"
read -r -p '确认恢复? (yes/NO): ' confirm
[ "$confirm" = yes ] || { echo "已取消。"; exit 2; }

systemctl stop "$service" || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    systemctl is-active --quiet "$service" || break
    sleep 1
done
if systemctl is-active --quiet "$service"; then
    systemctl kill --signal=TERM "$service" || true
    for _ in 1 2 3 4 5; do
        systemctl is-active --quiet "$service" || break
        sleep 1
    done
fi
systemctl is-active --quiet "$service" && { echo "错误: Redis 未停止，未覆盖数据。" >&2; exit 1; }
redis_stopped=1

[ -d "$rdb_dir" ] || { echo "错误: Redis 数据目录不存在: $rdb_dir" >&2; exit 1; }
if [ -f "$target" ]; then
    had_target=1
    backup=$(mktemp "${target}.backup.$(date +%Y%m%d_%H%M%S).XXXXXX")
    if ! cp -p -- "$target" "$backup"; then
        rm -f -- "$backup"; backup=""
        echo "错误: 无法备份当前 RDB。" >&2
        exit 1
    fi
fi

tmp=$(mktemp "$rdb_dir/.${rdb_file}.server-tools.XXXXXX")
cp -- "$source" "$tmp"
cmp -s -- "$source" "$tmp" || { echo "错误: RDB 临时副本与源文件不一致。" >&2; exit 1; }
redis-check-rdb "$tmp" >/dev/null || { echo "错误: RDB 临时副本校验失败。" >&2; exit 1; }
if [ "$had_target" -eq 1 ]; then
    chown --reference="$target" "$tmp"
    chmod --reference="$target" "$tmp"
else
    chown --reference="$rdb_dir" "$tmp"
    chmod 640 "$tmp"
fi
target_replaced=1
mv -f -- "$tmp" "$target"
tmp=""

if ! systemctl start "$service" || ! systemctl is-active --quiet "$service" || ! restored_instance_ready; then
    echo "错误: 新 RDB 未能通过启动、PING 或 persistence 验证，正在自动回滚。" >&2
    exit 1
fi
redis_stopped=0
echo "RDB 恢复完成。备份: ${backup:-无旧 RDB}"
