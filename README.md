# snell.sh

Snell Server v5 / v6 beta 一键安装/更新脚本。

- 默认端口 12312，可自定义 [1-65535]
- 默认 obfs 为 tls，可选 [tls/http/off]
- PSK 默认随机生成 32 位字符
- 已有配置文件会保留不覆盖
- Snell v6 配置支持多监听地址、`dns-ip-preference` 和 `mode`

脚本运行完毕后会显示当前配置，直接复制到 Surge 使用。

注意：请使用 root 权限运行。

## 快速开始 (Debian/Ubuntu)
```
wget --no-check-certificate -O update_snell.sh https://raw.githubusercontent.com/imdp6/snell.sh/main/update_snell.sh
chmod +x update_snell.sh
./update_snell.sh
```

## 可选环境变量 (update_snell.sh)
基础参数：
- `SNELL_VER`：版本号，默认 `v5.0.1`
- `SNELL_URL`：自定义下载地址
- `SNELL_BIN`：本地二进制路径
- `SNELL_ZIP`：本地 ZIP 路径
- `SNELL_CONF_VERSION`：生成配置语法，`auto` / `5` / `6`，默认 `auto`
- `SNELL_FORCE_IPV6=1`：使用 IPv6 下载
- `SNELL_SHA256`：指定文件 SHA256 校验值（用于 ZIP 或二进制）
- `SNELL_SHA256_URL`：指定校验文件地址（自动解析 64 位哈希）

配置参数（仅在首次生成配置时生效）：
- `SNELL_PORT`：监听端口
- `SNELL_OBFS`：`tls` / `http` / `off`
- `SNELL_PSK`：指定 PSK（不填则随机生成）
- `SNELL_IPV6`：`true/false` 强制 IPv6 模式
- `SNELL_DNS_IP_PREFERENCE`：Snell v6 DNS IP 偏好，`default` / `prefer-ipv4` / `prefer-ipv6` / `ipv4-only` / `ipv6-only`
- `SNELL_MODE`：Snell v6 模式，`default` / `unshaped` / `unsafe-raw`，默认 `default`
- `SNELL_STACK`：`auto` / `ipv4` / `ipv6` / `dual`
- `SNELL_LISTEN`：手动指定监听地址，如 `0.0.0.0:12312`、`[::]:12312` 或 `0.0.0.0:12312,[::]:12312`
- `SNELL_REINIT=1`：强制重建配置（会先备份）
- `SNELL_BACKUP=1`：仅备份现有配置

性能相关：
- `ENABLE_OPTIMIZE=1`：应用 TCP/sysctl 优化
- `ENABLE_BBR=1`：启用 BBR

非交互：
- `SNELL_NONINTERACTIVE=1`：禁用交互，使用默认值
- `ASSUME_YES=1`：默认启用优化/BBR（等同 `--yes`）

## 命令行参数 (update_snell.sh)
- `-y, --yes`：非交互并默认开启优化/BBR
- `--non-interactive`：非交互（默认关闭）
- `--optimize / --no-optimize`：开启/关闭系统优化
- `--bbr / --no-bbr`：开启/关闭 BBR
- `--reinit`：重建配置（会自动备份）
- `--backup`：仅备份配置
- `--config-version <5|6>`：指定生成配置语法
- `--dns-ip-preference <mode>`：设置 Snell v6 DNS IP 偏好
- `--mode <mode>`：设置 Snell v6 模式
- `--stack <mode>`：`auto` / `ipv4` / `ipv6` / `dual`
- `--listen <addr>`：指定监听地址

## Snell v6 beta 说明
- 官方 Snell v6 仍处于 beta，beta 期间可能出现不兼容协议变更，客户端和服务端需保持同步更新。
- Snell 6.0 beta 2 调整了协议画像，Surge Mac 也需要更新到最新版本。
- Snell 6.0 beta 3 新增 `mode` 设置，服务端和客户端的 `mode` 必须一致。
- 脚本会在检测到 `SNELL_VER=v6...`、v6 下载 URL/ZIP/BIN，或显式设置 `SNELL_CONF_VERSION=6` 时生成 v6 配置。
- Snell v6 的协议画像由 PSK 自动派生；建议不同服务器使用不同 PSK，不要复用。
- v6 双栈监听会生成 `listen = 0.0.0.0:PORT,[::]:PORT`，避免依赖 IPv6 socket 兼容行为。
- `mode=default`：默认模式，启用流量混淆和 AES 加密。
- `mode=unshaped`：关闭混淆，仅使用 AES 加密，吞吐性能更高，但加密流量表现为完全随机。
- `mode=unsafe-raw`：关闭加密和混淆，明文转发流量，只应在内网或其他安全隧道中使用。
- 若官方 beta 下载文件名变化，可用 `SNELL_URL`、`SNELL_ZIP` 或 `SNELL_BIN` 指定安装源。

## IPv4 / IPv6 / 双栈说明
- 默认 `SNELL_STACK=auto`：自动检测系统是否有全局 IPv4/IPv6 地址。
- Snell v6 双栈建议使用 `SNELL_STACK=dual` 或 `SNELL_LISTEN="0.0.0.0:PORT,[::]:PORT"`。
- Snell v5 双栈会继续使用旧的 IPv6 兼容监听；若 `net.ipv6.bindv6only=1`，可能只会监听 IPv6，需手动改为 0。
- 已存在 `/etc/snell/snell-server.conf` 时不会自动重写配置。
- 未检测到 systemd 时将跳过服务配置，需手动运行 `snell-server -c /etc/snell/snell-server.conf`。

## 示例
```
SNELL_PORT=443 SNELL_OBFS=off ./update_snell.sh
SNELL_PSK=YourPSKHere SNELL_STACK=dual ./update_snell.sh
SNELL_LISTEN="0.0.0.0:443,[::]:443" SNELL_CONF_VERSION=6 ./update_snell.sh
SNELL_CONF_VERSION=6 SNELL_DNS_IP_PREFERENCE=prefer-ipv6 SNELL_REINIT=1 ./update_snell.sh
SNELL_CONF_VERSION=6 SNELL_MODE=unshaped SNELL_REINIT=1 ./update_snell.sh
SNELL_SHA256=yourhashhere ./update_snell.sh
SNELL_SHA256_URL=https://example.com/snell.sha256 ./update_snell.sh
ENABLE_OPTIMIZE=1 ENABLE_BBR=1 ./update_snell.sh
SNELL_REINIT=1 ./update_snell.sh
./update_snell.sh --yes --no-bbr
```

## 卸载
```
wget --no-check-certificate -O uninstall-snell.sh https://raw.githubusercontent.com/imdp6/snell.sh/main/uninstall-snell.sh
chmod +x uninstall-snell.sh
./uninstall-snell.sh
```
如需同时移除 sysctl/limits 调优文件：
```
REMOVE_TUNE=1 ./uninstall-snell.sh
```

## 常用命令
说明：以下命令适用于 systemd 环境。
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
