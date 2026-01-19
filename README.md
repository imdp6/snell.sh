# snell.sh

Snell Server v5 一键安装/更新脚本。

- 默认端口 12312，可自定义 [1-65535]
- 默认 obfs 为 tls，可选 [tls/http/off]
- PSK 默认随机生成 16 位字符
- 已有配置文件会保留不覆盖

脚本运行完毕后会显示当前配置，直接复制到 Surge 使用。

注意：请使用 root 权限运行。

## 快速开始 (Debian/Ubuntu)
```
wget --no-check-certificate -O update_snell.sh https://raw.githubusercontent.com/imdp6/snell.sh/refs/heads/master/update_snell.sh
chmod +x update_snell.sh
./update_snell.sh
```

## 可选环境变量 (update_snell.sh)
基础参数：
- `SNELL_VER`：版本号，默认 `v5.0.1`
- `SNELL_URL`：自定义下载地址
- `SNELL_BIN`：本地二进制路径
- `SNELL_ZIP`：本地 ZIP 路径
- `SNELL_FORCE_IPV6=1`：使用 IPv6 下载

配置参数（仅在首次生成配置时生效）：
- `SNELL_PORT`：监听端口
- `SNELL_OBFS`：`tls` / `http` / `off`
- `SNELL_PSK`：指定 PSK（不填则随机生成）
- `SNELL_IPV6`：`true/false` 强制 IPv6 模式
- `SNELL_STACK`：`auto` / `ipv4` / `ipv6` / `dual`
- `SNELL_LISTEN`：手动指定监听地址，如 `0.0.0.0:12312` 或 `:::12312`

性能相关：
- `ENABLE_OPTIMIZE=1`：应用 TCP/sysctl 优化
- `ENABLE_BBR=1`：启用 BBR

## IPv4 / IPv6 / 双栈说明
- 默认 `SNELL_STACK=auto`：自动检测系统是否有全局 IPv4/IPv6 地址。
- 双栈建议使用 `SNELL_STACK=dual` 或 `SNELL_LISTEN=":::PORT"`。
- 若 `net.ipv6.bindv6only=1`，双栈可能只会监听 IPv6，需手动改为 0。
- 已存在 `/etc/snell/snell-server.conf` 时不会自动重写配置。

## 示例
```
SNELL_PORT=443 SNELL_OBFS=off ./update_snell.sh
SNELL_PSK=YourPSKHere SNELL_STACK=dual ./update_snell.sh
SNELL_LISTEN=":::443" SNELL_IPV6=true ./update_snell.sh
ENABLE_OPTIMIZE=1 ENABLE_BBR=1 ./update_snell.sh
```

## 卸载
```
wget --no-check-certificate -O uninstall-snell.sh https://raw.githubusercontent.com/imdp6/snell.sh/refs/heads/master/uninstall-snell.sh
chmod +x uninstall-snell.sh
./uninstall-snell.sh
```

## 常用命令
运行状态：
```
systemctl status snell
```
启动：
```
systemctl start snell
```
停止：
```
systemctl stop snell
```
重启：
```
systemctl restart snell
```
查看配置：
```
cat /etc/snell/snell-server.conf
```
修改配置：
```
vi /etc/snell/snell-server.conf
```