#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
CONF="/etc/snell/snell-server.conf"
SYSTEMD="/etc/systemd/system/snell.service"
apt install unzip -y
cd ~/
wget --no-check-certificate -O snell.zip https://dl.nssurge.com/snell/snell-server-v4.1.0-linux-amd64.zip
unzip -o snell.zip
rm -f snell.zip
chmod +x snell-server
mv -f snell-server /usr/local/bin/
if [ ! -f ${CONF} ]; then
    mkdir -p /etc/snell/
    if [ -z ${PSK} ]; then
        PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
        echo "Generated PSK: ${PSK}"
    else
        echo "Using predefined PSK: ${PSK}"
    fi
    echo "Generating new config..."
    echo "[snell-server]" > ${CONF}
    echo "listen = :::1024" >> ${CONF}
    echo "ipv6 = true" >> ${CONF}
    echo "psk = ${PSK}" >> ${CONF}
    echo "obfs = http" >> ${CONF}
else
    echo "Found existing config..."
fi
if [ ! -f ${SYSTEMD} ]; then
    echo "Generating new service..."
    echo "[Unit]" > ${SYSTEMD}
    echo "Description=Snell Proxy Service" >> ${SYSTEMD}
    echo "After=network.target" >> ${SYSTEMD}
    echo "[Service]" >> ${SYSTEMD}
    echo "Type=simple" >> ${SYSTEMD}
    echo "LimitNOFILE=32768" >> ${SYSTEMD}
    echo "ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf" >> ${SYSTEMD}
    echo "[Install]" >> ${SYSTEMD}
    echo "WantedBy=multi-user.target" >> ${SYSTEMD}
    systemctl daemon-reload
    systemctl enable snell
    systemctl start snell
else
    echo "Found existing service..."
    systemctl daemon-reload
    systemctl restart snell
fi
