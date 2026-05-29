#!/bin/bash

# خروج در صورت بروز خطا
set -e

clear
echo "=================================================="
echo "    SSH Tunnel + WEB GUI (PURE IPTABLES MODE)     "
echo "=================================================="
echo "Please select the role of this server:"
echo "1) Server KHAREJ (Main + Custom Web GUI Panel)"
echo "2) Server IRAN (Pure IPtables Port Forward)"
echo "=================================================="
read -p "Enter your choice (1 or 2): " SERVER_ROLE

WEB_PANEL_PORT=5000

# ==================================================
# تنظیمات سرور خارج (پنل وب گرافیکی)
# ==================================================
if [ "$SERVER_ROLE" == "1" ]; then
    echo "[*] Updating system and installing Flask..."
    sudo apt update && sudo apt install -y python3 python3-pip python3-flask ufw
    
    sudo ufw allow $WEB_PANEL_PORT/tcp comment 'Custom Web GUI'
    sudo ufw allow 22/tcp comment 'SSH Port'
    sudo ufw reload
    
    echo "[*] Creating Custom Web GUI Panel..."
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
                <th>عملیات</th>
            </tr>
            {% for user in users %}
            <tr>
                <td>{{ user[0] }}</td>
                <td>{{ user[1] }} GB</td>
                <td>{{ user[2] }} روز</td>
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
    
    echo "=================================================="
    echo "✔ Server KHAREJ Custom Panel Ready!"
    echo "🌐 http://YOUR_KHAREJ_IP:5000"
    echo "=================================================="

# ==================================================
# تنظیمات سرور ایران (فوروارد مستقیم با IPtables)
# ==================================================
elif [ "$SERVER_ROLE" == "2" ]; then
    echo "[*] Configuring Server IRAN (Pure IPtables)..."
    read -p "Enter Server KHAREJ IP address: " KHAREJ_IP
    
    # حذف گوست و سرویس‌های قبلی برای سبک‌سازی کامل سرور ایران
    sudo systemctl stop gost-tunnel.service 2>/dev/null || true
    sudo systemctl disable gost-tunnel.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/gost-tunnel.service
    
    # فعال کردن فوروارد پکت‌ها در هسته لینوکس سرور ایران
    sudo sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
    
    # پاک کردن رول‌های قدیمی احتمالاً تداخلی
    sudo iptables -t nat -F
    
    # دستور جادویی آینه‌ای کردن پورت ۸۰ ایران به پورت ۲۲ خارج
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $KHAREJ_IP:22
    sudo iptables -t nat -A POSTROUTING -p tcp -d $KHAREJ_IP --dport 22 -j MASQUERADE
    
    # نصب ابزار ذخیره دائمی رول‌های آی‌پی‌تیبلز تا با ریستارت سرور پاک نشوند
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
    sudo apt install -y iptables-persistent

    echo "=================================================="
    echo "✔ Server IRAN Port Forwarding via IPtables Ready!"
    echo "=================================================="
fi
