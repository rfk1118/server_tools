#!/bin/bash
set -e

RUST_VERSION="${RUST_VERSION:-1.98.0}"
[[ "$RUST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "错误: RUST_VERSION 格式无效" >&2; exit 1; }
target_user="${TARGET_USER:-}"
target_home() { getent passwd "$target_user" | awk -F: '{print $6}'; }
rust_profile_ready() {
    local home profile
    home=$(target_home); profile="$home/.bashrc"
    [ ! -L "$profile" ] && grep -Fqx '. "$HOME/.cargo/env"' "$profile" 2>/dev/null
}
ensure_rust_profile() {
    local home profile profile_line
    home=$(target_home); profile="$home/.bashrc"; profile_line='. "$HOME/.cargo/env"'
    [ ! -L "$profile" ] || { echo "错误: 拒绝写入符号链接形式的 $profile" >&2; return 1; }
    runuser -u "$target_user" -- env HOME="$home" bash -c \
        'touch "$HOME/.bashrc"; grep -Fqx "$1" "$HOME/.bashrc" || printf "%s\n" "$1" >> "$HOME/.bashrc"' _ "$profile_line"
}
has_rust_runtime() {
    local home; home=$(target_home)
    runuser -u "$target_user" -- env HOME="$home" "$home/.cargo/bin/rustc" --version 2>/dev/null | grep -q "rustc $RUST_VERSION "
}
has_rust() { has_rust_runtime && rust_profile_ready; }
if [ "${1:-}" = --check ]; then id "$target_user" >/dev/null 2>&1 && has_rust; exit; fi
id "$target_user" >/dev/null 2>&1 || { echo "错误: Rust 需要存在的 TARGET_USER" >&2; exit 1; }
command -v curl >/dev/null || { echo "错误: Rust 安装需要 curl；请先运行 install_build_tools。" >&2; exit 1; }
has_rust && { echo "用户 $target_user 已安装 Rust $RUST_VERSION，跳过。"; exit 0; }
home=$(target_home)
[ ! -L "$home/.bashrc" ] || { echo "错误: 拒绝写入符号链接形式的 $home/.bashrc" >&2; exit 1; }
if has_rust_runtime; then
    ensure_rust_profile
    has_rust && { echo "用户 $target_user 的 Rust $RUST_VERSION 已安装，仅补齐 shell 配置。"; exit 0; }
fi
runuser -u "$target_user" -- env HOME="$home" RUSTUP_HOME="$home/.rustup" CARGO_HOME="$home/.cargo" \
    bash -o pipefail -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "$1"' _ "$RUST_VERSION"
ensure_rust_profile
has_rust || { echo "错误: Rust 安装验证失败" >&2; exit 1; }
echo "Rust $RUST_VERSION 已为 $target_user 安装。"
