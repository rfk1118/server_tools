#!/bin/bash
set -e

default_version="${GO_VERSION:-1.25.5}"
path_line='export PATH=$PATH:/usr/local/go/bin'
architecture() { case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) return 1;; esac; }
has_version() { [ -x /usr/local/go/bin/go ] && /usr/local/go/bin/go version | grep -q "go$1 "; }
go_path_ready() {
    grep -Fqx "$path_line" /etc/profile || return 1
    if [ -n "${TARGET_USER:-}" ] && id "$TARGET_USER" >/dev/null 2>&1; then
        local home profile
        home=$(getent passwd "$TARGET_USER" | awk -F: '{print $6}'); profile="$home/.bashrc"
        [ ! -L "$profile" ] && grep -Fqx "$path_line" "$profile" 2>/dev/null
    fi
}
ensure_go_path() {
    grep -Fqx "$path_line" /etc/profile || printf '%s\n' "$path_line" >> /etc/profile
    if [ -n "${TARGET_USER:-}" ] && id "$TARGET_USER" >/dev/null 2>&1; then
        local home profile
        home=$(getent passwd "$TARGET_USER" | awk -F: '{print $6}')
        profile="$home/.bashrc"
        [ ! -L "$profile" ] || { echo "错误: 拒绝写入符号链接形式的 $profile" >&2; return 1; }
        runuser -u "$TARGET_USER" -- env HOME="$home" bash -c \
            'touch "$HOME/.bashrc"; grep -Fqx "$1" "$HOME/.bashrc" || printf "%s\n" "$1" >> "$HOME/.bashrc"' _ "$path_line"
    fi
}
need_build_tools() {
    command -v curl >/dev/null && command -v python3 >/dev/null && command -v sha256sum >/dev/null || {
        echo "错误: Go 安装需要 curl、python3 和 sha256sum；请先运行 install_build_tools。" >&2; exit 1
    }
}
if [ "${1:-}" = --check ]; then
    if [ "${SERVER_TOOLS_AUTO:-0}" = 1 ]; then has_version "$default_version" && go_path_ready
    else [ -x /usr/local/go/bin/go ] && /usr/local/go/bin/go version >/dev/null && go_path_ready; fi
    exit
fi
if [ "${SERVER_TOOLS_AUTO:-0}" = 1 ]; then version="$default_version"
else read -r -p "请输入 Go 版本号 (默认: $default_version): " requested; version="${requested:-$default_version}"; fi
[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "错误: Go 版本号格式无效: $version" >&2; exit 1; }
if [ -n "${TARGET_USER:-}" ] && id "$TARGET_USER" >/dev/null 2>&1; then
    target_profile="$(getent passwd "$TARGET_USER" | awk -F: '{print $6}')/.bashrc"
    [ ! -L "$target_profile" ] || { echo "错误: 拒绝写入符号链接形式的 $target_profile" >&2; exit 1; }
fi
if has_version "$version"; then
    ensure_go_path
    go_path_ready && { echo "Go $version 已安装且 PATH 已配置，跳过。"; exit 0; }
fi
need_build_tools
arch=$(architecture) || { echo "错误: 不支持的架构: $(uname -m)" >&2; exit 1; }
file="go${version}.linux-${arch}.tar.gz"; url="https://go.dev/dl/$file"
workdir=$(mktemp -d); trap 'rm -rf "$workdir"' EXIT
curl -fL --retry 3 -o "$workdir/$file" "$url"
curl -fL --retry 3 -o "$workdir/metadata.json" 'https://go.dev/dl/?mode=json&include=all'
expected=$(python3 - "$file" "$workdir/metadata.json" <<'PY'
import json, sys
filename, metadata = sys.argv[1:]
for release in json.load(open(metadata, encoding="utf-8")):
    for item in release.get("files", []):
        if item.get("filename") == filename:
            print(item.get("sha256", ""))
            raise SystemExit(0)
raise SystemExit(1)
PY
) || { echo "错误: Go 官方元数据中没有 $file 的 SHA-256" >&2; exit 1; }
[[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "错误: Go 官方校验和格式无效" >&2; exit 1; }
printf '%s  %s\n' "$expected" "$workdir/$file" | sha256sum -c -
tar -C "$workdir" -xzf "$workdir/$file"
[ -x "$workdir/go/bin/go" ] || { echo "错误: Go 归档内容无效" >&2; exit 1; }
backup="/usr/local/go.server-tools-backup.$$"
[ ! -e /usr/local/go ] || mv /usr/local/go "$backup"
mv "$workdir/go" /usr/local/go
if ! has_version "$version"; then
    rm -rf /usr/local/go; [ ! -e "$backup" ] || mv "$backup" /usr/local/go
    echo "错误: Go 安装验证失败，已恢复旧版本。" >&2; exit 1
fi
rm -rf "$backup"
ensure_go_path
go_path_ready || { echo "错误: Go PATH 配置验证失败" >&2; exit 1; }
/usr/local/go/bin/go version
