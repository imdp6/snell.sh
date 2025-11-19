#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# === 变量定义 ===
SNELL_VER="v5.0.1"
CONF_DIR="/etc/snell"
CONF_FILE="${CONF_DIR}/snell-server.conf"
SYSTEMD_FILE="/etc/systemd/system/snell.service"
BIN_PATH="/usr/local/bin/snell-server"

# === 颜色定义 ===
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

echo -e "${YELLOW}正在检查系统环境...${PLAIN}"

# 1. 检查并安装依赖 (Unzip)
if [ -x "$(command -v apt)" ]; then
    apt update -y && apt install unzip wget -y
elif [ -x "$(command -v yum)" ]; then
    yum install unzip wget -y
elif [ -x "$(command -v dnf)" ]; then
    dnf install unzip wget -y
else
    echo -e "${RED}未检测到 apt/yum/dnf，请手动安装 unzip 和 wget${PLAIN}"
    exit 1
fi

# 2. 架构检测 (AMD64 vs ARM64)
ARCH=$(uname -m)
if [[ $ARCH == "x86_64" ]]; then
    DL_ARCH="linux-amd64"
elif [[ $ARCH == "aarch64" ]]; then
    DL_ARCH="linux-aarch64"
else
    echo -e "${RED}不支持的架构: ${ARCH}${PLAIN}"
    exit 1
fi

# 3. 准备安装/更新
# 如果服务正在运行，先停止，避免二进制文件占用导致覆盖失败
if systemctl is-active --quiet snell; then
    echo -e "${YELLOW}发现正在运行的 Snell 服务，正在停止以进行更新...${PLAIN}"
    systemctl stop snell
fi

cd ~/
echo -e "${GREEN}正在下载 Snell Server [${SNELL_VER}] (${DL_ARCH})...${PLAIN}"
DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-${SNELL_VER}-${DL_ARCH}.zip"

wget --no-check-certificate -O snell.zip "${DOWNLOAD_URL}"

if [ $? -ne 0 ]; then
    echo -e "${RED}下载失败，请检查网络连接或版本号。${PLAIN}"
    exit 1
fi

unzip -o snell.zip
rm -f snell.zip
chmod +x snell-server
mv -f snell-server /usr/local/bin/

echo -e "${GREEN}Snell 核心程序安装/更新完毕。${PLAIN}"

# 4. 配置文件处理逻辑
if [ -f ${CONF_FILE} ]; then
    echo -e "${YELLOW}检测到现有配置文件，保留现有配置...${PLAIN}"
else
    echo -e "${GREEN}未检测到配置，开始生成新配置...${PLAIN}"
    mkdir -p ${CONF_DIR}
    
    # 交互式输入端口
    read -e -p "请输入 Snell 端口 [1-65535] (默认: 12312): " snell_port
    [[ -z "${snell_port}" ]] && snell_port="12312"

    # 交互式输入混淆
    read -e -p "请输入 obfs ( tls / http / off ) (默认: tls): " snell_obfs
    [[ -z "${snell_obfs}" ]] && snell_obfs="tls"

    # 生成随机 PSK
    PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

    # 写入配置
    cat > ${CONF_FILE} <<EOF
[snell-server]
listen = 0.0.0.0:${snell_port}
psk = ${PSK}
obfs = ${snell_obfs}
ipv6 = false
EOF
fi

# 5. Systemd 服务文件配置
# 无论是否存在，都重新写入一次 Systemd 文件以确保路径正确
cat > ${SYSTEMD_FILE} <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 6. 启动服务
echo -e "${GREEN}正在启动服务...${PLAIN}"
systemctl daemon-reload
systemctl enable snell
systemctl restart snell

# 7. 输出最终信息
echo
echo "================================================"
if systemctl is-active --quiet snell; then
    echo -e "状态: ${GREEN}已运行${PLAIN} | 版本: ${SNELL_VER}"
else
    echo -e "状态: ${RED}启动失败 (请检查 systemctl status snell)${PLAIN}"
fi
echo "================================================"
echo -e "${YELLOW}当前配置内容 /etc/snell/snell-server.conf :${PLAIN}"
echo "------------------------------------------------"
cat ${CONF_FILE}
echo "------------------------------------------------"
echo "如需在 Surge 中使用，请复制上方内容填写到配置文件。"
