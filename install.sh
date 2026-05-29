#!/bin/bash

set -e
clear
echo "=================================================="
echo "    SSH Tunnel + WEB GUI (SECURE WSTUNNEL MODE)   "
echo "=================================================="
echo "Please select the role of this server:"
echo "1) Server KHAREJ (Main Panel + Secure Receiver)"
echo "2) Server IRAN (Front Shield - Port 80)"
echo "=================================================="
read -p "Enter your choice (1 or 2): " SERVER_ROLE

WEB_PANEL_PORT=5000
WSTUNNEL_PORT=8989

# دانلود wstunnel در صورت عدم وجود
if [ ! -f /usr/local/bin/wstunnel ]; then
    echo "[*] Installing Secure WSTunnel Tool..."
    wget https://github.com/erebe/wstunnel/releases/download/v9.7.0/wstunnel-9.7.0-linux-amd64 -O /usr/local/bin/wstunnel
    chmod +x /usr/local/bin/wstunnel
fi

# ==================================================
# تنظیمات سرور خارج (پنهان و امن)
# ==================================================
if [ "$SERVER_ROLE" == "1" ]; then
    echo "[*] Configuring Server KHAREJ..."
    sudo apt update && sudo apt install -y python3 python3-pip python3-flask ufw
    
    sudo ufw allow $WSTUNNEL_PORT/tcp comment 'Secure Tunnel'
    sudo ufw allow $WEB_PANEL_PORT/tcp comment 'Web GUI'
    sudo ufw reload
    
    # ساخت سرویس گیرنده تونل امن وب‌ساکت
    sudo tee /etc/systemd/system/wstunnel-srv.service > /dev/null <<EOF
[Unit]
Description=WSTunnel Server Mode
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel server wss://0.0.0.0:$WSTUNNEL_PORT --restrictTo=127.0.0.1:22
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload && sudo systemctl enable wstunnel-srv.service && sudo systemctl start wstunnel-srv.service

    # ایجاد پنل وب گرافیکی
    sudo mkdir -p /etc/custom-panel
    sudo touch /etc/custom-panel/users.db
    sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess
from flask import Flask, request, render_template_string, redirect

app = Flask(__name__)
DB_FILE = "/etc/custom-panel/users.db"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8"><title>پنل مدیریت کاربران SSH</title>
    <style>
        body { font-family: Tahoma; background-color: #f4f6f9; margin: 40px; }
        .container { max-width: 800px; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); margin: auto; }
        h2 { border-bottom: 2px solid #007bff; padding-bottom: 10px; color: #007bff; }
        form { display: flex; gap: 10px; margin-bottom: 20px; }
        input { padding: 8px; border: 1px solid #ddd; border-radius: 4px; flex: 1; }
        button { padding: 8px 15px; background: #007bff; color: white; border: none; border-radius: 4px; cursor: pointer; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h2>➕ ساخت کاربر جدید</h2>
        <form action="/add" method="POST">
            <input type="text" name="username" placeholder="نام کاربری" required>
            <input type="text" name="password" placeholder="کلمه عبور" required>
            <button type="submit">ذخیره کاربر</button>
        </form>
        <h2>👥 لیست کاربران</h2>
        <table>
            <tr><th>نام کاربری</th><th>عملیات</th></tr>
            {% for user in users %}
            <tr>
                <td>{{ user[0] }}</td>
                <td>
                    <form action="/delete" method="POST" style="margin:0;">
                        <input type="hidden" name="username" value="{{ user[0] }}">
                        <button type="submit" style="background:#dc3545;">حذف</button>
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
                if ":" in line: users.append(line.strip().split(":"))
    return users

@app.route('/')
def index(): return render_template_string(HTML_TEMPLATE, users=get_users())

@app.route('/add', methods=['POST'])
def add_user():
    username = request.form['username'].strip()
    password = request.form['password'].strip()
    if username and password:
        subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)
        with open(DB_FILE, "a") as f: f.write(f"{username}:{password}\n")
    return redirect('/')

@app.route('/delete', methods=['POST'])
def delete_user():
    username = request.form['username'].strip()
    subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    users = get_users()
    with open(DB_FILE, "w") as f:
        for u in users:
            if u[0] != username: f.write(f"{u[0]}:{u[1]}\n")
    return redirect('/')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    sudo tee /etc/systemd/system/custom-panel.service > /dev/null <<EOF
[Unit]
Description=Custom Web GUI Panel
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /etc/custom-panel/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload && sudo systemctl enable custom-panel.service && sudo systemctl start custom-panel.service
    echo "✔ Server KHAREJ Protected & Ready!"

# ==================================================
# تنظیمات سرور ایران (سپر امنیتی)
# ==================================================
elif [ "$SERVER_ROLE" == "2" ]; then
    echo "[*] Configuring Server IRAN..."
    read -p "Enter Server KHAREJ IP address: " KHAREJ_IP
    
    sudo iptables -t nat -F 2>/dev/null || true
    sudo ufw allow 80/tcp
    sudo ufw reload

    # ساخت سرویس فوروارد وب‌ساکت امن به خارج
    sudo tee /etc/systemd/system/wstunnel-cli.service > /dev/null <<EOF
[Unit]
Description=WSTunnel Client Mode (Iran Shield)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel client --listen tcp://0.0.0.0:80 wss://$KHAREJ_IP:$WSTUNNEL_PORT --insecure
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload && sudo systemctl enable wstunnel-cli.service && sudo systemctl restart wstunnel-cli.service
    echo "✔ Server IRAN Shield Activated!"
fi
