#!/bin/bash

# خروج سریع در صورت بروز خطای پیش‌بینی نشده
set -e

clear
echo -e "\e[1;33m[*] Killing package managers and forcing lock release...\e[0m"

# ۱. آزاد کردن اجباری قفل dpkg و بستن پروسس‌های مزاحم سیستم‌عامل
sudo killall -9 apt-get apt unattended-upgrades || true
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock
sudo dpkg --configure -a || true

echo -e "\e[1;32m✔ System locks cleared successfully.\e[0m"
echo -e "\e[1;34m==================================================\e[0m"
echo -e "\e[1;36m    SSH PRO PANEL (ANTI-CRASH & OPTIMIZED V4)    \e[0m"
echo -e "\e[1;34m==================================================\e[0m"

# ۲. ایجاد مکث ۳ ثانیه‌ای به صورت شمارش معکوس زنده
for i in {3..1}; do
    echo -e "\e[1;35m⏳ Starting installation in $i seconds...\e[0m"
    sleep 1
done

echo -e "\e[1;32m🚀 Launching installation now...\e[0m"
echo -e "\e[1;34m==================================================\e[0m"

DB_FILE="/etc/custom-panel/panel.db"
WEB_PANEL_PORT=5000

purge_old_installation() {
    echo "[*] Cleaning up and purging previous installation files..."
    
    # متوقف کردن و حذف سرویس‌های قبلی
    sudo systemctl stop custom-panel.service 2>/dev/null || true
    sudo systemctl disable custom-panel.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/custom-panel.service
    sudo systemctl daemon-reload
    
    # کشتن پروسس‌های باقی‌مانده پایتون روی پورت پنل
    sudo fuser -k $WEB_PANEL_PORT/tcp 2>/dev/null || true
    
    # حذف دیتابیس قدیمی برای نصب کاملاً از نو و تمیز
    sudo rm -rf /etc/custom-panel
}

install_prerequisites() {
    echo "[*] Extra safety check: ensuring updates timers are quiet..."
    sudo systemctl stop unattended-upgrades 2>/dev/null || true
    sudo systemctl stop apt-daily.timer 2>/dev/null || true
    sudo systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
    
    echo "[*] Installing required system packages..."
    sudo apt update -y
    sudo apt install -y openssh-server python3 python3-pip python3-flask ufw sqlite3 bc psmisc
    
    # تنظیم فایروال سرور
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

def get_online_users():
    try:
        output = subprocess.check_output("w -h | awk '{print $1}'", shell=True).decode()
        return list(set(output.strip().split('\n')))
    except:
        return []

def safe_system_user_create(username, password):
    # حل ارور وضعیت ۹ لینوکس: اگر کاربر از قبل در لینوکس وجود داشت ابتدا آن را کاملاً حذف کن
    try:
        with open('/etc/passwd', 'r') as f:
            if username in f.read():
                subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except:
        pass
    
    # ساخت بدون مشکل کاربر
    subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True, check=True)

