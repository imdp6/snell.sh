#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# === 变量定义 ===
SNELL_VER="${SNELL_VER:-v5.0.1}"
SNELL_ZIP="${SNELL_ZIP:-}"
SNELL_BIN="${SNELL_BIN:-}"
SNELL_URL="${SNELL_URL:-}"
SNELL_FORCE_IPV6="${SNELL_FORCE_IPV6:-0}"
SNELL_PSK="${SNELL_PSK:-}"
SNELL_IPV6="${SNELL_IPV6:-}"
SNELL_STACK="${SNELL_STACK:-auto}"
SNELL_LISTEN="${SNELL_LISTEN:-}"
SNELL_SHA256="${SNELL_SHA256:-}"
SNELL_SHA256_URL="${SNELL_SHA256_URL:-}"
SNELL_REINIT="${SNELL_REINIT:-0}"
SNELL_BACKUP="${SNELL_BACKUP:-0}"
SNELL_NONINTERACTIVE="${SNELL_NONINTERACTIVE:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
CONF_DIR="/etc/snell"
CONF_FILE="${CONF_DIR}/snell-server.conf"
SYSTEMD_FILE="/etc/systemd/system/snell.service"
BIN_PATH="/usr/local/bin/snell-server"

# === 颜色定义 ===
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行该脚本。${PLAIN}"
    exit 1
fi

usage() {
    cat <<EOF
用法: ./update_snell.sh [选项]
  -y, --yes               非交互模式并默认启用优化/BBR
      --non-interactive   非交互模式（未指定则保持默认否）
      --optimize          启用系统优化
      --no-optimize       禁用系统优化
      --bbr               启用 BBR
      --no-bbr            禁用 BBR
      --reinit            重新生成配置（会备份）
      --backup            仅备份现有配置
      --stack <mode>      auto/ipv4/ipv6/dual
      --listen <addr>     指定监听地址，如 0.0.0.0:12312 或 :::12312
  -h, --help              显示帮助
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)
            ASSUME_YES=1
            SNELL_NONINTERACTIVE=1
            ;;
        --non-interactive)
            SNELL_NONINTERACTIVE=1
            ;;
        --optimize)
            ENABLE_OPTIMIZE=1
            ;;
        --no-optimize)
            ENABLE_OPTIMIZE=0
            ;;
        --bbr)
            ENABLE_BBR=1
            ;;
        --no-bbr)
            ENABLE_BBR=0
            ;;
        --reinit)
            SNELL_REINIT=1
            ;;
        --backup)
            SNELL_BACKUP=1
            ;;
        --stack)
            shift
            if [ -z "$1" ]; then
                echo -e "${RED}缺少 --stack 参数值${PLAIN}"
                exit 1
            fi
            SNELL_STACK="$1"
            ;;
        --listen)
            shift
            if [ -z "$1" ]; then
                echo -e "${RED}缺少 --listen 参数值${PLAIN}"
                exit 1
            fi
            SNELL_LISTEN="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${PLAIN}"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$SNELL_NONINTERACTIVE" = "1" ] && [ "$ASSUME_YES" != "1" ]; then
    [ -z "${ENABLE_OPTIMIZE}" ] && ENABLE_OPTIMIZE=0
    [ -z "${ENABLE_BBR}" ] && ENABLE_BBR=0
fi
if [ "$ASSUME_YES" = "1" ]; then
    [ -z "${ENABLE_OPTIMIZE}" ] && ENABLE_OPTIMIZE=1
    [ -z "${ENABLE_BBR}" ] && ENABLE_BBR=1
fi

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
case "$ARCH" in
    x86_64|amd64)
        DL_ARCH="linux-amd64"
        ;;
    aarch64|arm64)
        DL_ARCH="linux-aarch64"
        ;;
    armv7l)
        DL_ARCH="linux-armv7l"
        ;;
    i386|i686)
        DL_ARCH="linux-i386"
        ;;
    *)
        echo -e "${RED}不支持的架构: ${ARCH}${PLAIN}"
        exit 1
        ;;
esac

is_true() {
    case "$1" in
        1|true|TRUE|yes|YES|y|Y) return 0 ;;
    esac
    return 1
}

is_false() {
    case "$1" in
        0|false|FALSE|no|NO|n|N) return 0 ;;
    esac
    return 1
}

