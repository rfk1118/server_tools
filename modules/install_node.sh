#!/bin/bash
set -e

NVM_VERSION="${NVM_VERSION:-0.40.6}"
NVM_VERSION="${NVM_VERSION#v}"
NODE_VERSION="${NODE_VERSION:-24.19.0}"
[[ "$NVM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "错误: NVM_VERSION 格式无效" >&2; exit 1; }
[[ "$NODE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "错误: NODE_VERSION 格式无效" >&2; exit 1; }
target_user="${TARGET_USER:-}"
target_home() { getent passwd "$target_user" | awk -F: '{print $6}'; }
nvm_profile_ready() {
    local home profile
    home=$(target_home); profile="$home/.bashrc"
    [ ! -L "$profile" ] && grep -Fqx 'export NVM_DIR="$HOME/.nvm"' "$profile" 2>/dev/null &&
        grep -Fqx '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' "$profile" 2>/dev/null
}
ensure_nvm_profile() {
    local home profile profile_line_1 profile_line_2
    home=$(target_home); profile="$home/.bashrc"
    [ ! -L "$profile" ] || { echo "错误: 拒绝写入符号链接形式的 $profile" >&2; return 1; }
    profile_line_1='export NVM_DIR="$HOME/.nvm"'
    profile_line_2='[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    runuser -u "$target_user" -- env HOME="$home" bash -c '
profile="$HOME/.bashrc"
touch "$profile"
grep -Fqx "$1" "$profile" || printf "\n%s\n" "$1" >> "$profile"
grep -Fqx "$2" "$profile" || printf "%s\n" "$2" >> "$profile"
' _ "$profile_line_1" "$profile_line_2"
}
has_node_runtime() {
    local home; home=$(target_home)
    [ -s "$home/.nvm/nvm.sh" ] && runuser -u "$target_user" -- env HOME="$home" NVM_DIR="$home/.nvm" \
        bash -c '. "$NVM_DIR/nvm.sh" && [ "$(nvm --version)" = "$1" ] && node --version' _ "$NVM_VERSION" 2>/dev/null | grep -qx "v$NODE_VERSION" &&
        return 0
}
has_node() { has_node_runtime && nvm_profile_ready; }
if [ "${1:-}" = --check ]; then id "$target_user" >/dev/null 2>&1 && has_node; exit; fi
id "$target_user" >/dev/null 2>&1 || { echo "错误: Node.js 需要存在的 TARGET_USER" >&2; exit 1; }
command -v curl >/dev/null || { echo "错误: Node.js 安装需要 curl；请先运行 install_build_tools。" >&2; exit 1; }
has_node && { echo "用户 $target_user 已安装 Node.js v$NODE_VERSION 和 nvm $NVM_VERSION，跳过。"; exit 0; }
home=$(target_home)
[ ! -L "$home/.bashrc" ] || { echo "错误: 拒绝写入符号链接形式的 $home/.bashrc" >&2; exit 1; }
if has_node_runtime; then
    ensure_nvm_profile
    has_node && { echo "用户 $target_user 的 Node.js/nvm 已安装，仅补齐 shell 配置。"; exit 0; }
fi
# Always run the fixed installer: an existing nvm may be an unsafe old release.
runuser -u "$target_user" -- env HOME="$home" PROFILE=/dev/null \
    bash -o pipefail -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh | bash"
runuser -u "$target_user" -- env HOME="$home" NVM_DIR="$home/.nvm" \
    bash -c '. "$NVM_DIR/nvm.sh" && nvm install "$1" && nvm alias default "$1"' _ "$NODE_VERSION"
ensure_nvm_profile
has_node || { echo "错误: Node.js/nvm 安装验证失败" >&2; exit 1; }
echo "Node.js v$NODE_VERSION 已为 $target_user 安装（nvm $NVM_VERSION）。"