def background_monitor():
    while True:
        try:
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            cursor.execute("SELECT username, limit_gb, expire_date FROM users WHERE status='Active'")
            active_users = cursor.fetchall()
            
            today = datetime.datetime.now().strftime("%Y-%m-%d")
            online_list = get_online_users()

            # مدیریت اتصال همزمان (تک کاربره)
            for user in set(online_list):
                if user:
                    try:
                        count = int(subprocess.check_output(f"ps -u {user} | grep -E 'sshd|ssh' | wc -l", shell=True).decode().strip())
                        if count > 2: 
                            subprocess.run(f"sudo killall -u {user}", shell=True)
                    except:
                        pass

            for user in active_users:
                username, limit, expire_date = user
                if expire_date and expire_date < today:
                    subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
                    continue
                
                cursor.execute("SELECT used_gb FROM users WHERE username=?", (username,))
                res = cursor.fetchone()
                if res:
                    used = res[0]
                    if used and limit and used >= limit:
                        subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
            
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"Monitor Warning: {e}")
        
        # بهینه‌سازی شده از ۱۵ به ۶۰ ثانیه برای جلوگیری از قطع شدن سرور و کاهش ترافیک پردازنده
        time.sleep(60)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>⚡ SSH PRO PANEL - LIVE & ASYNC ⚡</title>
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
        .container { max-width: 1300px; background: var(--card-bg); padding: 30px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.4); margin: auto; border: 1px solid var(--border-color); }
        h1 { font-size: 26px; color: var(--text-main); display: flex; align-items: center; gap: 10px; margin-bottom: 25px; }
        h2 { font-size: 18px; color: var(--accent-blue); margin-top: 35px; border-bottom: 1px solid var(--border-color); padding-bottom: 8px; }
        .grid-header { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 25px; }
        .card-inner { background: #111827; padding: 20px; border-radius: 8px; border: 1px solid var(--border-color); }
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
        <h1>⚡ پنل مدیریت هوشمند SSH PRO (نسخه ضد کرش و بهینه شده)</h1>
        
        {% with messages = get_flashed_messages() %}
          {% if messages %}
            {% for message in messages %}
              <div class="alert-flash">⚠️ سیستم: {{ message }}</div>
            {% endfor %}
          {% endif %}
        {% endwith %}
        
        <div class="grid-header">
            <div class="card-inner">
                <h3 style="margin-top:0; color:var(--accent-green);">📥 پشتیبان‌گیری دیتابیس</h3>
                <a href="/backup/download"><button class="btn-green" style="width:100%;">دانلود فایل بک‌آپ پنل (.json)</button></a>
            </div>
            <div class="card-inner">
                <h3 style="margin-top:0; color:var(--accent-red);">📤 بازگردانی دیتابیس</h3>
                <form action="/backup/restore" method="POST" enctype="multipart/form-data" style="flex-direction: column; align-items: stretch; gap: 8px;">
                    <input type="file" name="backup_file" accept=".json" required style="padding:6px;">
                    <button type="submit" class="btn-red">شروع عملیات ریستور</button>
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

        <h2>👥 مانیتورینگ زنده کاربران (بروزرسانی خودکار هر ۳ ثانیه)</h2>
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
                    <th>عملیات مدیریت</th>
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
                        <td><span style="color:#38bdf8;">${user.used_gb.toFixed(2)}</span> GB</td>
                        <td style="font-weight: bold; color: #f43f5e;">${user.remaining_days >= 0 ? user.remaining_days + ' روز' : 'منقضی شده'}</td>
                        <td>${onlineBadge}</td>
                        <td>${statusText}</td>
                        <td>
                            <form action="/edit" method="POST" style="display:inline-flex; gap:5px; background:none; padding:0;">
                                <input type="hidden" name="username" value="${user.username}">
                                <input type="number" step="0.1" name="limit_gb" value="${user.limit_gb}" style="width:65px; min-width:auto; padding:4px; font-size:12px;">
                                <input type="number" name="add_days" value="${user.initial_days}" style="width:55px; min-width:auto; padding:4px; font-size:12px;">
                                <button type="submit" class="btn-yellow" style="padding:4px 8px; font-size:12px;">ویرایش</button>
                            </form>
                            <a href="/renew/${user.username}"><button class="btn-green" style="padding:4px 8px; font-size:12px;">🔄 تمدید</button></a>
                            <a href="/delete/${user.username}"><button class="btn-red" style="padding:4px 8px; font-size:12px;">حذف</button></a>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            } catch (error) {
                console.error("Error fetching live data:", error);
            }
        }

        fetchLiveStatus();
        setInterval(fetchLiveStatus, 3000);
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
        
        # استفاده از متد ساخت امن لینوکس جدید بدون تداخل وضعیت ۹
        safe_system_user_create(username, password)
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days) VALUES (?, ?, ?, 0.0, ?, 'Active', ?, ?)",
                       (username, password, limit_gb, expire_date, limit_gb, days))
        conn.commit()
        conn.close()
    except Exception as e:
        flash(str(e))
    return redirect('/')

@app.route('/edit', methods=['POST'])
def edit_user():
    try:
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
    except Exception as e:
        flash(str(e))
    return redirect('/')

@app.route('/renew/<username>')
def renew_user(username):
    try:
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
    except Exception as e:
        flash(str(e))
    return redirect('/')

@app.route('/delete/<username>')
def delete_user(username):
    try:
        subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM users WHERE username=?", (username,))
        conn.commit()
        conn.close()
    except Exception as e:
        flash(str(e))
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
        backup_filename = f"/tmp/ssh_premium_backup.json"
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
            
            # پاکسازی کامل تداخل های سیستمی قبل از ریستور
            try:
                subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                pass
                
            subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True, check=True)
            if status != 'Active':
                subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                
            cursor.execute('''
                INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (username, password, limit_gb, used_gb, expire_date, status, init_gb, init_days))
        conn.commit()
        conn.close()
    except Exception as e:
        flash(str(e))
    return redirect('/')

if __name__ == '__main__':
    init_db()
    threading.Thread(target=background_monitor, daemon=True).start()
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
echo -e "\e[1;32m✔ SUCCESS: PANEL COMPLETELY PURGED & REINSTALLED!  \e[0m"
echo -e "\e[1;36m🌐 Web UI Port: 5000                               \e[0m"
echo -e "\e[1;32m==================================================\e[0m"
