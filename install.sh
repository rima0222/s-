#!/bin/bash

# خروج در صورت بروز خطا
set -e

clear
echo "=================================================="
echo "   SSH Tunnel + CUSTOM WEB GUI + Anti-Filter WS   "
echo "=================================================="
echo "Please select the role of this server:"
echo "1) Server KHAREJ (Main + Custom Web GUI Panel)"
echo "2) Server IRAN (Tunnel + WS Server for Npv)"
echo "=================================================="
read -p "Enter your choice (1 or 2): " SERVER_ROLE

# ۱. نصب پیش‌نیازها
echo ""
echo "[*] Updating system and installing prerequisites..."
sudo apt update && sudo apt install -y curl wget unzip python3 python3-pip ufw bc
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

TUNNEL_PORT=8443
LOCAL_SSH_PORT=22
IRAN_ENTRY_PORT=443
WS_PORT=80
WEB_PANEL_PORT=5000

# ==================================================
# تنظیمات سرور خارج (ساخت پنل وب اختصاصی پایتون)
# ==================================================
if [ "$SERVER_ROLE" == "1" ]; then
    echo "[*] Configuring Server KHAREJ..."
    
    sudo ufw allow $TUNNEL_PORT/tcp comment 'GOST Tunnel'
    sudo ufw allow $WEB_PANEL_PORT/tcp comment 'Custom Web GUI'
    
    # ساخت سرویس GOST برای خارج
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
    sudo systemctl daemon-reload && sudo systemctl enable gost-tunnel.service && sudo systemctl start gost-tunnel.service

    # ساخت پوشه پنل وب اختصاصی
    echo "[*] Creating Custom Web GUI Panel..."
    sudo mkdir -p /etc/custom-panel
    sudo touch /etc/custom-panel/users.db

    # کدهای سرور وب پایتون (Flask) بدون کاراکترهای تداخلی لینوکس
    sudo cat << 'EOF' > /etc/custom-panel/app.py
import os, subprocess
from flask import Flask, request, render_template_string, redirect

