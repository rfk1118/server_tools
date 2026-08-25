#!/bin/bash

# 安装构建相关软件模块

set -e

packages=(build-essential pkg-config clang libclang-dev git curl wget vim htop net-tools software-properties-common ca-certificates gnupg lsb-release python3 openssh-client)
target_user="${TARGET_USER:-}"
fzf_repo=https://github.com/junegunn/fzf.git
fzf_bashrc_line='[ -f ~/.fzf.bash ] && source ~/.fzf.bash'

packages_ready() {
    local package
    for package in "${packages[@]}"; do
        dpkg-query -W -f='${db:Status-Status}\n' "$package" 2>/dev/null | grep -qx installed || return 1
    done
}
tools_ready() { command -v pkg-config >/dev/null && command -v clang >/dev/null && command -v git >/dev/null && command -v runuser >/dev/null; }
target_home() { getent passwd "$target_user" | awk -F: '{print $6}'; }
fzf_ready() {
    local home
    id "$target_user" >/dev/null 2>&1 || return 1
    home=$(target_home)
    [ -n "$home" ] && [ -d "$home/.fzf/.git" ] && [ ! -L "$home/.fzf" ] &&
        [ -x "$home/.fzf/bin/fzf" ] && [ -s "$home/.fzf.bash" ] && [ ! -L "$home/.bashrc" ] &&
        grep -Fqx "$fzf_bashrc_line" "$home/.bashrc" 2>/dev/null &&
        runuser -u "$target_user" -- env HOME="$home" "$home/.fzf/bin/fzf" --version >/dev/null 2>&1
}

if [ "${1:-}" = --check ]; then
    packages_ready && tools_ready && fzf_ready
    exit 0
fi

echo ""
echo "安装构建相关软件..."
[ -n "$target_user" ] && id "$target_user" >/dev/null 2>&1 || { echo "错误: fzf 安装需要存在的 TARGET_USER" >&2; exit 1; }
home=$(target_home)
[ -n "$home" ] && [ -d "$home" ] || { echo "错误: 无法获取用户 $target_user 的 home 目录" >&2; exit 1; }
[ ! -L "$home/.fzf" ] || { echo "错误: 拒绝使用符号链接形式的 $home/.fzf" >&2; exit 1; }
[ ! -L "$home/.bashrc" ] || { echo "错误: 拒绝写入符号链接形式的 $home/.bashrc" >&2; exit 1; }

if ! packages_ready; then
    apt-get update
    apt-get install -y "${packages[@]}"
fi
tools_ready || {
    echo "错误: pkg-config、clang、git 或 runuser 安装后仍不可用" >&2
    exit 1
}

if fzf_ready; then
    echo "用户 $target_user 已通过 GitHub 安装 fzf，跳过。"
else
    if [ ! -e "$home/.fzf" ]; then
        runuser -u "$target_user" -- env HOME="$home" git clone --depth 1 "$fzf_repo" "$home/.fzf"
    elif [ ! -d "$home/.fzf/.git" ]; then
        echo "错误: $home/.fzf 已存在但不是 fzf Git 仓库" >&2
        exit 1
    fi
    remote=$(runuser -u "$target_user" -- env HOME="$home" git -C "$home/.fzf" remote get-url origin)
    [ "$remote" = "$fzf_repo" ] || { echo "错误: $home/.fzf 的 origin 不是 $fzf_repo" >&2; exit 1; }
    runuser -u "$target_user" -- env HOME="$home" "$home/.fzf/install" --all
    fzf_ready || { echo "错误: 用户 $target_user 的 fzf 安装验证失败" >&2; exit 1; }
fi
echo "构建工具安装完成"
