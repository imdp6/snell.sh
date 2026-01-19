- 端口：12312 可自定义：[1-65535]
- Obfs：tls 可自定义：[tls/http/off]
- PSK：随机生成的16位字符
- 若已安装 Snell，直接输出配置

脚本运行完毕后，会显示 port 以及 psk，按照标准填入 Surge 即可。


** 请使用root用户运行 **

Debian & Ubuntu 用户安装更新
```
wget --no-check-certificate -O update_snell.sh https://raw.githubusercontent.com/imdp6/snell.sh/refs/heads/master/update_snell.sh
chmod +x update_snell.sh
./update_snell.sh
```

卸载方法：
```
wget --no-check-certificate -O uninstall-snell.sh https://raw.githubusercontent.com/imdp6/snell.sh/refs/heads/master/uninstall-snell.sh
chmod +x uninstall-snell.sh
./uninstall-snell.sh
```
运行状态
```
systemctl status snell
```
重启 Snell
```
systemctl restart snell
```
启动 Snell
```
systemctl start snell
```
停止 Snell
```
systemctl stop snell
```
----
查看 Snell 配置文件
```
cat /etc/snell/snell-server.conf
```
修改 Snell 配置文件
```
vi /etc/snell/snell-server.conf
```

Forked from：[ydzydzydz/snell.sh](https://github.com/ydzydzydz/snell.sh)
# snell.sh