detect_ipv4() {
    if command -v ip >/dev/null 2>&1; then
        ip -4 addr show scope global | grep -q "inet "
        return $?
    fi
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig | grep -E "inet " | grep -v "127\.0\.0\.1" >/dev/null 2>&1
        return $?
    fi
    if [ -r /proc/net/fib_trie ]; then
        awk '/32 host/ {getline; if ($2 !~ /127\.0\.0\.1/) {found=1; exit}} END {exit(found?0:1)}' /proc/net/fib_trie
        return $?
    fi
    return 1
}

detect_ipv6() {
    if [ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" = "1" ]; then
            return 1
        fi
    fi
    if command -v ip >/dev/null 2>&1; then
        ip -6 addr show scope global | grep -q "inet6 "
        return $?
    fi
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig | grep -Ei "inet6" | grep -vE "(fe80|::1)" >/dev/null 2>&1
        return $?
    fi
    if [ -r /proc/net/if_inet6 ]; then
        awk '$1 !~ /^fe80/ && $1 != "00000000000000000000000000000001" {found=1; exit} END {exit(found?0:1)}' /proc/net/if_inet6
        return $?
    fi
    return 1
}

has_systemd() {
    command -v systemctl >/dev/null 2>&1 || return 1
    [ -d /run/systemd/system ] || return 1
    return 0
}

EXPECTED_SHA256="${SNELL_SHA256}"

load_expected_sha256() {
    if [ -n "${EXPECTED_SHA256}" ]; then
        return 0
    fi
    if [ -z "${SNELL_SHA256_URL}" ]; then
        return 0
    fi
    local tmp_file=""
    tmp_file="$(mktemp)"
    local wget_sha_opts=(--no-check-certificate --timeout=15 --tries=5 --retry-connrefused --waitretry=2 -O "${tmp_file}")
    if [ "${SNELL_FORCE_IPV6}" = "1" ]; then
        wget_sha_opts=(-6 "${wget_sha_opts[@]}")
    fi
    if ! wget "${wget_sha_opts[@]}" "${SNELL_SHA256_URL}"; then
        rm -f "${tmp_file}"
        echo -e "${RED}下载 SHA256 校验文件失败。${PLAIN}"
        return 1
    fi
    EXPECTED_SHA256="$(awk 'match($0, /[A-Fa-f0-9]{64}/) {print substr($0, RSTART, RLENGTH); exit}' "${tmp_file}")"
    rm -f "${tmp_file}"
    if [ -z "${EXPECTED_SHA256}" ]; then
        echo -e "${RED}未能解析 SHA256 校验值。${PLAIN}"
        return 1
    fi
    return 0
}

verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual=""

    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "${file}" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
    elif command -v openssl >/dev/null 2>&1; then
        actual="$(openssl dgst -sha256 "${file}" | awk '{print $2}')"
    else
        echo -e "${RED}未找到 SHA256 校验工具。${PLAIN}"
        return 1
    fi

    if [ "${actual}" != "${expected}" ]; then
        echo -e "${RED}SHA256 校验失败。${PLAIN}"
        echo -e "${YELLOW}期望: ${expected}${PLAIN}"
        echo -e "${YELLOW}实际: ${actual}${PLAIN}"
        return 1
    fi
    echo -e "${GREEN}SHA256 校验通过。${PLAIN}"
    return 0
}

verify_sha256_if_needed() {
    if [ -z "${SNELL_SHA256}" ] && [ -z "${SNELL_SHA256_URL}" ]; then
        return 0
    fi
    if ! load_expected_sha256; then
        return 1
    fi
    if [ -z "${EXPECTED_SHA256}" ]; then
        echo -e "${RED}未能获取 SHA256 校验值。${PLAIN}"
        return 1
    fi
    verify_sha256 "$1" "${EXPECTED_SHA256}"
}

backup_config() {
    local ts=""
    local backup_path=""
    ts="$(date +%Y%m%d%H%M%S)"
    backup_path="${CONF_FILE}.${ts}.bak"
    cp -f "${CONF_FILE}" "${backup_path}"
    echo -e "${GREEN}已备份配置到 ${backup_path}${PLAIN}"
}

HAS_SYSTEMD=0
if has_systemd; then
    HAS_SYSTEMD=1
fi

