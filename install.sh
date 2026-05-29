#!/bin/bash

# ۱. آزادسازی پورت ۵۰۰۰ و پاکسازی پروسس‌های قدیمی پایتون
sudo killall -9 python3 2>/dev/null
sudo fuser -k 5000/tcp 2>/dev/null
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock 2>/dev/null

# ۲. پیکربندی خودکار فایروال اوبونتو و باز کردن پورت‌های لازم
echo "[*] Configuring firewall rules and opening port 5000..."
sudo ufw allow 5000/tcp >/dev/null 2>&1
sudo ufw allow 22/tcp >/dev/null 2>&1
sudo ufw --force enable >/dev/null 2>&1
sudo ufw reload >/dev/null 2>&1

sudo iptables -I INPUT -p tcp --dport 5000 -j ACCEPT 2>/dev/null
sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null

# ۳. نصب پکیج‌های پیش‌نیاز سیستم‌عامل
sudo apt update -y
sudo apt install -y openssh-server python3 python3-flask sqlite3 psmisc coreutils

# ۴. ایجاد دایرکتوری اصلی پنل
sudo mkdir -p /etc/custom-panel
sudo chmod 755 /etc/custom-panel

# ۵. تزریق کد پایتون به همراه قابلیت سرچ زنده کلاینت‌ساید و ظاهر شیشه‌ای
cat << 'EOF' > /etc/custom-panel/app.py
import os, subprocess, datetime, sqlite3, json, time, threading, pwd
from flask import Flask, request, render_template_string, redirect, send_file, jsonify

app = Flask(__name__)
app.secret_key = "ssh_pro_glass_search_v9"
DB_FILE = "/etc/custom-panel/panel.db"
db_lock = threading.Lock()

LAST_PID_BYTES = {}

def get_db_connection():
    conn = sqlite3.connect(DB_FILE, timeout=20.0, check_same_thread=False)
    conn.execute('PRAGMA journal_mode=WAL;')
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

