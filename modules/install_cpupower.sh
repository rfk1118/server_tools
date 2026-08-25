#!/bin/bash
set -e

virtual_machine() { command -v systemd-detect-virt >/dev/null && systemd-detect-virt -q; }
if [ "${1:-}" = --check ]; then virtual_machine || command -v cpupower >/dev/null 2>&1; exit; fi
if virtual_machine; then echo "虚拟机环境跳过可选的 cpupower 安装。"; exit 0; fi
if command -v cpupower >/dev/null 2>&1; then echo "cpupower 已安装。"; exit 0; fi
apt-get update
kernel_package="linux-tools-$(uname -r)"
if ! apt-get install -y "$kernel_package"; then
    echo "未找到 $kernel_package，回退安装 linux-tools-generic。"
    apt-get install -y linux-tools-generic
fi
command -v cpupower >/dev/null 2>&1 || { echo "错误: cpupower 安装后仍不可用" >&2; exit 1; }