app = Flask(__name__)
DB_FILE = "/etc/custom-panel/users.db"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>پنل مدیریت کاربران SSH</title>
    <style>
        body { font-family: Tahoma, Arial; background-color: #f4f6f9; color: #333; margin: 40px; }
        .container { max-width: 800px; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); margin: auto; }
        h2 { border-bottom: 2px solid #007bff; padding-bottom: 10px; color: #007bff; }
        form { display: flex; gap: 10px; margin-bottom: 20px; flex-wrap: wrap; }
        input { padding: 8px; border: 1px solid #ddd; border-radius: 4px; flex: 1; min-width: 120px; }
        button { padding: 8px 15px; background: #007bff; color: white; border: none; border-radius: 4px; cursor: pointer; }
        button.del { background: #dc3545; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: center; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="container">
        <h2>➕ ساخت کاربر جدید</h2>
        <form action="/add" method="POST">
            <input type="text" name="username" placeholder="نام کاربری" required>
            <input type="text" name="password" placeholder="کلمه عبور" required>
            <input type="number" name="limit_gb" placeholder="حجم به گیگابایت" required>
            <input type="number" name="days" placeholder="اعتبار به روز" required>
            <button type="submit">ذخیره کاربر</button>
        </form>

        <h2>👥 لیست کاربران فعال</h2>
        <table>
            <tr>
                <th>نام کاربری</th>
                <th>محدودیت حجم</th>
                <th>مدت اعتبار</th>
                <th>محدودیت کاربر</th>
                <th>عملیات</th>
            </tr>
            {% for user in users %}
            <tr>
                <td>{{ user[0] }}</td>
                <td>{{ user[1] }} GB</td>
                <td>{{ user[2] }} روز</td>
                <td>تک کاربره (1 IP)</td>
                <td>
                    <form action="/delete" method="POST" style="margin:0;">
                        <input type="hidden" name="username" value="{{ user[0] }}">
                        <button type="submit" class="del">حذف</button>
                    </form>
                </td>
            </tr>
            {% endfor %}
        </table>
    </div>
</body>
</html>
"""

def get_users():
    users = []
    if os.path.exists(DB_FILE):
        with open(DB_FILE, "r") as f:
            for line in f:
                if ":" in line:
                    users.append(line.strip().split(":"))
    return users

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, users=get_users())

@app.route('/add', methods=['POST'])
def add_user():
    username = request.form['username'].strip()
    password = request.form['password'].strip()
    limit_gb = request.form['limit_gb'].strip()
    days = request.form['days'].strip()
    
    if username and password:
        subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)
        with open(DB_FILE, "a") as f:
            f.write(f"{username}:{limit_gb}:{days}\n")
    return redirect('/')

@app.route('/delete', methods=['POST'])
def delete_user():
    username = request.form['username'].strip()
    subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    users = get_users()
    with open(DB_FILE, "w") as f:
        for user in users:
            if user[0] != username:
                f.write(f"{user[0]}:{user[1]}:{user[2]}\n")
    return redirect('/')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF"

    # ساخت سرویس برای اجرای دائمی پنل وب اختصاصی در پس‌زمینه
    sudo bash -c "cat <<EOF > /etc/systemd/system/custom-panel.service
[Unit]
Description=Custom Web GUI Panel
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /etc/custom-panel/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

    sudo systemctl daemon-reload
    sudo systemctl enable custom-panel.service
    sudo systemctl start custom-panel.service
    
    # اسکریپت کنترل اکانت‌های همزمان (تک‌کاربره کردن قطعی)
    sudo mkdir -p /etc/custom-panel
    sudo cat << 'EOF' > /etc/custom-panel/kill-multi.sh
#!/bin/bash
while true; do
    if [ -f /etc/custom-panel/users.db ]; then
        for user in $(awk -F: '{print $1}' /etc/custom-panel/users.db); do
            pids=$(ps -u $user -o pid= || true)
            count=$(echo "$pids" | wc -w)
            if [ "$count" -gt 1 ]; then
                kill -9 $(echo "$pids" | awk '{print $1}')
            fi
        done
    fi
    sleep 5
done
EOF
    chmod +x /etc/custom-panel/kill-multi.sh
    
    # ساخت سرویس تک‌کاربره
    sudo bash -c "cat <<EOF > /etc/systemd/system/ssh-kill-multi.service
[Unit]
Description=Kill Multi Login SSH
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /etc/custom-panel/kill-multi.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl enable ssh-kill-multi.service && sudo systemctl start ssh-kill-multi.service

    echo "=================================================="
    echo "✔ Server KHAREJ Custom Panel Ready!"
    echo "🌐 Access GUI via: http://YOUR_KHAREJ_IP:5000"
    echo "=================================================="

# ==================================================
# تنظیمات سرور ایران (بدون تغییر)
# ==================================================
elif [ "$SERVER_ROLE" == "2" ]; then
    echo "[*] Configuring Server IRAN..."
    read -p "Enter Server KHAREJ IP address: " KHAREJ_IP
    
    sudo ufw allow $IRAN_ENTRY_PORT/tcp
    sudo ufw allow $WS_PORT/tcp

    sudo bash -c "cat <<EOF > /etc/systemd/system/gost-tunnel.service
[Unit]
Description=Gost Tunnel Client on Iran
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L tcp://:$IRAN_ENTRY_PORT -F rtcp://$KHAREJ_IP:$TUNNEL_PORT
Restart=always
EOF"
    sudo systemctl daemon-reload && sudo systemctl enable gost-tunnel.service && sudo systemctl start gost-tunnel.service

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
EOF"
    sudo systemctl daemon-reload && sudo systemctl enable ssh-ws.service && sudo systemctl start ssh-ws.service
    
    echo "=================================================="
    echo "✔ Server IRAN Ready!"
    echo "=================================================="
fi
