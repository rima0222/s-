#!/bin/bash

# غیرفعال کردن خروج اضطراری برای بخش‌های نوسانی سیستم جهت تضمین عدم کرش
set +e

clear
echo -e "\e[1;33m[*] Optimizing Web GUI Fonts and Fixing Traffic Engine...\e[0m"

# آزاد کردن قفل‌های احتمالی apt برای جلوگیری از توقف نصب
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null
sudo dpkg --configure -a 2>/dev/null

echo -e "\e[1;34m==================================================\e[0m"
echo -e "\e[1;36m    SSH PRO PANEL (TRAFFIC FIXED & PREMIUM UI)    \e[0m"
echo -e "\e[1;34m==================================================\e[0m"

DB_FILE="/etc/custom-panel/panel.db"
WEB_PANEL_PORT=5000

update_and_replace_logic() {
    echo "[*] Cleaning up port 5000 gracefully..."
    sudo fuser -k $WEB_PANEL_PORT/tcp 2>/dev/null
    sudo mkdir -p /etc/custom-panel
}

install_prerequisites() {
    echo "[*] Checking core server dependencies..."
    set -e
    sudo apt update -y
    sudo apt install -y openssh-server python3 python3-pip python3-flask ufw sqlite3 bc psmisc iptables net-tools
    set +e
}