def live_monitor_daemon():
    global LAST_PID_BYTES
    while True:
        try:
            today = datetime.datetime.now().strftime("%Y-%m-%d")
            ps_output = subprocess.check_output("ps -eo user,pid,command | grep -E 'sshd:'", shell=True).decode()
            
            active_pids_this_run = set()
            user_to_pids_map = {}

            for line in ps_output.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 3:
                    user = parts[0].strip()
                    pid = parts[1].strip()
                    if user not in ['root', 'sshd', 'nobody'] and 'net' not in user:
                        active_pids_this_run.add(pid)
                        if user not in user_to_pids_map:
                            user_to_pids_map[user] = []
                        user_to_pids_map[user].append(pid)

            # سیستم تک‌کاربره سخت‌گیرانه (قطع کانکشن‌های همزمان قدیمی)
            for username, pids in user_to_pids_map.items():
                if len(pids) > 1:
                    pids.sort(key=int)
                    for old_pid in pids[:-1]:
                        subprocess.run(["sudo", "kill", "-9", old_pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        if old_pid in LAST_PID_BYTES:
                            del LAST_PID_BYTES[old_pid]

            # محاسبه ترافیک مصرفی و تقسیم بر فاکتور کالیبراسیون ۳.۵
            with db_lock:
                conn = get_db_connection()
                cursor = conn.cursor()
                for username, pids in user_to_pids_map.items():
                    for active_pid in pids:
                        try:
                            with open(f"/proc/{active_pid}/net/dev", "r") as f:
                                net_data = f.read()
                            bytes_sum = 0
                            for net_line in net_data.split('\n'):
                                if ':' in net_line:
                                    net_parts = net_line.split()
                                    if len(net_parts) >= 10:
                                        bytes_sum += int(net_parts[1]) + int(net_parts[9])
                            
                            if active_pid in LAST_PID_BYTES:
                                diff = bytes_sum - LAST_PID_BYTES[active_pid]
                                if diff > 0:
                                    diff_gb = (diff / (1024.0 * 1024.0 * 1024.0)) / 3.5
                                    cursor.execute("UPDATE users SET used_gb = used_gb + ? WHERE username = ? AND status='Active'", (diff_gb, username))
                            LAST_PID_BYTES[active_pid] = bytes_sum
                        except: pass
                conn.commit()
                conn.close()

            for dead_pid in list(LAST_PID_BYTES.keys()):
                if dead_pid not in active_pids_this_run:
                    del LAST_PID_BYTES[dead_pid]

            # مسدودسازی خودکار کاربران اتمام ترافیک یا اتمام زمان یافته
            with db_lock:
                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute("SELECT username, expire_date, limit_gb, used_gb FROM users WHERE status='Active'")
                for username, expire_date, limit_gb, used_gb in cursor.fetchall():
                    if (expire_date and expire_date < today) or (used_gb >= limit_gb):
                        subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        new_status = 'Expired' if (expire_date and expire_date < today) else 'Traffic_Limit'
                        cursor.execute("UPDATE users SET status=? WHERE username=?", (new_status, username))
                        subprocess.run(f"sudo pkill -9 -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                conn.commit()
                conn.close()
        except: pass
        time.sleep(1.5)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SSH PREMIUM PANEL</title>
    <style>
        body { font-family: sans-serif; background: #0f172a; color: #fff; padding: 20px; direction: rtl; }
        .container { max-width: 1100px; margin: auto; background: #1e293b; padding: 20px; border-radius: 10px; }
        .top-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid #334155; padding-bottom: 15px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 15px; margin-bottom: 25px; }
        .stat-card { background: #1a2333; padding: 15px; border-radius: 8px; border: 1px solid #334155; text-align: center; }
        .stat-card h4 { margin: 0 0 10px 0; color: #94a3b8; font-size: 14px; }
        .stat-card .val { font-size: 22px; font-weight: bold; color: #38bdf8; }
        form { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 20px; background: #1a2333; padding: 15px; border-radius: 8px; border: 1px solid #334155; }
        input, button { padding: 10px; border-radius: 5px; border: none; font-weight: bold; }
        input { background: #334155; color: #fff; flex: 1; }
        button { cursor: pointer; background: #0284c7; color: white; }
        .search-container { margin: 20px 0 10px 0; display: flex; }
        .search-input { width: 100%; padding: 12px; background: #1e293b; border: 2px solid #334155; border-radius: 6px; color: #fff; font-size: 14px; }
        .search-input:focus { border-color: #38bdf8; outline: none; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; background: #0f172a; }
        th, td { padding: 12px; text-align: center; border-bottom: 1px solid #334155; }
        th { background: #1e293b; color: #94a3b8; }
        .btn-backup { background: #10b981; }
        .file-input-label { cursor: pointer; background: #8b5cf6; padding: 10px; border-radius: 5px; font-weight: bold; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="top-bar">
            <h2>⚡ کنترل پنل هوشمند شیشه‌ای SSH PRO</h2>
            <div style="display: flex; gap: 10px;">
                <a href="/backup/download"><button class="btn-backup">📥 دانلود فایل بک‌آپ</button></a>
                <form action="/backup/restore" method="POST" enctype="multipart/form-data" style="margin: 0; padding:0; border:none; display: inline-flex;">
                    <label class="file-input-label">
                        📤 ریستور کل کاربران
                        <input type="file" name="backup_file" onchange="this.form.submit()" style="display: none;">
                    </label>
                </form>
            </div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <h4>📊 وضعیت زنده منابع سرور</h4>
                <div class="val" style="color: #a855f7;">اصلی / فعال</div>
            </div>
            <div class="stat-card">
                <h4>📉 مجموع ترافیک کل کاربران</h4>
                <div id="total-traffic-card" class="val">0.00 GB</div>
            </div>
        </div>
        
        <h3>✨ ساخت اکانت تک‌کاربره جدید</h3>
        <form action="/add" method="POST">
            <input type="text" name="username" placeholder="نام کاربری جدید" required>
            <input type="text" name="password" placeholder="کلمه عبور" required>
            <input type="number" step="0.1" name="limit_gb" placeholder="حجم مجاز (GB)" required>
            <input type="number" name="days" placeholder="مدت اعتبار (روز)" required>
            <button type="submit" style="background: #0ea5e9;">➕ ساخت و فعال‌سازی اکانت</button>
        </form>

        <div class="top-bar" style="margin-top: 30px; margin-bottom: 5px; border: none; padding-bottom: 0;">
            <h3>👥 وضعیت مصرف ترافیک و مانیتورینگ آنلاین کاربران</h3>
        </div>
        
        <div class="search-container">
            <input type="text" id="search-bar" class="search-input" placeholder="🔍 جستجو در نام کاربری یا وضعیت سیستم کلاینت..." oninput="filterUsers()">
        </div>

        <table>
            <thead>
                <tr>
                    <th>نام کاربری</th>
                    <th>کلمه عبور</th>
                    <th>حجم کل (GB)</th>
                    <th>حجم مصرفی واقعی (GB)</th>
                    <th>اعتبار زمانی</th>
                    <th>وضعیت اتصال</th>
                    <th>وضعیت سیستم</th>
                    <th>اقدام سرویس</th>
                </tr>
            </thead>
            <tbody id="user-rows"></tbody>
        </table>
    </div>

    <script>
        let allUsersData = [];

        async function updateData() {
            try {
                const res = await fetch('/api/users');
                const data = await res.json();
                allUsersData = data.users;
                
                // محاسبه مجموع ترافیک کل مصرفی در کارت مدیریت
                let totalConsumed = 0;
                data.users.forEach(u => { totalConsumed += u.used_gb; });
                document.getElementById('total-traffic-card').innerText = totalConsumed.toFixed(3) + " GB";

                renderTable(data.online);
            } catch(e) {}
        }

        function renderTable(onlineList = []) {
            const tbody = document.getElementById('user-rows');
            const searchKeyword = document.getElementById('search-bar').value.trim().toLowerCase();
            tbody.innerHTML = '';

            allUsersData.forEach(user => {
                const usernameLower = user.username.toLowerCase();
                let statusTextRaw = 'فعال';
                if (user.status === 'Expired') statusTextRaw = 'منقضی شده';
                if (user.status === 'Traffic_Limit') statusTextRaw = 'اتمام حجم';

                // فیلترینگ کلاینت‌ساید بر اساس کلمه کلیدی سرچ بار
                if (searchKeyword !== '' && !usernameLower.includes(searchKeyword) && !statusTextRaw.toLowerCase().includes(searchKeyword)) {
                    return; 
                }

                const isOnline = onlineList.map(o => o.trim().toLowerCase()).includes(user.username.trim().toLowerCase());
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
        }

        function filterUsers() {
            // ایجاد فیلترینگ آنی هنگام زدن دکمه کیبورد بدون تداخل با پولینگ
            fetch('/api/users').then(res => res.json()).then(data => {
                renderTable(data.online);
            }).catch(()=>{});
        }

        updateData();
        setInterval(updateData, 2000);
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
        
        ps_output = subprocess.check_output("ps -eo user,command | grep -E 'sshd:'", shell=True).decode()
        online_now = []
        for line in ps_output.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 2:
                u = parts[0].strip()
                if u not in ['root', 'sshd', 'nobody'] and 'net' not in u and u not in online_now:
                    online_now.append(u)
                    
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

@app.route('/backup/download')
def download_backup():
    try:
        with db_lock:
            conn = get_db_connection()
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
        backup_filename = "/tmp/ssh_panel_backup.json"
        with open(backup_filename, "w") as f: json.dump(backup_data, f, indent=4)
        return send_file(backup_filename, as_attachment=True, download_name="ssh_panel_backup.json")
    except: return "Backup Error"

@app.route('/backup/restore', methods=['POST'])
def restore_backup():
    try:
        if 'backup_file' in request.files:
            file = request.files['backup_file']
            if file.filename != '':
                data = json.load(file)
                with db_lock:
                    conn = get_db_connection()
                    cursor = conn.cursor()
                    for item in data:
                        safe_system_user_create(item["username"], item["password"])
                        if item["status"] == "Active":
                            subprocess.run(["sudo", "usermod", "-U", item["username"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        cursor.execute("""
                            INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """, (item["username"], item["password"], item["limit_gb"], item["used_gb"], item["expire_date"], item["status"], item["initial_gb"], item["initial_days"]))
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
        subprocess.run(f"sudo pkill -9 -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        subprocess.run(f"sudo pkill -9 -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except KeyError: pass
    subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)

if __name__ == '__main__':
    init_db()
    threading.Thread(target=live_monitor_daemon, daemon=True).start()
    app.run(host='0.0.0.0', port=5000)
EOF

# ۶. ساخت فایل دیمون لینوکس در مسیر فیکس شده و استاندارد اوبونتو
sudo tee /etc/systemd/system/custom-panel.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=SSH Pro Absolute Calibrated Engine Panel
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

# ۷. لود دیمون‌ها و استارت مجدد سرویس سیستم‌عامل
sudo systemctl daemon-reload
sudo systemctl enable custom-panel.service
sudo systemctl restart custom-panel.service

echo "--------------------------------------------------"
echo "✔ FIREWALLS AND SEARCH ENGINE INJECTED SUCCESSFULLY"
echo "🌐 PANEL ADDRESS: http://144.172.116.73:5000"
echo "--------------------------------------------------"
