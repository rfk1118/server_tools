#!/bin/bash

# 设置 CPU 模式为 performance 模块

set -e

echo ""
echo "设置 CPU 模式为 performance..."
# 检查 cpupower 是否可用并获取绝对路径
CPUPOWER_CMD=""
if [ -x "/usr/bin/cpupower" ]; then
    CPUPOWER_CMD="/usr/bin/cpupower"
elif command -v cpupower &> /dev/null; then
    CPUPOWER_CMD=$(command -v cpupower)
fi

if [ -n "$CPUPOWER_CMD" ]; then
    # 获取 CPU 核心数
    CPU_COUNT=$(nproc)
    echo "检测到 $CPU_COUNT 个 CPU 核心"
    
    # 使用 cpupower 设置所有 CPU 为 performance 模式
    if $CPUPOWER_CMD frequency-set -g performance 2>/dev/null; then
        echo "CPU 模式已设置为 performance"
        
        # 验证设置
        CURRENT_GOV=$($CPUPOWER_CMD frequency-info -p 2>/dev/null | grep -i "governor" | head -1 || echo "无法获取当前模式")
        echo "当前 CPU 模式: $CURRENT_GOV"
        
        # 创建 systemd 服务以确保开机自动设置（使用绝对路径）
        SYSTEMD_SERVICE="/etc/systemd/system/set-cpu-performance.service"
        cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Set CPU governor to performance
After=sysinit.target local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=$CPUPOWER_CMD frequency-set -g performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable set-cpu-performance.service
        echo "已创建 systemd 服务，确保开机自动设置 CPU 为 performance 模式"
    else
        echo "警告: 无法设置 CPU 模式，可能系统不支持 CPU 频率调节（如虚拟机环境）"
    fi
else
    echo "警告: cpupower 工具不可用，跳过 CPU 模式设置"
fi

echo "CPU 性能设置模块完成"

