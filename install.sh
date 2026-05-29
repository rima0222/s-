#!/bin/bash

# غیرفعال کردن خروج اضطراری برای بخش‌های نوسانی جهت تضمین عدم کرش
set +e

clear
echo -e "\e[1;33m[*] Restoring to Stable Core & Adding Live Resource Monitor...\e[0m"

# آزاد کردن قفل‌های احتمالی سیستم‌عامل
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null
sudo dpkg --configure -a 2>/dev/null

DB_FILE="/etc/custom-panel/panel.db"
WEB_PANEL_PORT=5000

update_and_replace_logic() {
    echo "[*] Cleaning up port 5000 gracefully..."
    sudo fuser -k $WEB_PANEL_PORT/tcp 2>/dev/null
    sudo mkdir -p /etc/custom-panel
}

install_prerequisites() {
    echo "[*] Checking Linux dependencies..."
    set -e
    sudo apt update -y
    sudo apt install -y openssh-server python3 python3-pip python3-flask ufw sqlite3 bc psmisc net-tools
    set +e
}

create_panel_app() {
    echo "[*] Injecting Optimized Premium Web Panel..."
    sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, datetime, sqlite3, json, time, threading
from flask import Flask, request, render_template_string, redirect, send_file, jsonify, flash

app = Flask(__name__)
app.secret_key = "ssh_pro_glass_premium_key_v8"
DB_FILE = "/etc/custom-panel/panel.db"
TRAFFIC_TRACKER = {}

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

def get_system_resources():
    """محاسبه دقیق و لایو میزان مصرف CPU و RAM سرور"""
    cpu = 0.0
    ram = 0.0
    try:
        # محاسبه مصرف CPU
        cpu_output = subprocess.check_output("top -bn1 | grep 'Cpu(s)'", shell=True).decode()
        idle = float(cpu_output.split()[7].replace(',', '.'))
        cpu = 100.0 - idle
    except:
        pass
    try:
        # محاسبه مصرف RAM
        ram_output = subprocess.check_output("free | grep Mem:", shell=True).decode().split()
        total_ram = float(ram_output[1])
        used_ram = float(ram_output[2])
        ram = (used_ram / total_ram) * 100.0
    except:
        pass
    return round(cpu, 1), round(ram, 1)

def update_traffic_from_proc():
    global TRAFFIC_TRACKER
    while True:
        try:
            active_connections = get_sshd_connections()
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            
            for username, pids in active_connections.items():
                for pid in pids:
                    net_file = f"/proc/{pid}/net/dev"
                    if os.path.exists(net_file):
                        try:
                            with open(net_file, "r") as f:
                                lines = f.readlines()
                            bytes_sum = 0
                            for line in lines:
                                if ":" in line:
                                    parts = line.split()
                                    bytes_sum += int(parts[1]) + int(parts[9])
                            
                            if username not in TRAFFIC_TRACKER:
                                TRAFFIC_TRACKER[username] = {"last_bytes": bytes_sum}
                                continue
                            
                            diff = bytes_sum - TRAFFIC_TRACKER[username]["last_bytes"]
                            if diff > 0:
                                calibrated_bytes = diff * 0.68
                                diff_gb = calibrated_bytes / (1024.0 * 1024.0 * 1024.0)
                                cursor.execute("UPDATE users SET used_gb = used_gb + ? WHERE username = ?", (diff_gb, username))
                            
                            TRAFFIC_TRACKER[username]["last_bytes"] = bytes_sum
                        except:
                            pass
            conn.commit()
            conn.close()
        except:
            pass
        time.sleep(2)

def monitor_core_logic():
    while True:
        try:
            today = datetime.datetime.now().strftime("%Y-%m-%d")
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            
            # ۱. بررسی انقضای تاریخ دوره
            cursor.execute("SELECT username, expire_date, status FROM users WHERE status='Active'")
            active_users = cursor.fetchall()
            for user in active_users:
                username, expire_date, status = user
                if expire_date and expire_date < today:
                    subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
                    subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ۲. مانیتور ترافیک مصرفی
            cursor.execute("SELECT username, limit_gb, used_gb, status FROM users")
            for row in cursor.fetchall():
                username, limit_gb, used_gb, status = row
                if used_gb >= limit_gb and status == 'Active':
                    subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
                    subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ۳. قطع ارتباط فوری مولتی لوگین (تک کاربره فوق سخت‌گیرانه لایو)
            active_connections = get_sshd_connections()
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
    <title>⚡ SSH PRO - GLASS UI PREMIUM ⚡</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Vazirmatn:wght@300;400;700&display=swap');
        
        :root {
            --accent-blue: #007aff;
            --accent-green: #34c759;
            --accent-red: #ff3b30;
            --accent-yellow: #ffcc00;
            --text-main: #ffffff;
            --text-muted: #a1a1aa;
        }
        
        body { 
            font-family: 'Vazirmatn', sans-serif; 
            background: linear-gradient(135deg, #0f172a 0%, #1e1e2f 100%);
            background-attachment: fixed;
            color: var(--text-main); 
            margin: 0; 
            padding: 40px 20px; 
            direction: rtl; 
        }
        
        .container { 
            max-width: 1400px; 
            background: rgba(30, 41, 59, 0.45); 
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            padding: 35px; 
            border-radius: 24px; 
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5); 
            margin: auto; 
            border: 1px solid rgba(255, 255, 255, 0.08); 
        }
        
        h1 { font-size: 26px; font-weight: 700; color: #fff; margin-bottom: 30px; display: flex; align-items: center; gap: 10px; }
        h2 { font-size: 18px; font-weight: 700; color: var(--accent-blue); margin-top: 40px; margin-bottom: 15px; }
        
        .grid-header { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; margin-bottom: 30px; }
        
        .card-inner { 
            background: rgba(15, 23, 42, 0.4); 
            backdrop-filter: blur(10px);
            padding: 22px; 
            border-radius: 16px; 
            border: 1px solid rgba(255, 255, 255, 0.05); 
            display: flex;
            flex-direction: column;
            justify-content: center;
        }
        
        /* استایل مانیتورینگ منابع سیستم */
        .resource-box { display: flex; justify-content: space-around; align-items: center; text-align: center; padding: 10px 0; }
        .circle-progress { width: 90px; height: 90px; border-radius: 50%; background: conic-gradient(var(--accent-blue) 0%, rgba(255,255,255,0.08) 0%); display: flex; align-items: center; justify-content: center; position: relative; transition: all 0.5s ease; }
        .circle-progress::before { content: ''; position: absolute; width: 76px; height: 76px; background: #151f32; border-radius: 50%; }
        .circle-text { position: relative; z-index: 10; font-weight: 700; font-size: 14px; color: #fff; }

        form { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
        
        input { 
            background: rgba(255, 255, 255, 0.07); 
            color: #fff; 
            border: 1px solid rgba(255, 255, 255, 0.1); 
            padding: 12px 16px; 
            border-radius: 12px; 
            flex: 1; 
            min-width: 140px; 
            font-family: 'Vazirmatn';
            font-size: 14px;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }
        input:focus { 
            background: rgba(255, 255, 255, 0.12);
            border-color: var(--accent-blue); 
            outline: none; 
        }
        
        button { 
            padding: 12px 24px; 
            color: white; 
            border: none; 
            border-radius: 12px; 
            cursor: pointer; 
            font-weight: 700; 
            font-family: 'Vazirmatn';
            font-size: 14px;
            transition: all 0.2s ease; 
        }
        button:hover { filter: brightness(1.15); transform: scale(1.02); }
        .btn-blue { background: var(--accent-blue); } 
        .btn-green { background: var(--accent-green); } 
        .btn-red { background: var(--accent-red); }
        
        .search-container {
            margin-bottom: 20px;
            display: flex;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 14px;
            padding: 4px;
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        .search-container input { background: transparent; border: none; padding: 14px; }
        .search-container input:focus { background: transparent; box-shadow: none; outline: none; }

        table { width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 15px; background: rgba(15, 23, 42, 0.3); border-radius: 16px; overflow: hidden; border: 1px solid rgba(255, 255, 255, 0.05); }
        th, td { padding: 16px; text-align: center; font-size: 14px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); }
        th { background-color: rgba(0, 0, 0, 0.2); color: var(--text-muted); font-weight: 700; }
        tr:last-child td { border-bottom: none; }
        tr:hover { background-color: rgba(255, 255, 255, 0.03); }
        
        .badge { padding: 6px 12px; border-radius: 8px; font-size: 12px; font-weight: 700; display: inline-block; }
        .online { background: rgba(52, 199, 89, 0.15); color: #34c759; border: 1px solid rgba(52, 199, 89, 0.3); }
        .offline { background: rgba(161, 161, 170, 0.15); color: #cbd5e1; border: 1px solid rgba(161, 161, 170, 0.3); }
        
        .alert-success { padding: 14px; background: rgba(52, 199, 89, 0.15); border: 1px solid var(--accent-green); color: #34c759; border-radius: 12px; margin-bottom: 25px; text-align: center; font-weight: 700; }
        .alert-danger { padding: 14px; background: rgba(255, 59, 48, 0.15); border: 1px solid var(--accent-red); color: #ff3b30; border-radius: 12px; margin-bottom: 25px; text-align: center; font-weight: 700; }
        
        .progress-wrapper { width: 230px; text-align: right; margin: auto; }
        .progress-text { display: flex; justify-content: space-between; font-size: 12px; color: #a1a1aa; margin-bottom: 5px; }
        .progress-container { width: 100%; background-color: rgba(255,255,255,0.08); border-radius: 10px; height: 7px; overflow: hidden; }
        .progress-bar { height: 100%; width: 100%; border-radius: 10px; transition: width 0.6s ease, background-color 0.4s ease; }
        code { background: rgba(255,255,255,0.08); padding: 4px 8px; border-radius: 6px; color: #64d2ff; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ کنترل پنل هوشمند شیشه‌ای SSH PRO</h1>
        
        {% with messages = get_flashed_messages(with_categories=true) %}
          {% if messages %}
            {% for category, message in messages %}
              <div class="alert-{{ category }}">📢 {{ message }}</div>
            {% endfor %}
          {% endif %}
        {% endwith %}

        <div class="grid-header">
            <div class="card-inner">
                <h3 style="margin-top:0; font-size:15px; color:var(--accent-blue); text-align: center; margin-bottom: 12px;">📊 وضعیت زنده منابع سرور</h3>
                <div class="resource-box">
                    <div>
                        <div class="circle-progress" id="cpu-circle">
                            <div class="circle-text" id="cpu-text">0%</div>
                        </div>
                        <div style="font-size:12px; margin-top:8px; color:var(--text-muted);">CPU Usage</div>
                    </div>
                    <div>
                        <div class="circle-progress" id="ram-circle" style="background: conic-gradient(var(--accent-yellow) 0%, rgba(255,255,255,0.08) 0%);">
                            <div class="circle-text" id="ram-text">0%</div>
                        </div>
                        <div style="font-size:12px; margin-top:8px; color:var(--text-muted);">RAM Usage</div>
                    </div>
                </div>
            </div>

            <div class="card-inner" style="text-align: center;">
                <h3 style="margin-top:0; font-size:15px; color:#64d2ff;">📈 مجموع ترافیک کل کاربران</h3>
                <div style="font-size: 28px; font-weight: 700; margin: 10px 0; color: #fff;">
                    <span id="total-server-usage">0.000</span> <span style="font-size:16px; color:var(--text-muted);">GB</span>
                </div>
                <p style="color:var(--text-muted); font-size:12px; margin: 0;">مجموع ترافیک دانلود و آپلود واقعی کالیبره شده کلاینت‌ها</p>
            </div>

            <div class="card-inner">
                <h3 style="margin-top:0; font-size:14px; color:var(--accent-green);">📥 پشتیبان‌گیری دیتابیس</h3>
                <p style="color:var(--text-muted); font-size:12px; margin-bottom:12px;">استخراج خروجی زنده JSON از اطلاعات کلاینت‌ها.</p>
                <a href="/backup/download"><button class="btn-green" style="width:100%; padding: 10px;">📥 دانلود فایل بک‌آب</button></a>
            </div>
            <div class="card-inner">
                <h3 style="margin-top:0; font-size:14px; color:var(--accent-red);">📤 بازگردانی دیتابیس</h3>
                <form action="/backup/restore" method="POST" enctype="multipart/form-data" style="flex-direction: column; align-items: stretch; gap: 6px;">
                    <input type="file" name="backup_file" accept=".json" required style="padding: 6px;">
                    <button type="submit" class="btn-red" style="padding: 10px;">📤 ریستور کل کاربران</button>
                </form>
            </div>
        </div>
        
        <h2>✨ ساخت اکانت تک‌کاربره جدید</h2>
        <div class="card-inner">
            <form action="/add" method="POST">
                <input type="text" name="username" placeholder="نام کاربری جدید" required>
                <input type="text" name="password" placeholder="کلمه عبور" required>
                <input type="number" step="0.1" name="limit_gb" placeholder="حجم مجاز (GB)" required>
                <input type="number" name="days" placeholder="مدت اعتبار (روز)" required>
                <button type="submit" class="btn-blue">➕ ساخت و فعال‌سازی اکانت</button>
            </form>
        </div>

        <h2>👥 وضعیت مصرف ترافیک و مانیتورینگ آنلاین کاربران</h2>
        
        <div class="search-container">
            <input type="text" id="search-input" onkeyup="filterUsers()" placeholder="🔍 جستجو در نام کاربری یا وضعیت کلاینت...">
        </div>

        <table>
            <thead>
                <tr>
                    <th>نام کاربری</th>
                    <th>کلمه عبور</th>
                    <th>حجم کل (GB)</th>
                    <th>حجم مصرفی واقعی (GB)</th>
                    <th>وضعیت نوار حجم مجاز</th>
                    <th>اعتبار زمانی</th>
                    <th>وضعیت اتصال</th>
                    <th>وضعیت سیستم</th>
                    <th>اقدام سرویس</th>
                </tr>
            </thead>
            <tbody id="user-table-body">
                </tbody>
        </table>
    </div>

    <script>
        function filterUsers() {
            const input = document.getElementById('search-input');
            const filter = input.value.toLowerCase();
            const tbody = document.getElementById('user-table-body');
            const trs = tbody.getElementsByTagName('tr');

            for (let i = 0; i < trs.length; i++) {
                const tdUsername = trs[i].getElementsByTagName('td')[0];
                if (tdUsername) {
                    const txtValue = tdUsername.textContent || tdUsername.innerText;
                    if (txtValue.toLowerCase().indexOf(filter) > -1) {
                        trs[i].style.display = "";
                    } else {
                        trs[i].style.display = "none";
                    }
                }
            }
        }

        async function fetchLiveStatus() {
            try {
                const response = await fetch('/api/live_data');
                const data = await response.json();
                
                // بروزرسانی دایره‌های سیستم ریسورس
                const cpuCircle = document.getElementById('cpu-circle');
                cpuCircle.style.background = `conic-gradient(var(--accent-blue) ${data.cpu}%, rgba(255,255,255,0.08) ${data.cpu}%)`;
                document.getElementById('cpu-text').innerText = data.cpu + '%';

                const ramCircle = document.getElementById('ram-circle');
                ramCircle.style.background = `conic-gradient(var(--accent-yellow) ${data.ram}%, rgba(255,255,255,0.08) ${data.ram}%)`;
                document.getElementById('ram-text').innerText = data.ram + '%';

                // بروزرسانی ترافیک کل مصرف شده در باکس کناری جدول
                document.getElementById('total-server-usage').innerText = data.total_server_usage.toFixed(3);

                const tbody = document.getElementById('user-table-body');
                const searchInput = document.getElementById('search-input').value.toLowerCase();
                tbody.innerHTML = '';

                data.users.forEach(user => {
                    const isOnline = data.online_users.includes(user.username);
                    const onlineBadge = isOnline 
                        ? '<span class="badge online">● آنلاین</span>' 
                        : '<span class="badge offline">○ آفلاین</span>';
                    
                    let statusText = '<span style="color:#34c759; font-weight:700;">فعال</span>';
                    if (user.status === 'Expired') statusText = '<span style="color:#ff3b30; font-weight:700;">منقضی زمان</span>';
                    if (user.status === 'Traffic_Limit') statusText = '<span style="color:#ffcc00; font-weight:700;">اتمام حجم</span>';

                    const totalGb = user.limit_gb;
                    const usedGb = user.used_gb;
                    let remainingGb = totalGb - usedGb;
                    if (remainingGb < 0) remainingGb = 0;
                    
                    let remainingPercent = totalGb > 0 ? (remainingGb / totalGb) * 100 : 0;
                    
                    let barColor = 'var(--accent-green)'; 
                    if (remainingPercent <= 50 && remainingPercent > 20) {
                        barColor = 'var(--accent-yellow)'; 
                    } else if (remainingPercent <= 20) {
                        barColor = 'var(--accent-red)'; 
                    }

                    const tr = document.createElement('tr');
                    if (searchInput && !user.username.toLowerCase().includes(searchInput)) {
                        tr.style.display = "none";
                    }

                    tr.innerHTML = `
                        <td style="font-weight:700; color:#007aff;">${user.username}</td>
                        <td><code>${user.password}</code></td>
                        <td style="font-weight:700; color:#cbd5e1;">${totalGb} GB</td>
                        <td><span style="color:#64d2ff; font-weight:700;">${usedGb.toFixed(3)}</span> GB</td>
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
                        <td style="font-weight: 700; color: #ff3b30;">${user.remaining_days >= 0 ? user.remaining_days + ' روز' : 'پایان دوره'}</td>
                        <td>${onlineBadge}</td>
                        <td>${statusText}</td>
                        <td>
                            <a href="/renew/${user.username}"><button class="btn-green" style="padding:6px 14px; font-size:12px; border-radius:8px;">🔄 ریست دوره</button></a>
                            <a href="/delete/${user.username}"><button class="btn-red" style="padding:6px 14px; font-size:12px; border-radius:8px;">حذف</button></a>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            } catch (error) {
                console.error("Interface Error:", error);
            }
        }
        fetchLiveStatus();
        setInterval(fetchLiveStatus, 1500);
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
        
        # محاسبه مجموع ترافیک کل کلاینت‌ها به صورت یکجا
        cursor.execute("SELECT SUM(used_gb) FROM users")
        total_sum = cursor.fetchone()[0]
        total_server_usage = total_sum if total_sum else 0.0
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
            
        cpu_usage, ram_usage = get_system_resources()
        return jsonify({
            "users": users_list, 
            "online_users": get_online_users(),
            "cpu": cpu_usage,
            "ram": ram_usage,
            "total_server_usage": total_server_usage
        })
    except Exception as e:
        return jsonify({"users": [], "online_users": [], "cpu": 0, "ram": 0, "total_server_usage": 0.0})

@app.route('/add', methods=['POST'])
def add_user():
    try:
        username = request.form['username'].strip()
        password = request.form['password'].strip()
        limit_gb = float(request.form['limit_gb'].strip())
        days = int(request.form['days'].strip())
        expire_date = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime("%Y-%m-%d")
        
        # متد اولیه امن لینوکس بدون بلاک کردن هسته سیستم‌عامل
        subprocess.run(["sudo", "userdel", "-f", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("INSERT OR REPLACE INTO users (username, password, limit_gb, used_gb, expire_date, status, initial_gb, initial_days) VALUES (?, ?, ?, 0.0, ?, 'Active', ?, ?)",
                       (username, password, limit_gb, expire_date, limit_gb, days))
        conn.commit()
        conn.close()
        
        flash("کاربر اختصاصی جدید با موفقیت ساخته و فعال شد.", "success")
    except Exception as e:
        flash(f"خطا در ساخت سریع کاربر: {str(e)}", "danger")
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
        flash(f"دوره کاربر {username} با موفقیت تمدید شد.", "success")
    except:
        pass
    return redirect('/')

@app.route('/delete/<username>')
def delete_user(username):
    try:
        subprocess.run(["sudo", "userdel", "-f", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM users WHERE username=?", (username,))
        conn.commit()
        conn.close()
        flash(f"کاربر {username} کاملاً از سیستم حذف گردید.", "danger")
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
            
            # بازگردانی همزمان کلاینت‌های لینوکس بدون تداخل قفل
            subprocess.run(["sudo", "userdel", "-f", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        flash("دیتابیس پشتیبان با متد پایدار اولیه با موفقیت بازگردانی شد.", "success")
    except Exception as e:
        flash(f"خطا در ریستور: {str(e)}", "danger")
    return redirect('/')

if __name__ == '__main__':
    init_db()
    threading.Thread(target=monitor_core_logic, daemon=True).start()
    threading.Thread(target=update_traffic_from_proc, daemon=True).start()
    app.run(host='0.0.0.0', port=5000)
EOF

    echo "[*] Restarting Daemon Layout..."
    sudo systemctl daemon-reload
    sudo systemctl restart custom-panel.service
}

update_and_replace_logic
install_prerequisites
create_panel_app

echo -e "\e[1;32m==================================================\e[0m"
echo -e "\e[1;32m✔ SUCCESS: STABLE CODE RESTORED!                  \e[0m"
echo -e "\e[1;36m🌐 CPU/RAM MONITOR & TOTAL TRAFFIC MODULE ADDED   \e[0m"
echo -e "\e[1;32m==================================================\e[0m"
