#!/bin/bash

# 安装 MySQL Community Server（免费版），仅允许本地访问

set -e

find_mysql_conf() {
    for file in /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/my.cnf; do
        [ -f "$file" ] && { printf '%s\n' "$file"; return 0; }
    done
    return 1
}

if [ "${1:-}" = --check ]; then
    MYSQL_CONF=$(find_mysql_conf) && command -v mysql >/dev/null 2>&1 && systemctl is-active --quiet mysql && \
        systemctl is-enabled --quiet mysql && \
        grep -qE '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*127\.0\.0\.1[[:space:]]*$' "$MYSQL_CONF" 2>/dev/null
    exit
fi

echo ""
echo "安装 MySQL (Community Server)..."

MYSQL_INSTALLED=false
if command -v mysql &>/dev/null; then
    echo "检测到 MySQL 已安装: $(mysql --version)"
    MYSQL_INSTALLED=true
else
    echo "开始安装 MySQL..."
    apt-get update
    apt-get install -y mysql-server
    systemctl enable mysql
    systemctl start mysql
    echo "MySQL 安装完成"
    MYSQL_INSTALLED=true
fi

if [ "$MYSQL_INSTALLED" = true ]; then
    echo ""
    echo "配置 MySQL 仅允许本地访问..."

    MYSQL_CONF=$(find_mysql_conf || true)

    if [ -n "$MYSQL_CONF" ]; then
        echo "找到 MySQL 配置文件: $MYSQL_CONF"

        if systemctl is-active --quiet mysql && systemctl is-enabled --quiet mysql && \
            grep -qE '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*127\.0\.0\.1[[:space:]]*$' "$MYSQL_CONF"; then
            echo "MySQL 已仅监听本地地址，跳过。"
            exit 0
        fi

        if [ ! -f "${MYSQL_CONF}.bak" ]; then
            cp "$MYSQL_CONF" "${MYSQL_CONF}.bak"
            echo "已备份配置文件到: ${MYSQL_CONF}.bak"
        fi
        CONFIG_BACKUP=$(mktemp)
        cp -p "$MYSQL_CONF" "$CONFIG_BACKUP"

        if grep -qE "^[# ]*bind-address" "$MYSQL_CONF"; then
            sed -i -E "s/^[# ]*bind-address[[:space:]]*=.*/bind-address = 127.0.0.1/" "$MYSQL_CONF"
        else
            if grep -q "^\[mysqld\]" "$MYSQL_CONF"; then
                sed -i "/^\[mysqld\]/a bind-address = 127.0.0.1" "$MYSQL_CONF"
            else
                echo "" >> "$MYSQL_CONF"
                echo "[mysqld]" >> "$MYSQL_CONF"
                echo "bind-address = 127.0.0.1" >> "$MYSQL_CONF"
            fi
        fi

        echo "重启 MySQL 服务以应用配置..."
        if ! mysqld --validate-config >/dev/null 2>&1 || ! systemctl enable mysql || ! systemctl restart mysql || ! systemctl is-active --quiet mysql; then
            cp -p "$CONFIG_BACKUP" "$MYSQL_CONF"
            systemctl restart mysql || true
            rm -f "$CONFIG_BACKUP"
            echo "错误: MySQL 新配置无效或服务启动失败，已恢复旧配置" >&2
            exit 1
        else
            rm -f "$CONFIG_BACKUP"
            echo "MySQL 服务运行正常"
            echo "仅监听本地地址: 127.0.0.1"
        fi
    else
        echo "错误: 未找到 MySQL 配置文件，请手动设置 bind-address = 127.0.0.1" >&2
        exit 1
    fi
fi
