#!/bin/bash

# ۱. آزادسازی پورت و پروسس‌های قبلی
sudo killall -9 python3 2>/dev/null
sudo fuser -k 5000/tcp 2>/dev/null
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock 2>/dev/null

# ۲. نصب پکیج‌های پیش‌فرض
sudo apt update -y
sudo apt install -y openssh-server python3 python3-flask sqlite3 psmisc

# ۳. ایجاد دایرکتوری اصلی پنل
sudo mkdir -p /etc/custom-panel
sudo chmod 777 /etc/custom-panel

# ۴. تزریق مستقیم کد پایتون بهینه شده با معماری غیرهمگام
cat << 'EOF' > /etc/custom-panel/app.py
import os, subprocess, datetime, sqlite3, json, time, threading, pwd, re
from flask import Flask, request, render_template_string, redirect, send_file, jsonify

app = Flask(__name__)
app.secret_key = "ssh_pro_architecture_v3"
DB_FILE = "/etc/custom-panel/panel.db"
db_lock = threading.Lock()

# ذخیره موقت بایت‌های قبلی کاربر برای محاسبه دقیق ترافیک لحظه‌ای
TRAFFIC_TRACKER = {}

def get_db_connection():
    conn = sqlite3.connect(DB_FILE, timeout=20.0, check_same_thread=False)
    conn.execute('PRAGMA journal_mode=WAL;') # جلوگیری از قفل شدن دیتابیس هنگام خواندن و نوشتن همزمان
    return conn

def init_db():
    with db_lock:
        conn = get_db_connection()
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

def get_sshd_connections_and_traffic():
    """
    استخراج آنلاین‌ها و ترافیک دقیق مصرفی هر پروسه از هسته لینوکس
    """
    online_users = []
    pid_traffic = {}
    
    # خواندن آمار بایت‌های شبکه کلاینت‌ها از سیستم عامل
    try:
        # پیدا کردن کلاینت‌های متصل به sshd
        ps_output = subprocess.check_output("ps -eo user,pid,command | grep -E 'sshd:'", shell=True).decode()
        for line in ps_output.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 3:
                user = parts[0].strip()
                pid = parts[1].strip()
                if user not in ['root', 'sshd', 'nobody'] and 'net' not in user:
                    if user not in online_users:
                        online_users.append(user)
                    
                    # پیدا کردن حجم مصرفی دقیق این PID از طریق خروجی شبکه لینوکس
                    try:
                        with open(f"/proc/{pid}/net/dev", "r") as f:
                            net_data = f.read()
                        # جمع زدن بایت‌های دریافتی و ارسالی کلاینت
                        bytes_sum = 0
                        for net_line in net_data.split('\n'):
                            if ':' in net_line:
                                net_parts = net_line.split()
                                if len(net_parts) >= 10:
                                    bytes_sum += int(net_parts[1]) + int(net_parts[9]) # Rx bytes + Tx bytes
                        pid_traffic[user] = pid_traffic.get(user, 0) + bytes_sum
                    except:
                        pass
    except:
        pass
    return online_users, pid_traffic

