#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行该脚本。${PLAIN}"
    exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl stop snell >/dev/null 2>&1 || true
    systemctl disable snell >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/snell.service /lib/systemd/system/snell.service
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed snell >/dev/null 2>&1 || true
fi

rm -f /usr/local/bin/snell-server /usr/bin/snell-server /usr/sbin/snell-server
rm -f /etc/snell/snell-server.conf
rmdir /etc/snell 2>/dev/null || true

if [ "${REMOVE_TUNE}" = "1" ]; then
    rm -f /etc/sysctl.d/99-snell-tune.conf /etc/sysctl.d/99-snell-bbr.conf
    rm -f /etc/security/limits.d/99-snell.conf
    echo -e "${YELLOW}已删除 sysctl/limits 调优文件，需手动恢复或重启生效。${PLAIN}"
fi

echo -e "Snell ${GREEN}卸载完成${PLAIN}"
