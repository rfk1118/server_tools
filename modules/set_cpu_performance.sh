#!/bin/bash
set -e

virtual_machine() { command -v systemd-detect-virt >/dev/null && systemd-detect-virt -q; }
supports_performance() { cpupower frequency-info -g 2>/dev/null | grep -qw performance; }
is_performance() { cpupower frequency-info -p 2>/dev/null | grep -qi 'performance'; }
service=/etc/systemd/system/set-cpu-performance.service
service_ready() {
    [ -f "$service" ] &&
        grep -Fqx 'After=systemd-modules-load.service' "$service" &&
        grep -Fqx "ExecStart=$(command -v cpupower) frequency-set -g performance" "$service" &&
        grep -Fqx 'RemainAfterExit=yes' "$service" &&
        grep -Fqx 'WantedBy=multi-user.target' "$service" &&
        systemctl is-enabled --quiet set-cpu-performance.service &&
        systemctl is-active --quiet set-cpu-performance.service
}
if [ "${1:-}" = --check ]; then
    if virtual_machine; then exit 0; fi
    command -v cpupower >/dev/null || exit 1
    supports_performance || exit 0
    is_performance && service_ready
    exit
fi
command -v cpupower >/dev/null || { echo "错误: 请先安装 cpupower" >&2; exit 1; }
if virtual_machine; then echo "虚拟机环境通常不支持 CPU governor；作为可选项跳过。"; exit 0; fi
if ! supports_performance; then echo "CPU 不提供 performance governor；作为可选项跳过。"; exit 0; fi
if is_performance; then
    echo "CPU governor 已是 performance，补齐持久化服务。"
else
    cpupower frequency-set -g performance || { echo "CPU 不支持 performance governor，跳过此可选项。"; exit 0; }
fi
is_performance || { echo "错误: CPU governor 未生效" >&2; exit 1; }
cat > "$service" <<EOF
[Unit]
Description=Set CPU governor to performance
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=$(command -v cpupower) frequency-set -g performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now set-cpu-performance.service
service_ready && is_performance || { echo "错误: CPU performance 持久化服务未能启用或生效" >&2; exit 1; }
echo "CPU governor 已设为 performance，并会在重启后自动设置。"