def live_monitor_daemon():
    """
    دیمون پس‌زمینه برای اعمال محدودیت تک‌کاربره و بروزرسانی ترافیک بدون درگیر کردن لودینگ وب
    """
    global TRAFFIC_TRACKER
    while True:
        try:
            today = datetime.datetime.now().strftime("%Y-%m-%d")
            online_now, current_bytes = get_sshd_connections_and_traffic()
            
            # ۱. محاسبه ترافیک واقعی و ثبت تفاوت مابین بایت‌ها در دیتابیس
            if online_now:
                with db_lock:
                    conn = get_db_connection()
                    cursor = conn.cursor()
                    for user in online_now:
                        if user in current_bytes:
                            new_bytes = current_bytes[user]
                            if user in TRAFFIC_TRACKER:
                                diff = new_bytes - TRAFFIC_TRACKER[user]
                                if diff > 0:
                                    diff_gb = diff / (1024 * 1024 * 1024)
                                    cursor.execute("UPDATE users SET used_gb = used_gb + ? WHERE username = ? AND status='Active'", (diff_gb, user))
                            TRAFFIC_TRACKER[user] = new_bytes
                    conn.commit()
                    conn.close()

            # ۲. سیستم قطع اتصال سریع برای دیوایس‌های همزمان (تک کاربره سخت‌گیرانه)
            try:
                ps_output = subprocess.check_output("ps -eo user,pid,command | grep -E 'sshd:'", shell=True).decode()
                user_pids = {}
                for line in ps_output.strip().split('\n'):
                    parts = line.split()
                    if len(parts) >= 3:
                        user = parts[0].strip()
                        pid = parts[1].strip()
                        if user not in ['root', 'sshd', 'nobody'] and 'net' not in user:
                            if user not in user_pids: user_pids[user] = []
                            user_pids[user].append(pid)
                
                for username, pids in user_pids.items():
                    if len(pids) > 1:
                        # اگر بیش از یک دیوایس بود، دیوایس‌های قدیمی یا اضافی بلافاصله قطع می‌شوند
                        for extra_pid in pids[1:]:
                            subprocess.run(["sudo", "kill", "-9", extra_pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                pass

            # ۳. بررسی وضعیت حجمی و زمانی در دیتابیس
            with db_lock:
                conn = get_db_connection()
                cursor = conn.cursor()
                
                cursor.execute("SELECT username, expire_date, limit_gb, used_gb FROM users WHERE status='Active'")
                for username, expire_date, limit_gb, used_gb in cursor.fetchall():
                    if expire_date and expire_date < today:
                        subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
                        subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif used_gb >= limit_gb:
                        subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
                        subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                conn.commit()
                conn.close()
        except:
            pass
        time.sleep(2) # مانیتورینگ دقیق و سریع ۲ ثانیه‌ای بدون ایجاد لود روی CPU

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SSH PREMIUM PANEL</title>
    <style>
        body { font-family: sans-serif; background: #0f172a; color: #fff; padding: 20px; direction: rtl; }
        .container { max-width: 1100px; margin: auto; background: #1e293b; padding: 20px; border-radius: 10px; }
        form { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 20px; }
        input, button { padding: 10px; border-radius: 5px; border: none; font-weight: bold; }
        input { background: #334155; color: #fff; flex: 1; }
        button { cursor: pointer; background: #0284c7; color: white; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; background: #0f172a; }
        th, td { padding: 12px; text-align: center; border-bottom: 1px solid #334155; }
        th { background: #1e293b; color: #94a3b8; }
    </style>
</head>
<body>
    <div class="container">
        <h2>⚡ مانیتورینگ زنده و دقیق مصرف حجم کاربران SSH PRO</h2>
        
        <form action="/add" method="POST">
            <input type="text" name="username" placeholder="نام کاربری" required>
            <input type="text" name="password" placeholder="کلمه عبور" required>
            <input type="number" step="0.1" name="limit_gb" placeholder="حجم مجاز (GB)" required>
            <input type="number" name="days" placeholder="اعتبار (روز)" required>
            <button type="submit">➕ ساخت کاربر</button>
        </form>

        <table>
            <thead>
                <tr>
                    <th>نام کاربری</th>
                    <th>کلمه عبور</th>
                    <th>حجم کل مجاز</th>
                    <th>حجم مصرفی (همگام با گوشی)</th>
                    <th>اعتبار زمان باقی‌مانده</th>
                    <th>وضعیت اتصال</th>
                    <th>وضعیت سیستم</th>
                    <th>عملیات پنل</th>
                </tr>
            </thead>
            <tbody id="user-rows"></tbody>
        </table>
    </div>

    <script>
        async function updateData() {
            try {
                const res = await fetch('/api/users');
                const data = await res.json();
                const tbody = document.getElementById('user-rows');
                tbody.innerHTML = '';

                data.users.forEach(user => {
                    const isOnline = data.online.map(o => o.trim().toLowerCase()).includes(user.username.trim().toLowerCase());
                    const onlineStatus = isOnline ? '<span style="color:#22c55e; font-weight:bold;">● آنلاین (Live)</span>' : '<span style="color:#94a3b8;">○ آفلاین</span>';
                    
                    let statusText = '<span style="color:#22c55e;">فعال</span>';
                    if (user.status === 'Expired') statusText = '<span style="color:#ef4444;">منقضی شده</span>';
                    if (user.status === 'Traffic_Limit') statusText = '<span style="color:#eab308;">اتمام حجم</span>';

                    const tr = document.createElement('tr');
                    tr.innerHTML = '<td><b>' + user.username + '</b></td>' +
                                   '<td><code>' + user.password + '</code></td>' +
                                   '<td>' + user.limit_gb + ' GB</td>' +
                                   '<td style="color:#38bdf8; font-weight:bold;">' + user.used_gb.toFixed(4) + ' GB</td>' +
                                   '<td>' + user.remaining_days + ' روز</td>' +
                                   '<td>' + onlineStatus + '</td>' +
                                   '<td>' + statusText + '</td>' +
                                   '<td>' +
                                       '<a href="/renew/' + user.username + '"><button style="background:#22c55e; padding:5px 10px; font-size:12px; margin-left:5px;">تمدید</button></a>' +
                                       '<a href="/delete/' + user.username + '"><button style="background:#ef4444; padding:5px 10px; font-size:12px;">حذف</button></a>' +
                                   '</td>';
                    tbody.appendChild(tr);
                });
            } catch(e) {}
        }
        updateData();
        setInterval(updateData, 2000); // به روز رسانی آنی فرانت‌اند هر ۲ ثانیه یک‌بار
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/users')
def api_users():
    try:
        with db_lock:
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT username, password, limit_gb, used_gb, expire_date, status FROM users")
            rows = cursor.fetchall()
            conn.close()
        
        today = datetime.datetime.now().date()
        users_list = []
        for row in rows:
            username, password, limit_gb, used_gb, expire_date, status = row
            try:
                exp_date = datetime.datetime.strptime(expire_date, "%Y-%m-%d").date()
                remaining_days = (exp_date - today).days
                if remaining_days < 0: remaining_days = 0
            except: remaining_days = 0
                
            users_list.append({
                "username": username, "password": password, "limit_gb": limit_gb if limit_gb else 0.0,
                "used_gb": used_gb if used_gb else 0.0, "remaining_days": remaining_days, "status": status
            })
        online_now, _ = get_sshd_connections_and_traffic()
        return jsonify({"users": users_list, "online": online_now})
    except:
        return jsonify({"users": [], "online": []})

@app.route('/add', methods=['POST'])
def add_user():
    try:
        username = request.form['username'].strip()
        password = request.form['password'].strip()
        limit_gb = float(request.form['limit_gb'].strip())
        days = int(request.form['days'].strip())
        expire_date = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime("%Y-%m-%d")
        
        safe_system_user_create(username, password)
        
        with db_lock:
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days) VALUES (?, ?, ?, 0.0, ?, 'Active', ?, ?)",
                           (username, password, limit_gb, expire_date, limit_gb, days))
            conn.commit()
            conn.close()
    except: pass
    return redirect('/')

@app.route('/renew/<username>')
def renew_user(username):
    try:
        with db_lock:
            conn = get_db_connection()
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
    except: pass
    return redirect('/')

@app.route('/delete/<username>')
def delete_user(username):
    try:
        subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with db_lock:
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("DELETE FROM users WHERE username=?", (username,))
            conn.commit()
            conn.close()
    except: pass
    return redirect('/')

def safe_system_user_create(username, password):
    try:
        pwd.getpwnam(username)
        subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except KeyError: pass
    subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)

if __name__ == '__main__':
    init_db()
    # راه اندازی دیمون غیرهمگام مانیتورینگ جهت تضمین عدم تداخل با لودینگ صفحه وب
    threading.Thread(target=live_monitor_daemon, daemon=True).start()
    app.run(host='0.0.0.0', port=5000)
EOF

# ۵. ساخت سرویس دیمون لینوکس برای پایداری همیشگی و اجرای خودکار در پس‌زمینه سرور
sudo tee /etc/systemctl/system/custom-panel.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=SSH Pro Precision Management Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/custom-panel
ExecStart=/usr/bin/python3 /etc/custom-panel/app.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl daemon-reload
sudo systemctl enable custom-panel.service
sudo systemctl restart custom-panel.service

echo "--------------------------------------------------"
echo "✔ ARCHITECTURE STABLE: PANEL INSTALLED SUCCESSFULLY"
echo "🌐 LISTEN PORT: 5000"
echo "--------------------------------------------------"