# 3. 准备安装/更新
install_from_zip() {
    local zip_path="$1"
    local cleanup="$2"
    local tmp_dir=""

    tmp_dir="$(mktemp -d)"
    if ! unzip -o "${zip_path}" -d "${tmp_dir}"; then
        echo -e "${RED}解压失败，请检查 ZIP 文件是否完整。${PLAIN}"
        rm -rf "${tmp_dir}"
        if [ "${cleanup}" = "1" ]; then
            rm -f "${zip_path}"
        fi
        exit 1
    fi
    if [ "${cleanup}" = "1" ]; then
        rm -f "${zip_path}"
    fi
    if [ ! -f "${tmp_dir}/snell-server" ]; then
        echo -e "${RED}未在 ZIP 中找到 snell-server${PLAIN}"
        rm -rf "${tmp_dir}"
        exit 1
    fi
    chmod +x "${tmp_dir}/snell-server"
    mv -f "${tmp_dir}/snell-server" "${BIN_PATH}"
    rm -rf "${tmp_dir}"
}

install_from_bin() {
    local bin_path="$1"

    cp -f "${bin_path}" "${BIN_PATH}"
    chmod +x "${BIN_PATH}"
}

# 如果服务正在运行，先停止，避免二进制文件占用导致覆盖失败
if [ "${HAS_SYSTEMD}" = "1" ] && systemctl is-active --quiet snell; then
    echo -e "${YELLOW}发现正在运行的 Snell 服务，正在停止以进行更新...${PLAIN}"
    systemctl stop snell
fi

if [ -n "${SNELL_BIN}" ]; then
    if [ ! -f "${SNELL_BIN}" ]; then
        echo -e "${RED}本地 Snell 二进制文件不存在: ${SNELL_BIN}${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}使用本地 Snell 二进制文件安装: ${SNELL_BIN}${PLAIN}"
    if ! verify_sha256_if_needed "${SNELL_BIN}"; then
        exit 1
    fi
    install_from_bin "${SNELL_BIN}"
elif [ -n "${SNELL_ZIP}" ]; then
    if [ ! -f "${SNELL_ZIP}" ]; then
        echo -e "${RED}本地 Snell ZIP 文件不存在: ${SNELL_ZIP}${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}使用本地 Snell ZIP 文件安装: ${SNELL_ZIP}${PLAIN}"
    if ! verify_sha256_if_needed "${SNELL_ZIP}"; then
        exit 1
    fi
    install_from_zip "${SNELL_ZIP}" "0"
else
    if [ -n "${SNELL_URL}" ]; then
        DOWNLOAD_URL="${SNELL_URL}"
    else
        DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-${SNELL_VER}-${DL_ARCH}.zip"
    fi

    echo -e "${GREEN}正在下载 Snell Server [${SNELL_VER}] (${DL_ARCH})...${PLAIN}"

    tmp_zip="$(mktemp)"
    WGET_OPTS=(--no-check-certificate --timeout=15 --tries=5 --retry-connrefused --waitretry=2 -O "${tmp_zip}")
    if [ "${SNELL_FORCE_IPV6}" = "1" ]; then
        WGET_OPTS=(-6 "${WGET_OPTS[@]}")
    fi

    wget "${WGET_OPTS[@]}" "${DOWNLOAD_URL}"
    if [ $? -ne 0 ]; then
        rm -f "${tmp_zip}"
        echo -e "${RED}下载失败，请检查网络连接或版本号。${PLAIN}"
        echo -e "${YELLOW}IPv6-only 可尝试:${PLAIN} SNELL_FORCE_IPV6=1 或设置可访问的镜像 URL:"
        echo -e "  SNELL_URL=<url> ./update_snell.sh"
        echo -e "${YELLOW}也可使用本地文件安装:${PLAIN}"
        echo -e "  SNELL_BIN=/root/snell-server ./update_snell.sh"
        echo -e "  SNELL_ZIP=/root/snell-server-${SNELL_VER}-${DL_ARCH}.zip ./update_snell.sh"
        exit 1
    fi

    if ! verify_sha256_if_needed "${tmp_zip}"; then
        rm -f "${tmp_zip}"
        exit 1
    fi

    install_from_zip "${tmp_zip}" "1"
fi

echo -e "${GREEN}Snell 核心程序安装/更新完毕。${PLAIN}"

# 4. 配置文件处理逻辑
need_init="0"
if [ -f ${CONF_FILE} ]; then
    if is_true "${SNELL_BACKUP}" || is_true "${SNELL_REINIT}"; then
        backup_config
    fi
    if is_true "${SNELL_REINIT}"; then
        echo -e "${YELLOW}检测到现有配置文件，按要求重建配置...${PLAIN}"
        need_init="1"
    else
        echo -e "${YELLOW}检测到现有配置文件，保留现有配置...${PLAIN}"
    fi
