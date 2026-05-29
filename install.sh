#!/bin/bash

# خروج در صورت بروز خطا
set -e

clear
echo "=================================================="
echo "    SSH PRO PANEL (WEB-BASED BACKUP & RESTORE)    "
echo "=================================================="
echo "Please select an option:"
echo "1) Fresh Install (نصب اولیه یا راه اندازی مجدد)"
echo "2) Command-Line Restore (در صورتی که فایل دیتابیس را دارید)"
echo "=================================================="
read -p "Enter your choice (1 or 2): " MAIN_CHOICE

DB_FILE="/etc/custom-panel/panel.db"
WEB_PANEL_PORT=5000

install_prerequisites() {
    echo "[*] Installing system requirements..."
    sudo apt update
    sudo apt install -y python3 python3-pip python3-flask ufw sqlite3 bc
    
    # تنظیم فایروال
    sudo ufw allow $WEB_PANEL_PORT/tcp comment 'Web Panel'
    sudo ufw allow 443/tcp comment 'SSH Port'
    sudo ufw allow 22/tcp comment 'SSH MGMT'
    sudo ufw --force enable
    
    # هماهنگ‌سازی پورت ۴۴۳ روی SSH سرور
    if ! grep -q "Port 443" /etc/ssh/sshd_config; then
        echo "Port 443" | sudo tee -a /etc/ssh/sshd_config > /dev/null
        sudo systemctl restart sshd
    fi
    
    sudo mkdir -p /etc/custom-panel
}

