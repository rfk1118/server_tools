#!/bin/bash

# Ubuntu 24.04 server bootstrap menu. Modules remain independently runnable.
# A is conservative: it excludes firewall changes, Redis restore, sysctl and MySQL.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
STATE_DIR="${SERVER_TOOLS_STATE_DIR:-/var/lib/server_tools}"
TARGET_USER_FILE="$SCRIPT_DIR/.target_user"
BASE_PROFILE=(create_user install_build_tools install_cpupower set_cpu_performance install_redis configure_ssh install_golang install_rust install_node install_fail2ban)
EXECUTION_ORDER=(create_user install_build_tools install_cpupower set_cpu_performance install_redis restore_redis_rdb configure_ssh configure_firewall install_golang install_rust install_node install_fail2ban configure_sysctl install_mysql_free)

read_target_user() { if [ -s "$TARGET_USER_FILE" ]; then head -n 1 "$TARGET_USER_FILE"; else printf '%s\n' four; fi; }
configured_target_user() { [ -s "$TARGET_USER_FILE" ] && head -n 1 "$TARGET_USER_FILE"; }
module_file() { printf '%s/%s.sh\n' "$MODULES_DIR" "$1"; }
marker_file() { printf '%s/%s.success\n' "$STATE_DIR" "$1"; }
module_is_current() { local file auto=0; file=$(module_file "$1"); [ "${2:-}" = base ] && auto=1; [ -f "$file" ] && TARGET_USER="$(read_target_user)" SERVER_TOOLS_AUTO="$auto" bash "$file" --check >/dev/null 2>&1; }
prepare_state_dir() {
    while [ "$STATE_DIR" != / ] && [[ "$STATE_DIR" == */ ]]; do STATE_DIR="${STATE_DIR%/}"; done
    case "$STATE_DIR" in
        ""|/|/var|/var/lib|/tmp|//*|*//*|*/../*|*/..|*/./*|*/.) return 1;;
        /*) ;;
        *) return 1;;
    esac
    [ ! -L "$STATE_DIR" ] || return 1
    if [ ! -d "$STATE_DIR" ]; then
        mkdir -p "$STATE_DIR" && chmod 0750 "$STATE_DIR" || return 1
        [ "$EUID" -ne 0 ] || chown root:root "$STATE_DIR" || return 1
    elif [ "$STATE_DIR" = /var/lib/server_tools ]; then
        chmod 0750 "$STATE_DIR" && chown root:root "$STATE_DIR" || return 1
    fi
}
mark_success() {
    local tmp
    prepare_state_dir || return 1
    tmp=$(mktemp "$STATE_DIR/.${1}.XXXXXX") || return 1
    chmod 0640 "$tmp" && mv -f "$tmp" "$(marker_file "$1")" || { rm -f "$tmp"; return 1; }
}
clear_success() { rm -f "$(marker_file "$1")"; }
should_skip_module() { [ "$1" = base ] && [ -f "$(marker_file "$2")" ] && module_is_current "$2" "$1"; }
contains_module() { local needle="$1" item; shift; for item in "$@"; do [ "$item" = "$needle" ] && return 0; done; return 1; }
module_dependencies() {
    case "$1" in
        install_build_tools) printf '%s\n' create_user;;
        set_cpu_performance) printf '%s\n' install_cpupower;;
        configure_ssh) printf '%s\n' create_user install_build_tools;;
        restore_redis_rdb) printf '%s\n' install_redis;;
        install_redis|install_node|install_rust) printf '%s\n' create_user install_build_tools;;
        install_golang) printf '%s\n' install_build_tools;;
    esac
}

add_with_dependencies() {
    local module="$1" dep
    while IFS= read -r dep; do
        [ -z "$dep" ] || add_with_dependencies "$dep"
    done < <(module_dependencies "$module")
    contains_module "$module" "${RESOLVED_MODULES[@]}" || RESOLVED_MODULES+=("$module")
}
sort_modules_by_dependencies() {
    local module; RESOLVED_MODULES=()
    for module in "$@"; do add_with_dependencies "$module"; done
    for module in "${EXECUTION_ORDER[@]}"; do contains_module "$module" "${RESOLVED_MODULES[@]}" && printf '%s\n' "$module"; done
    return 0
}
parse_selection() {
    local selection="$1" token; PARSED_MODULES=(); PARSED_PROFILE=manual
    selection=$(printf '%s' "$selection" | tr '[:upper:]' '[:lower:]')
    read -r -a tokens <<< "$selection"
    for token in "${tokens[@]}"; do
        case "$token" in
            a|all)
                [ "${#tokens[@]}" -eq 1 ] || { echo "A/all 不能与其他选择混用" >&2; return 1; }
                PARSED_MODULES=("${BASE_PROFILE[@]}"); PARSED_PROFILE=base; return 0 ;;
            1) PARSED_MODULES+=(create_user);; 2) PARSED_MODULES+=(install_build_tools);; 3) PARSED_MODULES+=(install_cpupower);; 4) PARSED_MODULES+=(set_cpu_performance);;
            5) PARSED_MODULES+=(install_redis);; 6) PARSED_MODULES+=(configure_ssh);; 7) PARSED_MODULES+=(configure_firewall);; 8) PARSED_MODULES+=(install_golang);;
            9) PARSED_MODULES+=(install_rust);; 10) PARSED_MODULES+=(install_node);; 11) PARSED_MODULES+=(install_fail2ban);; 12) PARSED_MODULES+=(configure_sysctl);;
            13) PARSED_MODULES+=(restore_redis_rdb);; 14) PARSED_MODULES+=(install_mysql_free);;
            *) echo "无效选择: $token" >&2; return 1;;
        esac
    done
    [ "${#PARSED_MODULES[@]}" -gt 0 ]
}
run_module() { local file user auto=0; file=$(module_file "$1"); user=$(configured_target_user || true); [ "${2:-}" = base ] && auto=1; [ -f "$file" ] || { echo "错误: 找不到模块: $1"; return 1; }; TARGET_USER="$user" SERVER_TOOLS_AUTO="$auto" bash "$file"; }

execute_modules() {
    local profile="$1"; shift
    local requested_modules=("$@") sorted_modules=() failed_modules=() module dep blocked_dep run_status failures=0 reply
    while IFS= read -r module; do sorted_modules+=("$module"); done < <(sort_modules_by_dependencies "$@")
    [ "${#sorted_modules[@]}" -gt 0 ] || { echo "未选择任何功能"; return 1; }
    echo "将按以下顺序执行：${sorted_modules[*]}"
    read -r -p "确认执行? (y/N): " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "已取消"; return 0; }
    for module in "${sorted_modules[@]}"; do
        blocked_dep=""
        while IFS= read -r dep; do
            if [ -n "$dep" ] && contains_module "$dep" "${failed_modules[@]}"; then blocked_dep="$dep"; break; fi
        done < <(module_dependencies "$module")
        if [ -n "$blocked_dep" ]; then
            clear_success "$module"
            echo "错误: $module 的依赖 $blocked_dep 失败，未执行下游模块。" >&2
            failed_modules+=("$module"); failures=$((failures + 1)); continue
        fi
        # Markers are only a cache: real module state always wins.
        if should_skip_module "$profile" "$module"; then
            echo "跳过 $module：上次成功且当前状态仍满足。"; continue
        fi
        if [ "$profile" = manual ] && ! contains_module "$module" "${requested_modules[@]}" && module_is_current "$module" "$profile"; then
            echo "跳过依赖 $module：当前状态已满足。"; continue
        fi
        echo "---- 执行模块: $module ----"
        if run_module "$module" "$profile"; then run_status=0; else run_status=$?; fi
        if [ "$run_status" -eq 2 ]; then
            clear_success "$module"
            # A canceled prerequisite is incomplete, so its dependents must not run.
            failed_modules+=("$module")
            echo "$module 已由用户取消，未记录成功状态。"
            continue
        fi
        if [ "$run_status" -eq 0 ] && module_is_current "$module" "$profile"; then
            if mark_success "$module"; then
                echo "$module 完成。"
            else
                clear_success "$module"; failed_modules+=("$module"); echo "错误: 无法保存 $module 的成功状态。" >&2; failures=$((failures + 1))
            fi
        else
            clear_success "$module"; failed_modules+=("$module"); echo "错误: 模块 $module 未成功完成。" >&2; failures=$((failures + 1))
        fi
    done
    [ "$failures" -eq 0 ] || { echo "完成，但有 $failures 个模块失败。" >&2; return 1; }
    echo "执行完成。"
}
show_menu() { cat <<'EOF'
==========================================
服务器初始化工具
  [1] 用户 [2] 构建工具 [3] cpupower [4] CPU performance
  [5] Redis [6] SSH [7] UFW [8] Go [9] Rust [10] Node.js
  [11] fail2ban [12] sysctl [13] 恢复 Redis RDB（破坏性）[14] MySQL
  [A] Ubuntu 基础配置（不含 UFW/RDB 恢复/sysctl/MySQL）
  [Q] 退出
EOF
}
main() {
    [ "$EUID" -eq 0 ] || { echo "请以 root 运行: sudo $0"; exit 1; }
    [ -d "$MODULES_DIR" ] || { echo "错误: 找不到 modules 目录"; exit 1; }
    while true; do
        show_menu; printf '目标用户: %s\n' "$(read_target_user)"; read -r -p "请选择: " selection
        case "${selection,,}" in q|quit|exit) return 0;; esac
        if parse_selection "$selection"; then
            execute_modules "$PARSED_PROFILE" "${PARSED_MODULES[@]}" || return 1
        fi
    done
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