else
    echo -e "${GREEN}未检测到配置，开始生成新配置...${PLAIN}"
    need_init="1"
fi

if [ "${need_init}" = "1" ]; then
    mkdir -p ${CONF_DIR}

    # 交互式输入端口
    if [ -n "${SNELL_LISTEN}" ]; then
        snell_port="${SNELL_PORT:-12312}"
    elif [ -z "${SNELL_PORT}" ]; then
        if [ "${SNELL_NONINTERACTIVE}" = "1" ] || [ "${ASSUME_YES}" = "1" ]; then
            snell_port="12312"
        else
            read -e -p "请输入 Snell 端口 [1-65535] (默认: 12312): " snell_port
            [[ -z "${snell_port}" ]] && snell_port="12312"
        fi
    else
        snell_port="${SNELL_PORT}"
    fi

    # 交互式输入混淆
    if [ -z "${SNELL_OBFS}" ]; then
        if [ "${SNELL_NONINTERACTIVE}" = "1" ] || [ "${ASSUME_YES}" = "1" ]; then
            snell_obfs="tls"
        else
            read -e -p "请输入 obfs ( tls / http / off ) (默认: tls): " snell_obfs
            [[ -z "${snell_obfs}" ]] && snell_obfs="tls"
        fi
    else
        snell_obfs="${SNELL_OBFS}"
    fi

    # 生成随机 PSK（如设置 SNELL_PSK 则使用用户指定）
    if [ -n "${SNELL_PSK}" ]; then
        PSK="${SNELL_PSK}"
    else
        PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    fi

    case "${snell_obfs}" in
        tls|http|off) ;;
        *)
            echo -e "${YELLOW}obfs 输入无效，已回退为 tls${PLAIN}"
            snell_obfs="tls"
            ;;
    esac

    snell_ipv6=""
    snell_ipv6_forced="0"
    if [ -n "${SNELL_IPV6}" ]; then
        if is_true "${SNELL_IPV6}"; then
            snell_ipv6="true"
            snell_ipv6_forced="1"
        elif is_false "${SNELL_IPV6}"; then
            snell_ipv6="false"
            snell_ipv6_forced="1"
        fi
    fi

    snell_listen=""
    snell_dual="0"
    if [ -n "${SNELL_LISTEN}" ]; then
        snell_listen="${SNELL_LISTEN}"
        if [ -z "${snell_ipv6}" ]; then
            case "${snell_listen}" in
                *"::"*) snell_ipv6="true" ;;
                *) snell_ipv6="false" ;;
            esac
        fi
    else
        has_ipv4=0
        has_ipv6=0

        stack_mode="${SNELL_STACK}"
        if [ "${stack_mode}" = "auto" ] && [ "${snell_ipv6_forced}" = "1" ]; then
            if [ "${snell_ipv6}" = "true" ]; then
                stack_mode="ipv6"
            else
                stack_mode="ipv4"
            fi
        fi

        case "${stack_mode}" in
            ipv4|v4) has_ipv4=1 ;;
            ipv6|v6) has_ipv6=1 ;;
            dual|dualstack|both) has_ipv4=1; has_ipv6=1 ;;
            auto|*)
                detect_ipv4 && has_ipv4=1
                detect_ipv6 && has_ipv6=1
                ;;
        esac

        if [ "${has_ipv6}" -eq 1 ]; then
            snell_listen=":::${snell_port}"
            if [ -z "${snell_ipv6}" ]; then
                snell_ipv6="true"
            fi
            if [ "${has_ipv4}" -eq 1 ]; then
                snell_dual="1"
            fi
        else
            snell_listen="0.0.0.0:${snell_port}"
            if [ -z "${snell_ipv6}" ]; then
                snell_ipv6="false"
            fi
        fi
    fi

    if [ -z "${snell_ipv6}" ]; then
        snell_ipv6="false"
    fi

    if [ "${snell_dual}" = "1" ] && sysctl net.ipv6.bindv6only >/dev/null 2>&1; then
        bindv6only="$(sysctl -n net.ipv6.bindv6only 2>/dev/null || echo "")"
        if [ "${bindv6only}" = "1" ]; then
            echo -e "${YELLOW}检测到 net.ipv6.bindv6only=1，双栈可能仅监听 IPv6，可手动改为 0${PLAIN}"
        fi
    fi

    # 写入配置
    cat > ${CONF_FILE} <<EOF
[snell-server]
listen = ${snell_listen}
psk = ${PSK}
obfs = ${snell_obfs}
ipv6 = ${snell_ipv6}
EOF
fi

