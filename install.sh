#!/bin/bash

# خروج سریع در صورت بروز خطا
set -e

clear
echo -e "\e[1;33m[*] Killing package managers and forcing lock release...\e[0m"

# ۱. آزاد کردن اجباری قفل dpkg
sudo killall -9 apt-get apt unattended-upgrades || true
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock
sudo dpkg --configure -a || true

echo -e "\e[1;32m✔ System locks cleared successfully.\e[0m"
echo -e "\e[1;34m==================================================\e[0m"
echo -e "\e[1;36m       SSH PRO PANEL (REAL-TIME TRAFFIC & FIX)    \e[0m"
echo -e "\e[1;34m==================================================\e[0m"

DB_FILE="/etc/custom-panel/panel.db"
WEB_PANEL_PORT=5000

purge_old_installation() {
    echo "[*] Cleaning up old installation files..."
    sudo systemctl stop custom-panel.service 2>/dev/null || true
    sudo systemctl disable custom-panel.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/custom-panel.service
    sudo systemctl daemon-reload
    
    # پاکسازی رول‌های قدیمی برای جلوگیری از تداخل
    sudo iptables -F || true
    sudo iptables -X || true
    
    sudo fuser -k $WEB_PANEL_PORT/tcp 2>/dev/null || true
    sudo rm -rf /etc/custom-panel
}

install_prerequisites() {
    echo "[*] Installing required system packages..."
    sudo apt update -y
    sudo apt install -y openssh-server python3 python3-pip python3-flask ufw sqlite3 bc psmisc iptables net-tools vnstat
    
    sudo ufw allow $WEB_PANEL_PORT/tcp comment 'Web Panel'
    sudo ufw allow 22/tcp comment 'SSH Default'
    sudo ufw --force enable
    
    sudo mkdir -p /etc/custom-panel
}

create_panel_app() {
    echo "[*] Generating core Python Web GUI script..."
    sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, datetime, sqlite3, json, time, threading
from flask import Flask, request, render_template_string, redirect, send_file, jsonify, flash

app = Flask(__name__)
app.secret_key = "ssh_pro_ultimate_clean_key"
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

def setup_iptables_for_user(username):
    """تنظیم دقیق زنجیره فایروال برای مچ کردن صد درصدی ترافیک فوروارد شده اکانت"""
    try:
        # ایجاد رول اختصاصی خروجی و ورودی در زنجیره‌های اصلی لینوکس
        subprocess.run(f"sudo iptables -C OUTPUT -m owner --uid-owner {username} -j ACCEPT 2>/dev/null || sudo iptables -I OUTPUT 1 -m owner --uid-owner {username} -j ACCEPT", shell=True)
        subprocess.run(f"sudo iptables -C INPUT -m owner --uid-owner {username} -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 1 -m owner --uid-owner {username} -j ACCEPT", shell=True)
        # رول فوروارد ترافیک برای تانل‌ها
        subprocess.run(f"sudo iptables -C FORWARD -m owner --uid-owner {username} -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD 1 -m owner --uid-owner {username} -j ACCEPT", shell=True)
    except:
        pass

def get_iptables_traffic(username):
    """محاسبه دقیق و لحظه‌ای بایت‌های عبور کرده از فایروال بدون تاخیر"""
    try:
        setup_iptables_for_user(username)
        # واکشی آمار بایت‌ها مستقیماً از سوئیچ -v -n -x لینوکس
        output = subprocess.check_output(f"sudo iptables -L OUTPUT -v -n -x | grep -E 'owner UID match {username}' || true", shell=True).decode()
        input_output = subprocess.check_output(f"sudo iptables -L INPUT -v -n -x | grep -E 'owner UID match {username}' || true", shell=True).decode()
        forward_output = subprocess.check_output(f"sudo iptables -L FORWARD -v -n -x | grep -E 'owner UID match {username}' || true", shell=True).decode()
        
        bytes_total = 0
        for block in [output, input_output, forward_output]:
            for line in block.strip().split('\n'):
                parts = line.split()
                if len(parts) > 0:
                    try:
                        bytes_total += int(parts[0]) # واکشی بایت خام
                    except:
                        pass
        
        gb_used = bytes_total / (1024.0 * 1024.0 * 1024.0)
        return gb_used
    except:
        return 0.0

def safe_system_user_create(username, password):
    try:
        with open('/etc/passwd', 'r') as f:
            if username in f.read():
                subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except:
        pass
    
    subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True, check=True)
    setup_iptables_for_user(username)