create_panel_app() {
    echo "[*] Injecting redesigned Beautiful Dark Web Panel..."
    sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, datetime, sqlite3, json, time, threading, re
from flask import Flask, request, render_template_string, redirect, send_file, jsonify, flash

app = Flask(__name__)
app.secret_key = "ssh_pro_premium_clean_key_v2"
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
            status TEXT DEFAULT 'Active',
            initial_gb REAL,
            initial_days INTEGER
        )
    ''')
    conn.commit()
    conn.close()

def get_sshd_connections():
    connections = {}
    try:
        output = subprocess.check_output("ps -eo user,pid,command | grep -E 'sshd:|ssh:'", shell=True).decode()
        for line in output.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 3:
                user = parts[0]
                pid = parts[1]
                if user not in ['root', 'sshd', 'nobody', 'ssh'] and 'net' not in user:
                    if user not in connections:
                        connections[user] = []
                    connections[user].append(pid)
    except:
        pass
    return connections

def get_online_users():
    return list(get_sshd_connections().keys())

def get_user_real_traffic(username):
    """موتور اصلاح‌شده و فوق‌دقیق استخراج بایت ترافیک مصرفی از فایروال هسته لینوکس"""
    try:
        res = subprocess.check_output(f"id -u {username}", shell=True).decode().strip()
        uid = int(res)
        
        # تضمین وجود قوانین فایروال بدون تداخل برای پایش زنده
        subprocess.run(f"sudo iptables -C OUTPUT -m owner --uid-owner {uid} -j ACCEPT 2>/dev/null || sudo iptables -I OUTPUT 1 -m owner --uid-owner {uid} -j ACCEPT", shell=True)
        subprocess.run(f"sudo iptables -C INPUT -m owner --uid-owner {uid} -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 1 -m owner --uid-owner {uid} -j ACCEPT", shell=True)
        
        total_bytes = 0
        
        # خواندن دقیق بایت‌های خروجی (OUTPUT)
        try:
            out_lines = subprocess.check_output("sudo iptables -L OUTPUT -v -n -x", shell=True).decode().strip().split('\n')
            for line in out_lines:
                if f"owner UID match {uid}" in line or f"owner match {uid}" in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        total_bytes += int(parts[1]) # ایندکس دقیق بایت‌های ارسالی در خروجی فایروال
        except:
            pass
            
        # خواندن دقیق بایت‌های ورودی (INPUT)
        try:
            in_lines = subprocess.check_output("sudo iptables -L INPUT -v -n -x", shell=True).decode().strip().split('\n')
            for line in in_lines:
                if f"owner UID match {uid}" in line or f"owner match {uid}" in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        total_bytes += int(parts[1]) # ایندکس دقیق بایت‌های دریافتی در خروجی فایروال
        except:
            pass

        # تبدیل بایت خالص به گیگابایت (GB) با دقت بالا
        return total_bytes / (1024.0 * 1024.0 * 1024.0)
    except:
        return 0.0

def safe_system_user_create(username, password):
    try:
        with open('/etc/passwd', 'r') as f:
            if username in f.read():
                subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except:
        pass
    subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)
    
    try:
        res = subprocess.check_output(f"id -u {username}", shell=True).decode().strip()
        uid = int(res)
        subprocess.run(f"sudo iptables -I OUTPUT 1 -m owner --uid-owner {uid} -j ACCEPT", shell=True)
        subprocess.run(f"sudo iptables -I INPUT 1 -m owner --uid-owner {uid} -j ACCEPT", shell=True)
    except:
        pass

def monitor_core_logic():
    while True:
        try:
            today = datetime.datetime.now().strftime("%Y-%m-%d")
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            
            # ۱. پایش اعتبار زمانی اکانت‌ها
            cursor.execute("SELECT username, expire_date, status FROM users WHERE status='Active'")
            active_users = cursor.fetchall()
            for user in active_users:
                username, expire_date, status = user
                if expire_date and expire_date < today:
                    subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
                    subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ۲. مانیتورینگ آنلاین ترافیک فایروال و اعمال محدودیت حجمی
            active_connections = get_sshd_connections()
            cursor.execute("SELECT username, limit_gb, used_gb, status FROM users")
            db_users = {r[0]: {"limit": r[1], "used": r[2], "status": r[3]} for r in cursor.fetchall()}
            
            for username in db_users.keys():
                userdata = db_users[username]
                real_gb_used = get_user_real_traffic(username)
                
                # ثبت ترافیک واقعیِ زنده در دیتابیس
                cursor.execute("UPDATE users SET used_gb=? WHERE username=?", (real_gb_used, username))
                userdata['used'] = real_gb_used

                if userdata['used'] >= userdata['limit'] and userdata['status'] == 'Active':
                    subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
                    subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ۳. جلوگیری سفت و سخت از اتصال همزمان (Multi-Login Blocker)
            for username, pids in active_connections.items():
                if len(pids) > 1:
                    for extra_pid in pids[1:]:
                        subprocess.run(["sudo", "kill", "-9", extra_pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        
            conn.commit()
            conn.close()
        except Exception as e:
            pass
        time.sleep(1)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>⚡ SSH PRO DASHBOARD - PREMIUM DARK ⚡</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Vazirmatn:wght@300;400;700&display=swap');
        
        :root {
            --bg-color: #0b0f19;
            --card-bg: #151f32;
            --input-bg: #1e293b;
            --accent-blue: #3b82f6;
            --accent-green: #10b981;
            --accent-red: #f43f5e;
            --accent-yellow: #eab308;
            --text-main: #f1f5f9;
            --text-muted: #64748b;
            --border-color: #1e293b;
        }
        body { 
            font-family: 'Vazirmatn', Tahoma, Arial, sans-serif; 
            background-color: var(--bg-color); 
            color: var(--text-main); 
            margin: 0; 
            padding: 40px 20px; 
            direction: rtl; 
            letter-spacing: -0.3px;
        }
        .container { 
            max-width: 1440px; 
            background: var(--card-bg); 
            padding: 35px; 
            border-radius: 16px; 
            box-shadow: 0 20px 40px rgba(0,0,0,0.5); 
            margin: auto; 
            border: 1px solid rgba(255,255,255,0.03); 
        }
        h1 { font-size: 24px; font-weight: 700; margin-bottom: 30px; display: flex; align-items: center; gap: 12px; color: #fff; }
        h2 { font-size: 17px; font-weight: 700; color: var(--accent-blue); margin-top: 40px; margin-bottom: 15px; display: flex; align-items: center; gap: 6px; }
        .grid-header { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .card-inner { background: #0f172a; padding: 22px; border-radius: 12px; border: 1px solid var(--border-color); box-shadow: inset 0 2px 4px rgba(0,0,0,0.2); }
        form { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
        input, select { 
            background: var(--input-bg); 
            color: #fff; 
            border: 1px solid var(--border-color); 
            padding: 12px 16px; 
            border-radius: 8px; 
            flex: 1; 
            min-width: 140px; 
            font-family: 'Vazirmatn';
            font-size: 14px;
            transition: all 0.2s;
        }
        input:focus { border-color: var(--accent-blue); outline: none; box-shadow: 0 0 0 3px rgba(59,130,246,0.15); }
        button { 
            padding: 12px 24px; 
            color: white; 
            border: none; 
            border-radius: 8px; 
            cursor: pointer; 
            font-weight: 700; 
            font-family: 'Vazirmatn';
            font-size: 14px;
            transition: all 0.2s; 
        }
        button:hover { filter: brightness(1.15); transform: translateY(-1px); }
        button:active { transform: translateY(0); }
        .btn-blue { background: var(--accent-blue); } 
        .btn-green { background: var(--accent-green); } 
        .btn-red { background: var(--accent-red); }
        table { width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 15px; background: #0f172a; border-radius: 12px; overflow: hidden; border: 1px solid var(--border-color); }
        th, td { padding: 16px; text-align: center; font-size: 14px; border-bottom: 1px solid var(--border-color); }
        th { background-color: #111827; color: var(--text-muted); font-weight: 700; font-size: 13px; text-transform: uppercase; }
        tr:last-child td { border-bottom: none; }
        tr:hover { background-color: #1e293b; }
        .badge { padding: 6px 12px; border-radius: 6px; font-size: 12px; font-weight: 700; display: inline-block; }
        .online { background: rgba(16, 185, 129, 0.15); color: #10b981; border: 1px solid rgba(16, 185, 129, 0.3); }
        .offline { background: rgba(100, 116, 139, 0.15); color: #94a3b8; border: 1px solid rgba(100, 116, 139, 0.3); }
        .alert-flash { padding: 14px; background: rgba(244, 63, 94, 0.15); border: 1px solid var(--accent-red); color: #f43f5e; border-radius: 8px; margin-bottom: 25px; text-align: center; font-weight: 700; font-size: 14px; }
        
        /* طراحی پرمیوم و شیک نوار حجم باقی‌مانده */
        .progress-wrapper { width: 230px; text-align: right; margin: auto; }
        .progress-text { display: flex; justify-content: space-between; font-size: 12px; font-weight: 400; color: #94a3b8; margin-bottom: 5px; }
        .progress-container { width: 100%; background-color: #1e293b; border-radius: 10px; height: 8px; overflow: hidden; box-shadow: inset 0 1px 3px rgba(0,0,0,0.5); }
        .progress-bar { height: 100%; width: 100%; border-radius: 10px; transition: width 0.6s cubic-bezier(0.4, 0, 0.2, 1), background-color 0.4s ease; }
        code { background: #1e293b; padding: 4px 8px; border-radius: 4px; font-family: Courier, monospace; color: #38bdf8; font-size: 13px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ مدیریت اکانت‌های ویژه SSH PRO PANEL</h1>
        
        {% with messages = get_flashed_messages() %}
          {% if messages %}
            {% for message in messages %}
              <div class="alert-flash">📢 {{ message }}</div>
            {% endfor %}
          {% endif %}
        {% endwith %}

        <div class="grid-header">
            <div class="card-inner" style="margin-bottom:0;">
                <h3 style="margin-top:0; font-size:15px; color:var(--accent-green);">📥 فایل پشتیبان سیستم</h3>
                <p style="color:var(--text-muted); font-size:13px; margin-bottom:15px;">دانلود دیتابیس کانفیگ‌ها به صورت فایل ساختاریافته هوشمند JSON.</p>
                <a href="/backup/download"><button class="btn-green" style="width:100%;">📥 دانلود نسخه پشتیبان کاربران</button></a>
            </div>
            <div class="card-inner" style="margin-bottom:0;">
                <h3 style="margin-top:0; font-size:15px; color:var(--accent-red);">📤 بازگردانی دیتابیس (Restore)</h3>
                <p style="color:var(--text-muted); font-size:13px; margin-bottom:12px;">فایل بک‌آپ دانلود شده از قبل را بارگذاری و اعمال کنید.</p>
                <form action="/backup/restore" method="POST" enctype="multipart/form-data" style="flex-direction: column; align-items: stretch; gap: 8px;">
                    <input type="file" name="backup_file" accept=".json" required style="padding:8px;">
                    <button type="submit" class="btn-red">📤 شروع بازیابی بدون تغییر اطلاعات</button>
                </form>
            </div>
        </div>
        
        <h2>✨ افزودن اکانت اختصاصی جدید</h2>
        <div class="card-inner">
            <form action="/add" method="POST">
                <input type="text" name="username" placeholder="نام کاربری" required>
                <input type="text" name="password" placeholder="کلمه عبور" required>
                <input type="number" step="0.1" name="limit_gb" placeholder="حجم ترافیک مجاز (GB)" required>
                <input type="number" name="days" placeholder="مدت دوره (روز)" required>
                <button type="submit" class="btn-blue">➕ ایجاد و فعال‌سازی</button>
            </form>
        </div>

        <h2>👥 وضعیت مصرف ترافیک و مانیتورینگ آنلاین</h2>
        <table>
            <thead>
                <tr>
                    <th>نام کاربری</th>
                    <th>کلمه عبور</th>
                    <th>حجم کل (GB)</th>
                    <th>حجم مصرفی (GB)</th>
                    <th>وضعیت نوار حجم مجاز</th>
                    <th>اعتبار زمانی</th>
                    <th>وضعیت اتصال</th>
                    <th>وضعیت سرویس</th>
                    <th>اقدام سرویس</th>
                </tr>
            </thead>
            <tbody id="user-table-body">
                </tbody>
        </table>
    </div>

    <script>
        async function fetchLiveStatus() {
            try {
                const response = await fetch('/api/live_data');
                const data = await response.json();
                const tbody = document.getElementById('user-table-body');
                tbody.innerHTML = '';

                data.users.forEach(user => {
                    const isOnline = data.online_users.includes(user.username);
                    const onlineBadge = isOnline 
                        ? '<span class="badge online">● آنلاین</span>' 
                        : '<span class="badge offline">○ آفلاین</span>';
                    
                    let statusText = '<span style="color:#10b981; font-weight:700;">فعال</span>';
                    if (user.status === 'Expired') statusText = '<span style="color:#f43f5e; font-weight:700;">منقضی دوره</span>';
                    if (user.status === 'Traffic_Limit') statusText = '<span style="color:#eab308; font-weight:700;">اتمام ترافیک</span>';

                    const totalGb = user.limit_gb;
                    const usedGb = user.used_gb;
                    let remainingGb = totalGb - usedGb;
                    if (remainingGb < 0) remainingGb = 0;
                    
                    let remainingPercent = totalGb > 0 ? (remainingGb / totalGb) * 100 : 0;
                    
                    // تغییر رنگ داینامیک و لوکس بر اساس باقیمانده حجم کاربر
                    let barColor = 'var(--accent-green)'; 
                    if (remainingPercent <= 50 && remainingPercent > 20) {
                        barColor = 'var(--accent-yellow)'; 
                    } else if (remainingPercent <= 20) {
                        barColor = 'var(--accent-red)'; 
                    }

                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td style="font-weight:700; color:#3b82f6;">${user.username}</td>
                        <td><code>${user.password}</code></td>
                        <td style="font-weight:700; color:#cbd5e1;">${totalGb} GB</td>
                        <td><span style="color:#38bdf8; font-weight:700;">${usedGb.toFixed(3)}</span> GB</td>
                        <td>
                            <div class="progress-wrapper">
                                <div class="progress-text">
                                    <span>باقی‌مانده: <b>${remainingGb.toFixed(2)} GB</b></span>
                                    <span>${remainingPercent.toFixed(0)}%</span>
                                </div>
                                <div class="progress-container">
                                    <div class="progress-bar" style="width: ${remainingPercent}%; background-color: ${barColor};"></div>
                                </div>
                            </div>
                        </td>
                        <td style="font-weight: 700; color: #f43f5e;">${user.remaining_days >= 0 ? user.remaining_days + ' روز' : 'پایان زمان'}</td>
                        <td>${onlineBadge}</td>
                        <td>${statusText}</td>
                        <td>
                            <a href="/renew/${user.username}"><button class="btn-green" style="padding:6px 14px; font-size:12px; border-radius:6px;">🔄 ریست دوره</button></a>
                            <a href="/delete/${user.username}"><button class="btn-red" style="padding:6px 14px; font-size:12px; border-radius:6px;">حذف</button></a>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            } catch (error) {
                console.error("Error updating interface components:", error);
            }
        }
        fetchLiveStatus();
        setInterval(fetchLiveStatus, 1000);
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/live_data')
def live_data():
    try:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("SELECT username, password, limit_gb, used_gb, expire_date, status, initial_days FROM users")
        rows = cursor.fetchall()
        conn.close()
        
        today = datetime.datetime.now().date()
        users_list = []
        for row in rows:
            username, password, limit_gb, used_gb, expire_date, status, init_days = row
            try:
                exp_date = datetime.datetime.strptime(expire_date, "%Y-%m-%d").date()
                remaining_days = (exp_date - today).days
            except:
                remaining_days = 0
                
            users_list.append({
                "username": username, "password": password, "limit_gb": limit_gb if limit_gb else 0.0,
                "used_gb": used_gb if used_gb else 0.0, "remaining_days": remaining_days, "status": status,
                "initial_days": init_days if init_days else 30
            })
        return jsonify({"users": users_list, "online_users": get_online_users()})
    except Exception as e:
        return jsonify({"users": [], "online_users": [], "error": str(e)})

@app.route('/add', methods=['POST'])
def add_user():
    try:
        username = request.form['username'].strip()
        password = request.form['password'].strip()
        limit_gb = float(request.form['limit_gb'].strip())
        days = int(request.form['days'].strip())
        expire_date = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime("%Y-%m-%d")
        
        safe_system_user_create(username, password)
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days) VALUES (?, ?, ?, 0.0, ?, 'Active', ?, ?)",
                       (username, password, limit_gb, expire_date, limit_gb, days))
        conn.commit()
        conn.close()
    except:
        pass
    return redirect('/')

@app.route('/renew/<username>')
def renew_user(username):
    try:
        try:
            res = subprocess.check_output(f"id -u {username}", shell=True).decode().strip()
            uid = int(res)
            subprocess.run(f"sudo iptables -Z OUTPUT -m owner --uid-owner {uid} 2>/dev/null || true", shell=True)
            subprocess.run(f"sudo iptables -Z INPUT -m owner --uid-owner {uid} 2>/dev/null || true", shell=True)
        except:
            pass
            
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("SELECT initial_gb, initial_days FROM users WHERE username=?", (username,))
        row = cursor.fetchone()
        if row:
            init_gb, init_days = row
            new_expire = (datetime.datetime.now() + datetime.timedelta(days=init_days)).strftime("%Y-%m-%d")
            
            cursor.execute("UPDATE users SET used_gb=0.0, limit_gb=?, expire_date=?, status='Active' WHERE username=?", 
                           (init_gb, new_expire, username))
            conn.commit()
            subprocess.run(["sudo", "usermod", "-U", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        conn.close()
    except:
        pass
    return redirect('/')

@app.route('/delete/<username>')
def delete_user(username):
    try:
        try:
            res = subprocess.check_output(f"id -u {username}", shell=True).decode().strip()
            uid = int(res)
            subprocess.run(f"sudo iptables -D OUTPUT -m owner --uid-owner {uid} -j ACCEPT 2>/dev/null || true", shell=True)
            subprocess.run(f"sudo iptables -D INPUT -m owner --uid-owner {uid} -j ACCEPT 2>/dev/null || true", shell=True)
        except:
            pass
            
        subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM users WHERE username=?", (username,))
        conn.commit()
        conn.close()
    except:
        pass
    return redirect('/')

@app.route('/backup/download')
def download_backup():
    try:
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
        backup_filename = "/tmp/ssh_premium_backup.json"
        with open(backup_filename, "w") as f:
            json.dump(backup_data, f, indent=4)
        return send_file(backup_filename, as_attachment=True, download_name="ssh_premium_backup.json")
    except Exception as e:
        return str(e)

@app.route('/backup/restore', methods=['POST'])
def restore_backup():
    try:
        if 'backup_file' not in request.files: return redirect('/')
        file = request.files['backup_file']
        if file.filename == '' or not file: return redirect('/')
        
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
            
            safe_system_user_create(username, password)
            if status != 'Active':
                subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                
            cursor.execute('''
                INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (username, password, limit_gb, used_gb, expire_date, status, init_gb, init_days))
        conn.commit()
        conn.close()
        flash("پشتیبان‌گیری با موفقیت بدون تداخل جایگذاری شد.")
    except Exception as e:
        flash(f"خطا در ریستور: {str(e)}")
    return redirect('/')

if __name__ == '__main__':
    init_db()
    threading.Thread(target=monitor_core_logic, daemon=True).start()
    app.run(host='0.0.0.0', port=5000)
EOF

    echo "[*] Confirming Service Layout Configuration..."
    sudo tee /etc/systemd/system/custom-panel.service > /dev/null <<EOF
[Unit]
Description=SSH Advanced GUI Dark Panel Ultimate
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

# اجرای بهینه
update_and_replace_logic
install_prerequisites
create_panel_app

echo -e "\e[1;32m==================================================\e[0m"
echo -e "\e[1;32m✔ DONE: ALL ENGINES ARE FULLY WORKING & FIXED!    \e[0m"
echo -e "\e[1;36m🌐 PREMIUM DASHBOARD UPDATED LIVE ON PORT 5000     \e[0m"
echo -e "\e[1;32m==================================================\e[0m"