# 5. Systemd 服务文件配置
# 无论是否存在，都重新写入一次 Systemd 文件以确保路径正确
if [ "${HAS_SYSTEMD}" = "1" ]; then
    cat > ${SYSTEMD_FILE} <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
else
    echo -e "${YELLOW}未检测到 systemd，将跳过服务配置。${PLAIN}"
fi

# 6. 系统网络优化
optimize_system() {
    echo -e "${YELLOW}正在应用系统优化 (TCP & Limits)...${PLAIN}"
    
    # 1. 提高文件描述符限制
    if [ -d /etc/security/limits.d ]; then
        local limits_conf="/etc/security/limits.d/99-snell.conf"
        if [ ! -f "${limits_conf}" ]; then
            cat > "${limits_conf}" <<EOF
* soft nofile 65535
* hard nofile 65535
EOF
        fi
    else
        if ! grep -q "soft nofile" /etc/security/limits.conf; then
            echo "* soft nofile 65535" >> /etc/security/limits.conf
            echo "* hard nofile 65535" >> /etc/security/limits.conf
        fi
    fi
    
    # 2. Sysctl 调优
    cat > /etc/sysctl.d/99-snell-tune.conf <<EOF
fs.file-max = 1000000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
EOF
    sysctl -p /etc/sysctl.d/99-snell-tune.conf
    echo -e "${GREEN}系统优化完成！${PLAIN}"
}

if [ "$ENABLE_OPTIMIZE" = "1" ]; then
    optimize_system
elif [ -z "$ENABLE_OPTIMIZE" ]; then
    read -e -p "是否进行系统网络优化 (推荐)? [y/N]: " need_opt
    [[ "$need_opt" == "y" || "$need_opt" == "Y" ]] && optimize_system
fi

# 7. BBR 加速配置
enable_bbr() {
    local bbr_conf="/etc/sysctl.d/99-snell-bbr.conf"

    if sysctl net.ipv4.tcp_congestion_control | grep -qw bbr; then
        echo -e "${GREEN}BBR 已开启。${PLAIN}"
        return
    fi

    if ! sysctl net.ipv4.tcp_available_congestion_control >/dev/null 2>&1; then
        echo -e "${RED}无法检测 BBR 支持，已跳过。${PLAIN}"
        return
    fi

    if ! sysctl net.ipv4.tcp_available_congestion_control | grep -qw bbr; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
    fi

    if ! sysctl net.ipv4.tcp_available_congestion_control | grep -qw bbr; then
        echo -e "${RED}当前内核不支持 BBR，已跳过。${PLAIN}"
        return
    fi

    echo -e "${YELLOW}正在开启 BBR...${PLAIN}"
    cat > "${bbr_conf}" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p "${bbr_conf}"
    echo -e "${GREEN}BBR 已成功开启！${PLAIN}"
}

if [ "$ENABLE_BBR" = "1" ]; then
    enable_bbr
elif [ -z "$ENABLE_BBR" ]; then
    read -e -p "是否开启 BBR 加速? [y/N]: " need_bbr
    [[ "$need_bbr" == "y" || "$need_bbr" == "Y" ]] && enable_bbr
fi

# 8. 启动服务
if [ "${HAS_SYSTEMD}" = "1" ]; then
    echo -e "${GREEN}正在启动服务...${PLAIN}"
    systemctl daemon-reload
    systemctl enable snell
    systemctl restart snell
else
    echo -e "${YELLOW}未检测到 systemd，请手动启动:${PLAIN} /usr/local/bin/snell-server -c /etc/snell/snell-server.conf"
fi

# 7. 输出最终信息
echo
echo "================================================"
if [ "${HAS_SYSTEMD}" = "1" ]; then
    if systemctl is-active --quiet snell; then
        echo -e "状态: ${GREEN}已运行${PLAIN} | 版本: ${SNELL_VER}"
    else
        echo -e "状态: ${RED}启动失败 (请检查 systemctl status snell)${PLAIN}"
    fi
else
    echo -e "状态: ${YELLOW}未使用 systemd${PLAIN} | 版本: ${SNELL_VER}"
fi
echo "================================================"
echo -e "${YELLOW}当前配置内容 /etc/snell/snell-server.conf :${PLAIN}"
echo "------------------------------------------------"
cat ${CONF_FILE}
echo "------------------------------------------------"
echo "如需在 Surge 中使用，请复制上方内容填写到配置文件。"
