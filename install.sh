#!/bin/bash

# خروج در صورت بروز خطا
set -e

clear
echo -e "\e[1;34m==================================================\e[0m"
echo -e "\e[1;36m    SSH PRO ADVANCED PANEL (SMART RENEW & DARK)   \e[0m"
echo -e "\e[1;34m==================================================\e[0m"
echo "Please select an option:"
echo "1) Fresh Install (نصب اولیه یا راه اندازی مجدد)"
echo "2) Command-Line Restore (در صورتی که فایل دیتابیس را دارید)"
echo -e "\e[1;34m==================================================\e[0m"
read -p "Enter your choice (1 or 2): " MAIN_CHOICE

DB_FILE="/etc/custom-panel/panel.db"
WEB_PANEL_PORT=5000

install_prerequisites() {
    echo "[*] Fixing potential dpkg locks and installing requirements..."
    sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock
    sudo dpkg --configure -a || true
    
    sudo apt update
    sudo apt install -y openssh-server python3 python3-pip python3-flask ufw sqlite3 bc
    
    # تنظیم ایمن فایروال بدون مسدود سازی دسترسی اصلی
    sudo ufw allow $WEB_PANEL_PORT/tcp comment 'Web Panel'
    sudo ufw allow 443/tcp comment 'SSH Port'
    sudo ufw allow 22/tcp comment 'SSH MGMT'
    sudo ufw --force enable
    
    sudo mkdir -p /etc/custom-panel
}