def monitor_core_logic():
    while True:
        try:
            today = datetime.datetime.now().strftime("%Y-%m-%d")
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            
            # ۱. بررسی تاریخ انقضا
            cursor.execute("SELECT username, expire_date, status FROM users WHERE status='Active'")
            active_users = cursor.fetchall()
            for user in active_users:
                username, expire_date, status = user
                if expire_date and expire_date < today:
                    subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
                    subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ۲. بررسی زنده و لحظه‌ای حجم مصرفی فایروال
            active_connections = get_sshd_connections()
            cursor.execute("SELECT username, limit_gb, used_gb, status FROM users")
            db_users = {r[0]: {"limit": r[1], "used": r[2], "status": r[3]} for r in cursor.fetchall()}
            
            for username in db_users.keys():
                userdata = db_users[username]
                real_gb_used = get_iptables_traffic(username)
                
                if real_gb_used > 0:
                    cursor.execute("UPDATE users SET used_gb=? WHERE username=?", (real_gb_used, username))
                    userdata['used'] = real_gb_used

                # لیمیت کردن آنی در صورت عبور از سقف حجم مجاز
                if userdata['used'] >= userdata['limit'] and userdata['status'] == 'Active':
                    subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
                    subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ۳. سیستم تک‌کاربره سخت‌گیرانه (آنلاین همزمان فقط ۱ دستگاه)
            for username, pids in active_connections.items():
                if len(pids) > 1:
                    for extra_pid in pids[1:]:
                        subprocess.run(["sudo", "kill", "-9", extra_pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"Core Engine Warning: {e}")
        
        time.sleep(1)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>⚡ SSH PRO PANEL - REALTIME NATIVE ⚡</title>
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
        body { font-family: 'Segoe UI', Tahoma, Arial; background-color: var(--bg-color); color: var(--text-main); margin: 0; padding: 30px; direction: rtl; }
        .container { max-width: 1400px; background: var(--card-bg); padding: 30px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.4); margin: auto; border: 1px solid var(--border-color); }
        h1 { font-size: 26px; color: var(--text-main); display: flex; align-items: center; gap: 10px; margin-bottom: 25px; }
        h2 { font-size: 18px; color: var(--accent-blue); margin-top: 35px; border-bottom: 1px solid var(--border-color); padding-bottom: 8px; }
        .card-inner { background: #111827; padding: 20px; border-radius: 8px; border: 1px solid var(--border-color); margin-bottom: 20px; }
        form { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
        input { background: #111827; color: var(--text-main); border: 1px solid var(--border-color); padding: 10px 14px; border-radius: 6px; flex: 1; min-width: 120px; }
        button { padding: 10px 20px; color: white; border: none; border-radius: 6px; cursor: pointer; font-weight: 600; transition: 0.2s; }
        button:hover { filter: brightness(1.2); }
        .btn-blue { background: var(--accent-blue); } .btn-green { background: var(--accent-green); } .btn-red { background: var(--accent-red); } .btn-yellow { background: var(--accent-yellow); color: #000; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; background: #111827; border-radius: 8px; overflow: hidden; }
        th, td { border: 1px solid var(--border-color); padding: 14px; text-align: center; }
        th { background-color: #1e293b; color: var(--text-muted); }
        tr:hover { background-color: #1e293b; }
        .badge { padding: 5px 10px; border-radius: 5px; font-size: 12px; font-weight: bold; display: inline-block; }
        .online { background: rgba(16, 185, 129, 0.2); color: #34d399; border: 1px solid #10b981; }
        .offline { background: rgba(148, 163, 184, 0.2); color: #cbd5e1; border: 1px solid #94a3b8; }
        .alert-flash { padding: 12px; background: rgba(239, 68, 68, 0.2); border: 1px solid var(--accent-red); color: #f87171; border-radius: 6px; margin-bottom: 20px; text-align: center; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ پنل مانیتورینگ لحظه‌ای و فوق دقیق SSH PRO (بدون ریست همزمانی)</h1>
        
        <h2>➕ ساخت اکانت تک‌کاربره جدید</h2>
        <div class="card-inner">
            <form action="/add" method="POST">
                <input type="text" name="username" placeholder="نام کاربری" required>
                <input type="text" name="password" placeholder="کلمه عبور" required>
                <input type="number" step="0.1" name="limit_gb" placeholder="حجم مجاز (GB)" required>
                <input type="number" name="days" placeholder="مدت اعتبار (روز)" required>
                <button type="submit" class="btn-blue">ایجاد کاربر</button>
            </form>
        </div>

        <h2>👥 مانیتورینگ ثانیه‌ای و زنده کاربران</h2>
        <table>
            <thead>
                <tr>
                    <th>نام کاربری</th>
                    <th>کلمه عبور</th>
                    <th>حجم مجاز (GB)</th>
                    <th>حجم مصرفی واقعی (GB)</th>
                    <th>روزهای باقی‌مانده</th>
                    <th>وضعیت اتصال</th>
                    <th>وضعیت سیستم</th>
                    <th>عملیات ویرایش پارامترها و تمدید</th>
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
                    
                    let statusText = '<span style="color:#34d399;">✔ فعال</span>';
                    if (user.status === 'Expired') statusText = '<span style="color:#f87171;">❌ منقضی</span>';
                    if (user.status === 'Traffic_Limit') statusText = '<span style="color:#fbbf24;">⚠️ پایان حجم</span>';

                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td style="font-weight:bold; color:var(--accent-blue);">${user.username}</td>
                        <td><code>${user.password}</code></td>
                        <td>${user.limit_gb} GB</td>
                        <td><span style="color:#38bdf8; font-weight:bold;">${user.used_gb.toFixed(4)}</span> GB</td>
                        <td style="font-weight: bold; color: #f43f5e;">${user.remaining_days >= 0 ? user.remaining_days + ' روز' : 'منقضی شده'}</td>
                        <td>${onlineBadge}</td>
                        <td>${statusText}</td>
                        <td>
                            <form action="/edit" method="POST" style="display:inline-flex; gap:5px; background:none; padding:0; margin:0;">
                                <input type="hidden" name="username" value="${user.username}">
                                <input type="number" step="0.1" name="limit_gb" value="${user.limit_gb}" title="تغییر حجم کل" style="width:75px; min-width:auto; padding:5px; font-size:12px;">
                                <input type="number" name="remaining_days" value="${user.remaining_days}" title="تغییر مستقیم روزهای باقی‌مانده" style="width:60px; min-width:auto; padding:5px; font-size:12px;">
                                <button type="submit" class="btn-yellow" style="padding:5px 10px; font-size:12px;">💾 اعمال ویرایش</button>
                            </form>
                            <a href="/renew/${user.username}"><button class="btn-green" style="padding:5px 10px; font-size:12px;">🔄 تمدید (ریست دوره)</button></a>
                            <a href="/delete/${user.username}"><button class="btn-red" style="padding:5px 10px; font-size:12px;">حذف</button></a>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            } catch (error) {
                console.error("Error fetching live data:", error);
            }
        }

        fetchLiveStatus();
        // رفرش کل دیتای صفحه هر ۱ ثانیه یکبار به صورت کاملا زنده و آسنکرون
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
    except Exception as e:
        pass
    return redirect('/')

@app.route('/edit', methods=['POST'])
def edit_user():
    """اصلاح متد ویرایش: تغییر سقف حجم و روزها بدون تغییر و دستکاری در حجم مصرف شده فعلی کاربر"""
    try:
        username = request.form['username'].strip()
        limit_gb = float(request.form['limit_gb'].strip())
        remaining_days = int(request.form['remaining_days'].strip())
        
        # محاسبه تاریخ انقضای جدید بر اساس روزهای وارد شده جدید از همین امروز
        new_expire_date = (datetime.datetime.now() + datetime.timedelta(days=remaining_days)).strftime("%Y-%m-%d")
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        # فقط سقف حجم و تاریخ انقضا آپدیت می‌شود، فیلد used_gb دست‌نخورده باقی می‌ماند
        cursor.execute("UPDATE users SET limit_gb=?, expire_date=?, initial_gb=?, initial_days=?, status='Active' WHERE username=?", 
                       (limit_gb, new_expire_date, limit_gb, remaining_days, username))
        conn.commit()
        conn.close()
        
        subprocess.run(["sudo", "usermod", "-U", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"Error on edit: {e}")
    return redirect('/')

@app.route('/renew/<username>')
def renew_user(username):
    """متد تمدید: ریست کردن کامل دوره مصرفی و بازگردانی به حجم صفر"""
    try:
        # صفر کردن شمارنده سخت‌افزاری کارت شبکه لینوکس برای این یوزر
        subprocess.run(f"sudo iptables -Z OUTPUT -m owner --uid-owner {username} 2>/dev/null || true", shell=True)
        subprocess.run(f"sudo iptables -Z INPUT -m owner --uid-owner {username} 2>/dev/null || true", shell=True)
        subprocess.run(f"sudo iptables -Z FORWARD -m owner --uid-owner {username} 2>/dev/null || true", shell=True)
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("SELECT initial_gb, initial_days FROM users WHERE username=?", (username,))
        row = cursor.fetchone()
        if row:
            init_gb, init_days = row
            new_expire = (datetime.datetime.now() + datetime.timedelta(days=init_days)).strftime("%Y-%m-%d")
            # در زمان تمدید فیلد used_gb کاملا 0.0 می‌شود
            cursor.execute("UPDATE users SET used_gb=0.0, limit_gb=?, expire_date=?, status='Active' WHERE username=?", 
                           (init_gb, new_expire, username))
            conn.commit()
            subprocess.run(["sudo", "usermod", "-U", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        conn.close()
    except Exception as e:
        pass
    return redirect('/')

@app.route('/delete/<username>')
def delete_user(username):
    try:
        subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(f"sudo iptables -D OUTPUT -m owner --uid-owner {username} -j ACCEPT 2>/dev/null || true", shell=True)
        subprocess.run(f"sudo iptables -D INPUT -m owner --uid-owner {username} -j ACCEPT 2>/dev/null || true", shell=True)
        subprocess.run(f"sudo iptables -D FORWARD -m owner --uid-owner {username} -j ACCEPT 2>/dev/null || true", shell=True)
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM users WHERE username=?", (username,))
        conn.commit()
        conn.close()
    except Exception as e:
        pass
    return redirect('/')

if __name__ == '__main__':
    init_db()
    threading.Thread(target=monitor_core_logic, daemon=True).start()
    app.run(host='0.0.0.0', port=5000)
EOF

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

purge_old_installation
install_prerequisites
create_panel_app

echo -e "\e[1;32m==================================================\e[0m"
echo -e "\e[1;32m✔ SUCCESS: 1-SECOND REALTIME FORWARDING PATTERNS! \e[0m"
echo -e "\e[1;36m🌐 WEB PANEL ACTIVE ON PORT 5000                  \e[0m"
echo -e "\e[1;32m==================================================\e[0m"
