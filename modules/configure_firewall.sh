#!/bin/bash

# 配置防火墙模块
# 支持预定义模板和自定义端口配置
# 默认开放22端口（SSH）

set -e

echo ""
echo "配置防火墙..."
echo ""

# 检查 ufw 是否已安装
if ! command -v ufw &> /dev/null; then
    echo "安装 ufw 防火墙工具..."
    apt-get update
    apt-get install -y ufw
    echo "ufw 安装完成"
fi

# 显示预定义模板
show_templates() {
    echo "预定义模板:"
    echo "  [1] Geth (默认)"
    echo "      端口: 22, 30000:31000 (P2P), 8545, 8546 (RPC)"
    echo ""
    echo "  [2] Web"
    echo "      端口: 22, 80 (HTTP), 443 (HTTPS)"
    echo ""
    echo "  [3] 自定义端口配置"
    echo ""
}

# 应用预定义模板（不包含SSH端口，因为会在后面统一添加）
apply_template() {
    local template="$1"
    
    case "$template" in
        "1"|"geth")
            echo "应用 Geth 模板..."
            ufw allow 30000:31000/tcp comment 'Geth P2P TCP'
            ufw allow 30000:31000/udp comment 'Geth P2P UDP'
            ufw allow 8545/tcp comment 'Geth HTTP RPC'
            ufw allow 8546/tcp comment 'Geth WebSocket RPC'
            echo "Geth 端口已开放"
            ;;
        "2"|"web")
            echo "应用 Web 模板..."
            ufw allow 80/tcp comment 'HTTP'
            ufw allow 443/tcp comment 'HTTPS'
            echo "Web 端口已开放"
            ;;
        *)
            echo "未知模板: $template"
            return 1
            ;;
    esac
}

# 自定义端口配置
custom_ports() {
    echo ""
    echo "自定义端口配置..."
    echo "格式说明:"
    echo "  - 单个端口: 8080"
    echo "  - 端口范围: 8000:9000"
    echo "  - 指定协议: 8080/tcp 或 8080/udp"
    echo "  - 多个端口用空格分隔: 8080 9090 10000"
    echo ""
    echo "示例: 8080 9090/tcp 10000:10010/udp"
    echo ""
    
    read -p "请输入要开放的端口（直接按回车跳过）: " ports_input
    
    if [ -z "$ports_input" ]; then
        echo "未输入端口，跳过自定义端口配置"
        return 0
    fi
    
    # 解析并添加端口
    for port_spec in $ports_input; do
        # 检查是否包含协议
        if [[ "$port_spec" == *"/"* ]]; then
            # 包含协议
            ufw allow "$port_spec" comment "Custom port: $port_spec"
            echo "已开放端口: $port_spec"
        else
            # 不包含协议，默认使用 tcp
            ufw allow "$port_spec/tcp" comment "Custom port: $port_spec"
            echo "已开放端口: $port_spec/tcp"
        fi
    done
    
    echo "自定义端口配置完成"
}

# 主配置流程
echo "请选择防火墙配置方式:"
echo ""
show_templates

read -p "请选择 (1-3，默认: 1): " choice
# 如果用户直接按回车，使用默认值 1 (geth)
if [ -z "$choice" ]; then
    choice="1"
fi

# 检查防火墙是否已启用
UFW_ENABLED=false
UFW_STATUS=$(ufw status 2>/dev/null || echo "inactive")
if echo "$UFW_STATUS" | grep -q "Status: active"; then
    UFW_ENABLED=true
    echo "警告: 防火墙当前已启用"
fi

# 重置 ufw 规则（如果需要）
read -p "是否重置现有防火墙规则? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ "$UFW_ENABLED" = true ]; then
        echo "正在禁用防火墙以重置规则..."
        ufw --force disable
    fi
    echo "重置防火墙规则..."
    ufw --force reset
    echo "防火墙规则已重置"
    UFW_ENABLED=false
fi

# 设置默认策略（只在重置后或首次配置时设置）
if ! ufw status | grep -q "Default:"; then
    echo ""
    echo "设置默认策略..."
    ufw default deny incoming
    ufw default allow outgoing
    echo "默认策略已设置: 禁止入站，允许出站"
fi

# 默认开放SSH端口（22），检查是否已存在
echo ""
SSH_EXISTS=false
if ufw status numbered 2>/dev/null | grep -q "22/tcp"; then
    SSH_EXISTS=true
fi

if [ "$SSH_EXISTS" = true ]; then
    echo "SSH端口 (22) 已存在，跳过添加"
else
    echo "开放SSH端口 (22)..."
    ufw allow 22/tcp comment 'SSH'
    echo "SSH端口已开放"
fi

# 根据用户选择应用配置
TEMPLATE_APPLIED=false
case "$choice" in
    "1"|"geth")
        apply_template "1"
        TEMPLATE_APPLIED=true
        ;;
    "2"|"web")
        apply_template "2"
        TEMPLATE_APPLIED=true
        ;;
    "3"|"custom")
        custom_ports
        ;;
    *)
        echo "无效选择，使用默认模板 Geth..."
        apply_template "1"
        TEMPLATE_APPLIED=true
        ;;
esac

# 如果应用了模板，询问是否继续添加自定义端口
if [ "$TEMPLATE_APPLIED" = true ]; then
    echo ""
    read -p "是否继续添加自定义端口? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        custom_ports
    fi
fi

# 显示防火墙状态
echo ""
echo "=========================================="
echo "防火墙规则预览:"
echo "=========================================="
ufw status numbered

echo ""
read -p "是否启用防火墙? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ufw --force enable
    echo ""
    echo "防火墙已启用"
    echo ""
    echo "注意: 如果当前通过SSH连接，请确保SSH端口(22)已正确开放，否则可能会断开连接！"
else
    echo "防火墙配置完成，但未启用"
    echo "稍后可以运行 'ufw enable' 启用防火墙"
fi

echo ""
echo "防火墙配置模块完成"