create_panel_app() {
    echo "[*] Creating Core Python Web GUI with Advanced Features..."
    sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, datetime, sqlite3, json
from flask import Flask, request, render_template_string, redirect, send_file

app = Flask(__name__)
app.secret_key = "ssh_pro_premium_dark_key_v2"
DB_FILE = "/etc/custom-panel/panel.db"

def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    # افزودن فیلدهای initial_gb و initial_days برای ذخیره تنظیمات اولیه جهت تمدید هوشمند
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            username TEXT PRIMARY KEY,
            password TEXT,
            limit_gb REAL,
            used_gb REAL DEFAULT 0.0,
            expire_date TEXT,
            status TEXT DEFAULT 'Active',
            initial_gb REAL,
            initial_days INTEGER
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
    
    # قفل هوشمند و اجباری تک‌کاربره
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
            subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
            continue
            
        cursor.execute("SELECT used_gb FROM users WHERE username=?", (username,))
        used = cursor.fetchone()[0]
        if used >= limit:
            subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
            
    conn.commit()
    conn.close()

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>⚡ SSH PRO PANEL - PREMIUM DARK ⚡</title>
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: #1e293b;
            --accent-blue: #3b82f6;
            --accent-green: #10b981;
            --accent-red: #ef4444;
            --accent-yellow: #f59e0b;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --border-color: #334155;
        }
        body { 
            font-family: 'Segoe UI', Tahoma, Arial; 
            background-color: var(--bg-color); 
            color: var(--text-main);
            margin: 0; padding: 30px; 
            direction: rtl; 
        }
        .container { 
            max-width: 1300px; 
            background: var(--card-bg); 
            padding: 30px; 
            border-radius: 12px; 
            box-shadow: 0 10px 25px rgba(0,0,0,0.4); 
            margin: auto;
            border: 1px solid var(--border-color);
        }
        h1 { font-size: 26px; color: var(--text-main); display: flex; align-items: center; gap: 10px; margin-bottom: 25px; }
        h2 { font-size: 18px; color: var(--accent-blue); margin-top: 35px; border-bottom: 1px solid var(--border-color); padding-bottom: 8px; }
        
        .grid-header { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 25px; }
        .card-inner { background: #111827; padding: 20px; border-radius: 8px; border: 1px solid var(--border-color); }
        
        form { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
        input, select { 
            background: #111827; color: var(--text-main); 
            border: 1px solid var(--border-color); padding: 10px 14px; 
            border-radius: 6px; flex: 1; min-width: 120px; transition: 0.2s;
        }
        input:focus { border-color: var(--accent-blue); outline: none; }
        
        button { 
            padding: 10px 20px; color: white; border: none; 
            border-radius: 6px; cursor: pointer; font-weight: 600; transition: 0.2s; 
        }
        button:hover { filter: brightness(1.2); }
        .btn-blue { background: var(--accent-blue); }
        .btn-green { background: var(--accent-green); }
        .btn-red { background: var(--accent-red); }
        .btn-yellow { background: var(--accent-yellow); color: #000; }
        
        table { width: 100%; border-collapse: collapse; margin-top: 20px; background: #111827; border-radius: 8px; overflow: hidden; }
        th, td { border: 1px solid var(--border-color); padding: 14px; text-align: center; }
        th { background-color: #1e293b; color: var(--text-muted); font-weight: 600; }
        tr:hover { background-color: #1e293b; }
        
        .badge { padding: 5px 10px; border-radius: 5px; font-size: 12px; font-weight: bold; display: inline-block; }
        .online { background: rgba(16, 185, 129, 0.2); color: #34d399; border: 1px solid #10b981; }
        .offline { background: rgba(148, 163, 184, 0.2); color: #cbd5e1; border: 1px solid #94a3b8; }
        .status-active { color: #34d399; }
        .status-expired { color: #f87171; }
        .status-limit { color: #fbbf24; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ پنل مدیریت هوشمند و پیشرفته SSH PRO</h1>
        
        <div class="grid-header">
            <div class="card-inner">
                <h3 style="margin-top:0; color:var(--accent-green);">📥 پشتیبان‌گیری دیتابیس</h3>
                <p style="color:var(--text-muted); font-size:13px;">دانلود آنی ساختار کامل کاربران، حجم و زمان باقی‌مانده.</p>
                <a href="/backup/download"><button class="btn-green" style="width:100%;">دانلود فایل بک‌آپ پنل (.json)</button></a>
            </div>
            <div class="card-inner">
                <h3 style="margin-top:0; color:var(--accent-red);">📤 بازگردانی دیتابیس</h3>
                <form action="/backup/restore" method="POST" enctype="multipart/form-data" style="flex-direction: column; align-items: stretch; gap: 8px;">
                    <input type="file" name="backup_file" accept=".json" required style="padding:6px;">
                    <button type="submit" class="btn-red">شروع عملیات ریستور بر روی سرور جدید</button>
                </form>
            </div>
        </div>

        <h2>➕ ساخت اکانت تک‌کاربره جدید</h2>
        <div class="card-inner">
            <form action="/add" method="POST">
                <input type="text" name="username" placeholder="نام کاربری" required>
                <input type="text" name="password" placeholder="کلمه عبور" required>
                <input type="number" step="0.1" name="limit_gb" placeholder="حجم مجاز (GB)" required>
                <input type="number" name="days" placeholder="مدت اعتبار (روز)" required>
                <button type="submit" class="btn-blue">ایجاد کاربر جدید</button>
            </form>
        </div>

        <h2>👥 مانیتورینگ منابع و اتصال کاربران زنده</h2>
        <table>
            <thead>
                <tr>
                    <th>نام کاربری</th>
                    <th>کلمه عبور</th>
                    <th>حجم مجاز اولیه</th>
                    <th>حجم مصرفی فعلی</th>
                    <th>روزهای باقی‌مانده</th>
                    <th>وضعیت اتصال</th>
                    <th>وضعیت سیستم</th>
                    <th>عملیات ویرایش و تمدید خودکار</th>
                </tr>
            </thead>
            <tbody>
                {% for user in users %}
                <tr>
                    <td style="font-weight:bold; color:var(--accent-blue);">{{ user[0] }}</td>
                    <td><code>{{ user[1] }}</code></td>
                    <td>{{ user[2] }} GB</td>
                    <td><span style="color:#38bdf8;">{{ "%.2f"|format(user[3]) }}</span> GB</td>
                    <td style="font-weight: bold; color: #f43f5e;">
                        {% if user[6] >= 0 %}
                            {{ user[6] }} روز
                        {% else %}
                            منقضی شده
                        {% endif %}
                    </td>
                    <td>
                        {% if user[0] in online_users %}
                        <span class="badge online">● آنلاین</span>
                        {% else %}
                        <span class="badge offline">○ آفلاین</span>
                        {% endif %}
                    </td>
                    <td>
                        {% if user[5] == 'Active' %}
                        <span class="status-active">✔ فعال</span>
                        {% elif user[5] == 'Expired' %}
                        <span class="status-expired">❌ منقضی شده</span>
                        {% else %}
                        <span class="status-limit">⚠️ پایان حجم</span>
                        {% endif %}
                    </td>
                    <td>
                        <form action="/edit" method="POST" style="display:inline-flex; gap:5px; background:none; padding:0;">
                            <input type="hidden" name="username" value="{{ user[0] }}">
                            <input type="number" step="0.1" name="limit_gb" value="{{ user[2] }}" style="width:65px; min-width:auto; padding:4px; font-size:12px;" title="حجم جدید">
                            <input type="number" name="add_days" value="{{ user[7] }}" style="width:55px; min-width:auto; padding:4px; font-size:12px;" title="روزهای جدید">
                            <button type="submit" class="btn-yellow" style="padding:4px 8px; font-size:12px;">ویرایش</button>
                        </form>
                        
                        <a href="/renew/{{ user[0] }}" style="text-decoration:none;" title="تمدید مجدد بر اساس پکیج روز اول"><button class="btn-green" style="padding:4px 8px; font-size:12px;">🔄 تمدید خودکار</button></a>
                        <a href="/delete/{{ user[0] }}" style="text-decoration:none;"><button class="btn-red" style="padding:4px 8px; font-size:12px;">حذف</button></a>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
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
    cursor.execute("SELECT username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days FROM users")
    raw_users = cursor.fetchall()
    conn.close()
    
    processed_users = []
    today = datetime.datetime.now().date()
    
    for row in raw_users:
        username, password, limit_gb, used_gb, expire_date, status, init_gb, init_days = row
        try:
            exp_date = datetime.datetime.strptime(expire_date, "%Y-%m-%d").date()
            remaining_days = (exp_date - today).days
        except:
            remaining_days = 0
            
        processed_users.append((
            username, password, limit_gb, used_gb, expire_date, status, remaining_days, init_days
        ))
        
    return render_template_string(HTML_TEMPLATE, users=processed_users, online_users=get_online_users())

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
        cursor.execute("INSERT OR REPLACE INTO users (username, password, limit_gb, expire_date, initial_gb, initial_days) VALUES (?, ?, ?, ?, ?, ?)",
                       (username, password, limit_gb, expire_date, limit_gb, days))
        conn.commit()
    except:
        pass
    conn.close()
    return redirect('/')

@app.route('/edit', methods=['POST'])
def edit_user():
    username = request.form['username'].strip()
    limit_gb = float(request.form['limit_gb'].strip())
    add_days = int(request.form['add_days'].strip())
    
    expire_date = (datetime.datetime.now() + datetime.timedelta(days=add_days)).strftime("%Y-%m-%d")
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET limit_gb=?, expire_date=?, initial_gb=?, initial_days=?, status='Active' WHERE username=?", 
                   (limit_gb, expire_date, limit_gb, add_days, username))
    conn.commit()
    conn.close()
    
    subprocess.run(["sudo", "usermod", "-U", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return redirect('/')

# تمدید خودکار و هوشمند بر اساس دیتای روز اول
@app.route('/renew/<username>')
def renew_user(username):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT initial_gb, initial_days FROM users WHERE username=?", (username,))
    row = cursor.fetchone()
    
    if row:
        init_gb, init_days = row
        # محاسبه تاریخ انقضای جدید از همین امروز
        new_expire = (datetime.datetime.now() + datetime.timedelta(days=init_days)).strftime("%Y-%m-%d")
        
        # تمدید حجم، ریست مصرف به صفر و فعالسازی مجدد وضعیت کاربر
        cursor.execute("UPDATE users SET used_gb=0.0, limit_gb=?, expire_date=?, status='Active' WHERE username=?", 
                       (init_gb, new_expire, username))
        conn.commit()
        
        subprocess.run(["sudo", "usermod", "-U", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
    conn.close()
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

@app.route('/backup/download')
def download_backup():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days FROM users")
    rows = cursor.fetchall()
    conn.close()
    
    backup_data = []
    for row in rows:
        backup_data.append({
            "username": row[0], "password": row[1], "limit_gb": row[2], "used_gb": row[3],
            "expire_date": row[4], "status": row[5], "initial_gb": row[6], "initial_days": row[7]
        })
        
    backup_filename = f"/tmp/ssh_premium_backup.json"
    with open(backup_filename, "w") as f:
        json.dump(backup_data, f, indent=4)
        
    return send_file(backup_filename, as_attachment=True, download_name="ssh_premium_backup.json")

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
            init_gb = item.get('initial_gb', limit_gb)
            init_days = item.get('initial_days', 30)
            
            subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)
            if status != 'Active':
                subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                
            cursor.execute('''
                INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (username, password, limit_gb, used_gb, expire_date, status, init_gb, init_days))
            
        conn.commit()
        conn.close()
    return redirect('/')

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
EOF

    sudo tee /etc/systemd/system/custom-panel.service > /dev/null <<EOF
[Unit]
Description=SSH Advanced GUI Dark Panel
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
    echo -e "\e[1;32m==================================================\e[0m"
    echo -e "\e[1;32m✔ SUCCESS: SYSTEM FIXED & PREMIUM PANEL RUNNING! \e[0m"
    echo -e "\e[1;36m🌐 Dark Interface URL: http://YOUR_SERVER_IP:5000 \e[0m"
    echo -e "\e[1;32m==================================================\e[0m"
elif [ "$MAIN_CHOICE" == "2" ]; then
    install_prerequisites
    create_panel_app
fi
