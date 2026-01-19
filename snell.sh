#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
CONF="/etc/snell/snell-server.conf"
SYSTEMD="/etc/systemd/system/snell.service"
if command -v apt-get >/dev/null 2>&1; then
  apt-get update && apt-get install -y unzip wget
elif command -v apt >/dev/null 2>&1; then
  apt update && apt install -y unzip wget
elif command -v yum >/dev/null 2>&1; then
  yum install -y unzip wget
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y unzip wget
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache unzip wget
else
  echo "No supported package manager found. Install unzip and wget manually."
  exit 1
fi
if ! command -v unzip >/dev/null 2>&1 || ! command -v wget >/dev/null 2>&1; then
  echo "Failed to install unzip and wget. Install them manually and re-run."
  exit 1
fi
cd ~/
wget --no-check-certificate -O snell.zip https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-amd64.zip
unzip -o snell.zip
rm -f snell.zip
chmod +x snell-server
mv -f snell-server /usr/local/bin/
if [ -f ${CONF} ]; then
  echo "Found existing config..."
  else
  if [ -z ${PSK} ]; then
    PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo "Using generated PSK: ${PSK}"
  else
    echo "Using predefined PSK: ${PSK}"
  fi
  mkdir /etc/snell/
  echo "Generating new config..."
  echo "[snell-server]" >>${CONF}
  echo "listen = 0.0.0.0:1024" >>${CONF}
  echo "psk = ${PSK}" >>${CONF}
  echo "obfs = http" >>${CONF}
fi
if [ -f ${SYSTEMD} ]; then
  echo "Found existing service..."
  systemctl daemon-reload
  systemctl restart snell
else
  echo "Generating new service..."
  echo "[Unit]" >>${SYSTEMD}
  echo "Description=Snell Proxy Service" >>${SYSTEMD}
  echo "After=network.target" >>${SYSTEMD}
  echo "" >>${SYSTEMD}
  echo "[Service]" >>${SYSTEMD}
  echo "Type=simple" >>${SYSTEMD}
  echo "LimitNOFILE=32768" >>${SYSTEMD}
  echo "ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf" >>${SYSTEMD}
  echo "" >>${SYSTEMD}
  echo "[Install]" >>${SYSTEMD}
  echo "WantedBy=multi-user.target" >>${SYSTEMD}
  systemctl daemon-reload
  systemctl enable snell
  systemctl start snell
fi