create_panel_app() {
    echo "[*] Creating Core Python Web GUI with Backup/Restore..."
    sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, datetime, sqlite3, json
from flask import Flask, request, render_template_string, redirect, send_file, flash

app = Flask(__name__)
app.secret_key = "ssh_pro_secret_key_secure"
DB_FILE = "/etc/custom-panel/panel.db"

def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            username TEXT PRIMARY KEY,
            password TEXT,
            limit_gb REAL,
            used_gb REAL DEFAULT 0.0,
            expire_date TEXT,
            status TEXT DEFAULT 'Active'
        )
    ''')
    conn.commit()
    conn.close()

def get_online_users():
    try:
        output = subprocess.check_output("w -h | awk '{print $1}'", shell=True).decode()
        return list(set(output.strip().split('\n')))
    except:
        return []

def update_traffic_and_limits():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT username, limit_gb, expire_date FROM users WHERE status='Active'")
    active_users = cursor.fetchall()
    
    today = datetime.datetime.now().strftime("%Y-%m-%d")
    online_list = get_online_users()
    
    # قفل هوشمند تک‌کاربره (قطع اتصال نفر دوم)
    for user in set(online_list):
        if user:
            try:
                count = int(subprocess.check_output(f"ps -u {user} | grep sshd | wc -l", shell=True).decode().strip())
                if count > 2: 
                    subprocess.run(f"sudo killall -u {user}", shell=True)
            except:
                pass

    for user in active_users:
        username, limit, expire_date = user
        if expire_date < today:
            subprocess.run(["sudo", "usermod", "-L", username])
            cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
            continue
            
        cursor.execute("SELECT used_gb FROM users WHERE username=?", (username,))
        used = cursor.fetchone()[0]
        if used >= limit:
            subprocess.run(["sudo", "usermod", "-L", username])
            cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
            
    conn.commit()
    conn.close()

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8"><title>پنل مدیریت کاربران SSH PRO</title>
    <style>
        body { font-family: Tahoma, Arial; background-color: #f4f6f9; margin: 20px; direction: rtl; }
        .container { max-width: 1200px; background: white; padding: 25px; border-radius: 8px; box-shadow: 0 4px 10px rgba(0,0,0,0.08); margin: auto; }
        h2 { border-bottom: 2px solid #007bff; padding-bottom: 10px; color: #007bff; margin-top: 30px; }
        .flex-box { display: flex; gap: 15px; flex-wrap: wrap; margin-bottom: 20px; }
        form.add-form { display: flex; gap: 10px; flex-wrap: wrap; background: #f8f9fa; padding: 15px; border-radius: 6px; width: 100%; border: 1px solid #e2e8f0; }
        input, select { padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 4px; flex: 1; min-width: 140px; }
        button { padding: 8px 16px; background: #007bff; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: bold; }
        button.btn-success { background: #28a745; }
        button.btn-danger { background: #dc3545; }
        button.btn-warning { background: #ffc107; color: #212529; }
        .backup-section { background: #e2e8f0; padding: 15px; border-radius: 6px; display: flex; gap: 20px; align-items: center; width: 100%; margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { border: 1px solid #e2e8f0; padding: 12px; text-align: center; }
        th { background-color: #f1f5f9; color: #334155; }
        .badge { padding: 4px 8px; border-radius: 4px; color: white; font-size: 12px; font-weight: bold; }
        .online { background: #28a745; } .offline { background: #94a3b8; }
        .alert { padding: 10px; background: #d4edda; color: #155724; border-radius: 4px; margin-bottom: 15px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚙️ پنل مدیریت هوشمند SSH PRO</h1>
        
        <h2>💾 پشتیبان‌گیری و بازگردانی سریع (Backup & Restore)</h2>
        <div class="backup-section">
            <div>
                <a href="/backup/download"><button class="btn-success">📥 دانلود فایل بک‌آپ پنل</button></a>
            </div>
            <div style="border-right: 2px solid #cbd5e1; padding-right: 20px;">
                <form action="/backup/restore" method="POST" enctype="multipart/form-data" style="display: flex; gap: 10px; margin: 0; padding: 0;">
                    <label style="font-weight: bold; margin-top: 5px;">📤 بازگردانی فایل بک‌آپ:</label>
                    <input type="file" name="backup_file" accept=".json" required style="background: white; min-width: auto;">
                    <button type="submit" class="btn-danger">شروع عملیات ریستور</button>
                </form>
            </div>
        </div>

        <h2>➕ ساخت کاربر جدید</h2>
        <form action="/add" method="POST" class="add-form">
            <input type="text" name="username" placeholder="نام کاربری" required>
            <input type="text" name="password" placeholder="کلمه عبور" required>
            <input type="number" step="0.1" name="limit_gb" placeholder="حجم مجاز (GB)" required>
            <input type="number" name="days" placeholder="مدت اعتبار (روز)" required>
            <button type="submit">ایجاد اکانت</button>
        </form>

        <h2>👥 لیست کاربران فعال و وضعیت منابع</h2>
        <table>
            <tr>
                <th>نام کاربری</th>
                <th>کلمه عبور</th>
                <th>حجم کل</th>
                <th>حجم مصرفی</th>
                <th>تاریخ انقضا</th>
                <th>وضعیت اتصال</th>
                <th>وضعیت اکانت</th>
                <th>عملیات مدیریت</th>
            </tr>
            {% for user in users %}
            <tr>
                <td>{{ user[0] }}</td>
                <td>{{ user[1] }}</td>
                <td>{{ user[2] }} GB</td>
                <td>{{ "%.2f"|format(user[3]) }} GB</td>
                <td>{{ user[4] }}</td>
                <td>
                    {% if user[0] in online_users %}
                    <span class="badge online">آنلاین</span>
                    {% else %}
                    <span class="badge offline">آفلاین</span>
                    {% endif %}
                </td>
                <td>{{ user[5] }}</td>
                <td>
                    <form action="/edit" method="POST" style="display:inline; padding:0; margin:0;">
                        <input type="hidden" name="username" value="{{ user[0] }}">
                        <input type="number" step="0.1" name="limit_gb" value="{{ user[2] }}" style="width:65px; min-width:auto; padding:2px;">
                        <input type="text" name="expire_date" value="{{ user[4] }}" style="width:95px; min-width:auto; padding:2px;">
                        <button type="submit" class="btn-warning" style="padding:3px 8px; font-size:12px;">ویرایش</button>
                    </form>
                    
                    <a href="/reset/{{ user[0] }}"><button class="btn-success" style="padding:3px 8px; font-size:12px;">ریست مصرف</button></a>
                    <a href="/delete/{{ user[0] }}"><button class="btn-danger" style="padding:3px 8px; font-size:12px;">حذف</button></a>
                </td>
            </tr>
            {% endfor %}
        </table>
    </div>
</body>
</html>
"""

@app.route('/')
def index():
    update_traffic_and_limits()
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT username, password, limit_gb, used_gb, expire_date, status FROM users")
    users = cursor.fetchall()
    conn.close()
    return render_template_string(HTML_TEMPLATE, users=users, online_users=get_online_users())

@app.route('/add', methods=['POST'])
def add_user():
    username = request.form['username'].strip()
    password = request.form['password'].strip()
    limit_gb = float(request.form['limit_gb'].strip())
    days = int(request.form['days'].strip())
    expire_date = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime("%Y-%m-%d")
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    try:
        subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)
        cursor.execute("INSERT INTO users (username, password, limit_gb, expire_date) VALUES (?, ?, ?, ?)",
                       (username, password, limit_gb, expire_date))
        conn.commit()
    except:
        pass
    conn.close()
    return redirect('/')

@app.route('/edit', methods=['POST'])
def edit_user():
    username = request.form['username'].strip()
    limit_gb = float(request.form['limit_gb'].strip())
    expire_date = request.form['expire_date'].strip()
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET limit_gb=?, expire_date=?, status='Active' WHERE username=?", (limit_gb, expire_date, username))
    conn.commit()
    conn.close()
    
    subprocess.run(["sudo", "usermod", "-U", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return redirect('/')

@app.route('/reset/<username>')
def reset_user(username):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET used_gb=0.0, status='Active' WHERE username=?", (username,))
    conn.commit()
    conn.close()
    subprocess.run(["sudo", "usermod", "-U", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return redirect('/')

@app.route('/delete/<username>')
def delete_user(username):
    subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM users WHERE username=?", (username,))
    conn.commit()
    conn.close()
    return redirect('/')

# دانلود فایل بک آپ به صورت فرمت خوانای JSON
@app.route('/backup/download')
def download_backup():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT username, password, limit_gb, used_gb, expire_date, status FROM users")
    rows = cursor.fetchall()
    conn.close()
    
    backup_data = []
    for row in rows:
        backup_data.append({
            "username": row[0], "password": row[1], "limit_gb": row[2],
            "used_gb": row[3], "expire_date": row[4], "status": row[5]
        })
        
    backup_filename = f"/tmp/ssh_backup_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(backup_filename, "w") as f:
        json.dump(backup_data, f, indent=4)
        
    return send_file(backup_filename, as_attachment=True, download_name="ssh_panel_backup.json")

# آپلود و ساخت آنی کاربران از روی فایل JSON بک آپ
@app.route('/backup/restore', methods=['POST'])
def restore_backup():
    if 'backup_file' not in request.files:
        return redirect('/')
    file = request.files['backup_file']
    if file.filename == '':
        return redirect('/')
        
    if file:
        data = json.load(file)
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        for item in data:
            username = item['username']
            password = item['password']
            limit_gb = item['limit_gb']
            used_gb = item['used_gb']
            expire_date = item['expire_date']
            status = item['status']
            
            # ساخت مجدد کاربر در لینوکس جدید
            subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)
            if status != 'Active':
                subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                
            # درج یا بروزرسانی در دیتابیس نوپا
            cursor.execute('''
                INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (username, password, limit_gb, used_gb, expire_date, status))
            
        conn.commit()
        conn.close()
    return redirect('/')

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
EOF

    sudo tee /etc/systemd/system/custom-panel.service > /dev/null <<EOF
[Unit]
Description=SSH Advanced GUI Pro Panel
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /etc/custom-panel/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable custom-panel.service
    sudo systemctl restart custom-panel.service
}

if [ "$MAIN_CHOICE" == "1" ]; then
    install_prerequisites
    create_panel_app
    echo "=================================================="
    echo "✔ PRO SSH Panel with Web Backup Installed!"
    echo "🌐 Web Interface: http://YOUR_SERVER_IP:5000"
    echo "📱 Client Port: 443"
    echo "=================================================="

elif [ "$MAIN_CHOICE" == "2" ]; then
    install_prerequisites
    echo "[!] Please use Web GUI on port 5000 to upload json backup easily."
    create_panel_app
fi
