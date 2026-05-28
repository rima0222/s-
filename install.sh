#!/bin/bash

# خروج در صورت بروز خطا
set -e

clear
echo "=================================================="
echo "   SSH Tunnel + WEB GUI PANEL + Anti-Filter WS    "
echo "=================================================="
echo "Please select the role of this server:"
echo "1) Server KHAREJ (Main + Web GUI Panel Setup)"
echo "2) Server IRAN (Tunnel + WS Server for Npv)"
echo "=================================================="
read -p "Enter your choice (1 or 2): " SERVER_ROLE

# ۱. نصب پیش‌نیازها
echo ""
echo "[*] Updating system and installing basic prerequisites..."
sudo apt update && sudo apt install -y curl wget unzip python3 ufw bc
echo "[*] Waiting 3 seconds for packages to fully settle..."
sleep 3

# ۲. دانلود و نصب ابزار GOST
if [ ! -f /usr/local/bin/gost ]; then
    echo "[*] Installing GOST Tunneling Tool..."
    wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
    gunzip gost-linux-amd64-2.11.5.gz
    chmod +x gost-linux-amd64-2.11.5
    sudo mv gost-linux-amd64-2.11.5 /usr/local/bin/gost
    sleep 3
fi

# تعریف پورت‌های ثابت سیستم
TUNNEL_PORT=8443
LOCAL_SSH_PORT=22
IRAN_ENTRY_PORT=443
WS_PORT=80

# ==================================================
# تنظیمات سرور خارج (نصب پنل گرافیکی تحت وب)
# ==================================================
if [ "$SERVER_ROLE" == "1" ]; then
    echo "[*] Configuring Server KHAREJ..."
    
    # باز کردن پورت فایروال برای تونل
    sudo ufw allow $TUNNEL_PORT/tcp comment 'GOST Tunnel'
    
    # ساخت سرویس پس‌زمینه برای GOST
    sudo bash -c "cat <<EOF > /etc/systemd/system/gost-tunnel.service
[Unit]
Description=Gost Tunnel Server on Kharej
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L rtcp://:$TUNNEL_PORT/127.0.0.1:$LOCAL_SSH_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"

    sudo systemctl daemon-reload
    sudo systemctl enable gost-tunnel.service
    sudo systemctl start gost-tunnel.service
    
    # نصب پنل گرافیکی تحت وب X-UI (نسخه انگلیسی/فارسی Sanaei)
    echo ""
    echo "[*] Installing Web GUI Panel (X-UI)..."
    echo "--------------------------------------------------"
    # اجرای اسکریپت رسمی نصب پنل گرافیکی
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    
    echo "=================================================="
    echo "✔ Server KHAREJ configuration completed!"
    echo "🌐 You can now access your Web Panel via Kharej_IP:Panel_Port"
    echo "👉 Now run this script on Server IRAN."
    echo "=================================================="

# ==================================================
# تنظیمات سرور ایران (بدون تغییر)
# ==================================================
elif [ "$SERVER_ROLE" == "2" ]; then
    echo "[*] Configuring Server IRAN..."
    read -p "Enter Server KHAREJ IP address: " KHAREJ_IP
    
    sudo ufw allow $IRAN_ENTRY_PORT/tcp comment 'Gost Main Port'
    sudo ufw allow $WS_PORT/tcp comment 'Npv WebSocket Port'

    sudo bash -c "cat <<EOF > /etc/systemd/system/gost-tunnel.service
[Unit]
Description=Gost Tunnel Client on Iran
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L tcp://:$IRAN_ENTRY_PORT -F rtcp://$KHAREJ_IP:$TUNNEL_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl daemon-reload
    sudo systemctl enable gost-tunnel.service
    sudo systemctl start gost-tunnel.service

    echo "[*] Creating WebSocket Python Proxy..."
    sudo mkdir -p /etc/ssh-ws
    sudo bash -c "cat <<EOF > /etc/ssh-ws/ws-proxy.py
import socket, threading
def handle_client(client_socket):
    try:
        request = client_socket.recv(1024).decode('utf-8', errors='ignore')
        if \"Upgrade: websocket\" in request or \"HTTP/1.1\" in request:
            client_socket.sendall(b\"HTTP/1.1 101 Switching Protocols\\\r\\\nUpgrade: websocket\\\r\\\nConnection: Upgrade\\\r\\\n\\\r\\\n\")
            server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server_socket.connect(('127.0.0.1', $IRAN_ENTRY_PORT))
            def forward(src, dst):
                try:
                    while True:
                        data = src.recv(4096)
                        if not data: break
                        dst.sendall(data)
                except: pass
                finally: src.close(); dst.close()
            threading.Thread(target=forward, args=(client_socket, server_socket)).start()
            threading.Thread(target=forward, args=(server_socket, client_socket)).start()
        else:
            client_socket.close()
    except: client_socket.close()
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('0.0.0.0', $WS_PORT))
server.listen(100)
while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client,)).start()
EOF"

    sudo bash -c "cat <<EOF > /etc/systemd/system/ssh-ws.service
[Unit]
Description=SSH WebSocket Proxy for Npv
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /etc/ssh-ws/ws-proxy.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"
    
    sudo systemctl daemon-reload
    sudo systemctl enable ssh-ws.service
    sudo systemctl start ssh-ws.service
    
    echo "=================================================="
    echo "✔ Server IRAN configuration completed!"
    echo "🚀 Npv Config Port: $WS_PORT"
    echo "=================================================="
else
    echo "❌ Invalid choice!"
    exit 1
fi
