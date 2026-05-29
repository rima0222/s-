#!/bin/bash

# غیرفعال کردن خروج اضطراری برای بخش‌های نوسانی جهت تضمین عدم کرش
set +e

clear
echo -e "\e[1;33m[*] Calibrating precise network conversion metrics & Injection Fonts...\e[0m"

# آزاد کردن قفل‌های سیستم‌عامل
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null
sudo dpkg --configure -a 2>/dev/null

echo -e "\e[1;34m==================================================\e[0m"
echo -e "\e[1;36m      SSH PRO PANEL (ADVANCED FIX & RESET)        \e[0m"
echo -e "\e[1;34m==================================================\e[0m"

DB_FILE="/etc/custom-panel/panel.db"
WEB_PANEL_PORT=5000

update_and_replace_logic() {
    echo "[*] Ensuring port 5000 is clean..."
    sudo fuser -k $WEB_PANEL_PORT/tcp 2>/dev/null
    sudo mkdir -p /etc/custom-panel
}

install_prerequisites() {
    echo "[*] Reviewing server packages..."
    set -e
    sudo apt update -y
    sudo apt install -y openssh-server python3 python3-pip python3-flask ufw sqlite3 bc psmisc net-tools
    set +e
}

create_panel_app() {
    echo "[*] Injecting Updated iOS Glassmorphism Web Panel..."
    sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, datetime, sqlite3, json, time, threading, pwd
from flask import Flask, request, render_template_string, redirect, send_file, jsonify, flash

app = Flask(__name__)
app.secret_key = "ssh_pro_glass_premium_key_v6"
DB_FILE = "/etc/custom-panel/panel.db"
TRAFFIC_TRACKER = {}

db_lock = threading.Lock()

def get_db_connection():
    conn = sqlite3.connect(DB_FILE, timeout=30.0, check_same_thread=False)
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

def get_system_stats():
    cpu = 0
    ram = 0
    try:
        with open('/proc/meminfo', 'r') as f:
            lines = f.readlines()
        mem_total = 1
        mem_available = 1
        for line in lines:
            if "MemTotal" in line:
                mem_total = int(line.split()[1])
            if "MemAvailable" in line:
                mem_available = int(line.split()[1])
        ram = int(((mem_total - mem_available) / mem_total) * 100)
        
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        parts = list(map(int, line.split()[1:5]))
        idle_before = parts[3]
        total_before = sum(parts)
        
        time.sleep(0.2)
        
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        parts = list(map(int, line.split()[1:5]))
        idle_after = parts[3]
        total_after = sum(parts)
        
        total_diff = total_after - total_before
        idle_diff = idle_after - idle_before
        if total_diff > 0:
            cpu = int(((total_diff - idle_diff) / total_diff) * 100)
    except:
        pass
    return {"cpu": max(0, min(100, cpu)), "ram": max(0, min(100, ram))}

def get_sshd_connections():
    connections = {}
    try:
        output = subprocess.check_output("ps -eo user,pid,command | grep -E 'sshd:|ssh:'", shell=True).decode()
        for line in output.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 3:
                user = parts[0].strip()
                pid = parts[1].strip()
                if user not in ['root', 'sshd', 'nobody', 'ssh'] and 'net' not in user:
                    if user not in connections:
                        connections[user] = []
                    connections[user].append(pid)
    except:
        pass
    return connections

def get_online_users():
    return list(get_sshd_connections().keys())

def update_traffic_from_proc():
    global TRAFFIC_TRACKER
    while True:
        try:
            active_connections = get_sshd_connections()
            if active_connections:
                with db_lock:
                    conn = get_db_connection()
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
                                            # جمع دقیق بایت‌های دریافتی و ارسالی کلاینت روی هسته شبکه
                                            bytes_sum += int(parts[1]) + int(parts[9])
                                    
                                    if username not in TRAFFIC_TRACKER:
                                        TRAFFIC_TRACKER[username] = {"last_bytes": bytes_sum}
                                        continue
                                    
                                    diff = bytes_sum - TRAFFIC_TRACKER[username]["last_bytes"]
                                    if diff > 0:
                                        # فرمول رسمی و استاندارد کالیبراسیون ۱۰۰٪ با نمایشگر گوشی‌ها (بایت به گیگابایت دودویی)
                                        diff_gb = diff / (1024.0 * 1024.0 * 1024.0)
                                        cursor.execute("UPDATE users SET used_gb = used_gb + ? WHERE username = ?", (diff_gb, username))
                                    
                                    TRAFFIC_TRACKER[username]["last_bytes"] = bytes_sum
                                except:
                                    pass
                    conn.commit()
                    conn.close()
        except Exception as e:
            print(f"Error in traffic monitoring: {e}")
        time.sleep(2)

def monitor_core_logic():
    while True:
        try:
            today = datetime.datetime.now().strftime("%Y-%m-%d")
            with db_lock:
                conn = get_db_connection()
                cursor = conn.cursor()
                
                cursor.execute("SELECT username, expire_date, status FROM users WHERE status='Active'")
                active_users = cursor.fetchall()
                for user in active_users:
                    username, expire_date, status = user
                    if expire_date and expire_date < today:
                        subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        cursor.execute("UPDATE users SET status='Expired' WHERE username=?", (username,))
                        subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                cursor.execute("SELECT username, limit_gb, used_gb, status FROM users")
                for row in cursor.fetchall():
                    username, limit_gb, used_gb, status = row
                    if used_gb >= limit_gb and status == 'Active':
                        subprocess.run(["sudo", "usermod", "-L", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        cursor.execute("UPDATE users SET status='Traffic_Limit' WHERE username=?", (username,))
                        subprocess.run(f"sudo killall -u {username}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                active_connections = get_sshd_connections()
                for username, pids in active_connections.items():
                    if len(pids) > 1:
                        for extra_pid in pids[1:]:
                            subprocess.run(["sudo", "kill", "-9", extra_pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            
                conn.commit()
                conn.close()
        except Exception as e:
            print(f"Error in core monitoring logic: {e}")
        time.sleep(2)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>⚡ SSH PRO - GLASS UI PREMIUM ⚡</title>
    <style>
        /* استفاده از فونت مدرن، ضخیم و یکدست انجمن / وزیرمتن برای استایل عکس‌های ارسالی */
        @import url('https://fonts.googleapis.com/css2?family=Vazirmatn:wght@400;500;700;900&display=swap');
        
        :root {
            --accent-blue: #007aff;
            --accent-green: #34c759;
            --accent-red: #ff3b30;
            --accent-yellow: #ffcc00;
            --text-main: #ffffff;
            --text-muted: #cbd5e1;
        }
        
        body { 
            font-family: 'Vazirmatn', sans-serif; 
            font-weight: 500;
            background: linear-gradient(135deg, #0f172a 0%, #1e1e2f 100%);
            background-attachment: fixed;
            color: var(--text-main); 
            margin: 0; 
            padding: 40px 20px; 
            direction: rtl; 
            -webkit-font-smoothing: antialiased;
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
        
        h1 { font-size: 28px; font-weight: 900; color: #fff; margin-bottom: 30px; display: flex; align-items: center; gap: 10px; text-shadow: 0 2px 4px rgba(0,0,0,0.2); }
        h2 { font-size: 20px; font-weight: 700; color: var(--accent-blue); margin-top: 40px; margin-bottom: 15px; }
        
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
        
        form { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
        
        input { 
            background: rgba(255, 255, 255, 0.07); 
            color: #fff; 
            border: 1px solid rgba(255, 255, 255, 0.1); 
            padding: 14px 18px; 
            border-radius: 12px; 
            flex: 1; 
            min-width: 140px; 
            font-family: 'Vazirmatn';
            font-weight: 700;
            font-size: 14px;
            transition: all 0.3s ease;
        }
        input:focus { 
            background: rgba(255, 255, 255, 0.12);
            border-color: var(--accent-blue); 
            outline: none; 
            box-shadow: 0 0 0 4px rgba(0, 122, 255, 0.25); 
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
        button:active { transform: scale(0.98); }
        .btn-blue { background: var(--accent-blue); font-weight: 900; } 
        .btn-green { background: var(--accent-green); font-weight: 900; } 
        .btn-red { background: var(--accent-red); font-weight: 900; }
        .btn-reset-traffic { background: rgba(255, 59, 48, 0.2); border: 1px solid var(--accent-red); color: #fff; margin-top: 10px; padding: 6px 12px; font-size: 12px; border-radius: 8px; }
        .btn-reset-traffic:hover { background: var(--accent-red); }

        .search-container {
            margin-bottom: 20px;
            display: flex;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 14px;
            padding: 4px;
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        .search-container input {
            background: transparent;
            border: none;
            padding: 14px;
        }
        .search-container input:focus {
            background: transparent;
            box-shadow: none;
        }

        table { width: 100%; border-collapse: collapse; margin-top: 15px; background: rgba(15, 23, 42, 0.3); border-radius: 16px; overflow: hidden; border: 1px solid rgba(255, 255, 255, 0.05); }
        th, td { padding: 16px; text-align: center; font-size: 14px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); font-weight: 700; }
        th { background-color: rgba(0, 0, 0, 0.2); color: #a1a1aa; font-weight: 900; font-size: 14px; }
        tr:last-child td { border-bottom: none; }
        tr:hover { background-color: rgba(255, 255, 255, 0.03); }
        
        .badge { padding: 6px 12px; border-radius: 8px; font-size: 12px; font-weight: 900; display: inline-block; }
        .online { background: rgba(52, 199, 89, 0.15); color: #34c759; border: 1px solid rgba(52, 199, 89, 0.3); }
        .offline { background: rgba(161, 161, 170, 0.15); color: #cbd5e1; border: 1px solid rgba(161, 161, 170, 0.3); }
        .alert-flash { padding: 14px; background: rgba(52, 199, 89, 0.15); border: 1px solid var(--accent-green); color: #34c759; border-radius: 12px; margin-bottom: 25px; text-align: center; font-weight: 900; font-size: 15px; }
        
        .progress-wrapper { width: 230px; text-align: right; margin: auto; }
        .progress-text { display: flex; justify-content: space-between; font-size: 12px; color: #a1a1aa; margin-bottom: 5px; font-weight: 700; }
        .progress-container { width: 100%; background-color: rgba(255,255,255,0.08); border-radius: 10px; height: 7px; overflow: hidden; }
        .progress-bar { height: 100%; width: 100%; border-radius: 10px; transition: width 0.6s ease, background-color 0.4s ease; }
        code { background: rgba(255,255,255,0.08); padding: 4px 8px; border-radius: 6px; color: #64d2ff; font-family: 'Vazirmatn'; font-weight: 700; }

        .status-container { display: flex; justify-content: space-around; align-items: center; text-align: center; height: 100%; }
        .circle-chart { width: 70px; height: 70px; }
        .circle-bg { fill: none; stroke: rgba(255, 255, 255, 0.1); stroke-width: 3.5; }
        .circle-progress-ram { fill: none; stroke: var(--accent-blue); stroke-width: 3.5; stroke-dasharray: 0, 100; transition: stroke-dasharray 0.5s ease; }
        .circle-progress-cpu { fill: none; stroke: var(--accent-green); stroke-width: 3.5; stroke-dasharray: 0, 100; transition: stroke-dasharray 0.5s ease; }
        .percentage { font-size: 9px; font-weight: 900; fill: #fff; text-anchor: middle; font-family: 'Vazirmatn'; }
        .stat-label { font-size: 12px; color: #a1a1aa; margin-top: 6px; font-weight: 700; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ کنترل پنل هوشمند شیشه‌ای SSH PRO</h1>
        
        {% with messages = get_flashed_messages() %}
          {% if messages %}
            {% for message in messages %}
              <div class="alert-flash">📊 {{ message }}</div>
            {% endfor %}
          {% endif %}
        {% endwith %}

        <div class="grid-header">
            <div class="card-inner">
                <h3 style="margin-top:0; font-size:14px; color:#fff; text-align:center; margin-bottom:10px; font-weight:900;">📊 وضعیت زنده منابع سرور</h3>
                <div class="status-container">
                    <div>
                        <svg viewBox="0 0 36 36" class="circle-chart">
                            <path class="circle-bg" d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831" />
                            <path id="ram-circle" class="circle-progress-ram" d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831" />
                            <text id="ram-text" x="18" y="21" class="percentage">0%</text>
                        </svg>
                        <div class="stat-label">RAM Usage</div>
                    </div>
                    <div>
                        <svg viewBox="0 0 36 36" class="circle-chart">
                            <path class="circle-bg" d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831" />
                            <path id="cpu-circle" class="circle-progress-cpu" d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831" />
                            <text id="cpu-text" x="18" y="21" class="percentage">0%</text>
                        </svg>
                        <div class="stat-label">CPU Usage</div>
                    </div>
                </div>
            </div>

            <div class="card-inner" style="text-align: center;">
                <h3 style="margin-top:0; font-size:14px; color:#fff; font-weight:900;">📈 مجموع ترافیک کل کاربران</h3>
                <div style="font-size: 28px; font-weight: 900; color: var(--accent-blue); margin: 5px 0;" id="total-server-traffic">0.000 <span style="font-size:14px;">GB</span></div>
                <p style="color:#a1a1aa; font-size:11px; margin:0 0 8px 0;">مجموع ترافیک دانلود و آپلود کالیبره واقعی کلاینت‌ها</p>
                <a href="/reset_all_traffic" onclick="return confirm('آیا از صفر کردن مصرف ترافیک تمامی کاربران اطمینان دارید؟ اکانت‌ها حذف نخواهند شد.');"><button class="btn-reset-traffic">🔄 ریست مصرف کل کاربران</button></a>
            </div>

            <div class="card-inner">
                <h3 style="margin-top:0; font-size:14px; color:var(--accent-green); font-weight:900;">📥 پشتیبان‌گیری دیتابیس</h3>
                <p style="color:#a1a1aa; font-size:11px; margin-bottom:12px;">استخراج خروجی زنده JSON از اطلاعات کلاینت‌ها.</p>
                <a href="/backup/download"><button class="btn-green" style="width:100%; padding: 10px;">📥 دانلود فایل بک‌آب</button></a>
            </div>

            <div class="card-inner">
                <h3 style="margin-top:0; font-size:14px; color:var(--accent-red); font-weight:900;">📤 بازگردانی دیتابیس</h3>
                <form action="/backup/restore" method="POST" enctype="multipart/form-data" style="flex-direction: column; align-items: stretch; gap: 6px;">
                    <input type="file" name="backup_file" accept=".json" required style="padding:5px; font-size:11px;">
                    <button type="submit" class="btn-red" style="padding:10px;">📤 ریستور کل کاربران</button>
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
                
                if(!data) return;

                if(data.system_stats) {
                    const ramUsage = data.system_stats.ram || 0;
                    const cpuUsage = data.system_stats.cpu || 0;
                    
                    document.getElementById('ram-text').textContent = ramUsage + '%';
                    document.getElementById('ram-circle').style.strokeDasharray = ramUsage + ', 100';
                    
                    document.getElementById('cpu-text').textContent = cpuUsage + '%';
                    document.getElementById('cpu-circle').style.strokeDasharray = cpuUsage + ', 100';
                }

                if(data.users) {
                    let totalServerUsed = 0;
                    data.users.forEach(u => {
                        totalServerUsed += parseFloat(u.used_gb) || 0;
                    });
                    document.getElementById('total-server-traffic').innerHTML = totalServerUsed.toFixed(3) + ' <span style="font-size:14px;">GB</span>';
                }

                const tbody = document.getElementById('user-table-body');
                const searchInputElement = document.getElementById('search-input');
                const searchInput = searchInputElement ? searchInputElement.value.toLowerCase() : "";

                tbody.innerHTML = '';

                if(data.users) {
                    data.users.forEach(user => {
                        try {
                            const isOnline = data.online_users.map(u => u.trim().toLowerCase()).includes(user.username.trim().toLowerCase());
                            const onlineBadge = isOnline 
                                ? '<span class="badge online">● آنلاین</span>' 
                                : '<span class="badge offline">○ آفلاین</span>';
                            
                            let statusText = '<span style="color:#34c759; font-weight:900;">فعال</span>';
                            if (user.status === 'Expired') statusText = '<span style="color:#ff3b30; font-weight:900;">منقضی زمان</span>';
                            if (user.status === 'Traffic_Limit') statusText = '<span style="color:#ffcc00; font-weight:900;">اتمام حجم</span>';

                            const totalGb = parseFloat(user.limit_gb) || 0;
                            const usedGb = parseFloat(user.used_gb) || 0;
                            let remainingGb = totalGb - usedGb;
                            if (remainingGb < 0) remainingGb = 0;
                            
                            let remainingPercent = totalGb > 0 ? (remainingGb / totalGb) * 100 : 0;
                            if (remainingPercent > 100) remainingPercent = 100;
                            if (remainingPercent < 0) remainingPercent = 0;
                            
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

                            let daysText = 'پایان دوره';
                            if (user.remaining_days !== undefined && user.remaining_days !== null) {
                                const daysInt = parseInt(user.remaining_days);
                                if (daysInt > 0) {
                                    daysText = daysInt + ' روز';
                                }
                            }

                            tr.innerHTML = `
                                <td style="font-weight:900; color:#007aff;">${user.username}</td>
                                <td><code>${user.password}</code></td>
                                <td style="font-weight:900; color:#fff;">${totalGb.toFixed(1)} GB</td>
                                <td><span style="color:#64d2ff; font-weight:900;">${usedGb.toFixed(3)}</span> GB</td>
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
                                <td style="font-weight: 900; color: #ff3b30;">${daysText}</td>
                                <td>${onlineBadge}</td>
                                <td>${statusText}</td>
                                <td>
                                    <a href="/renew/${user.username}"><button class="btn-green" style="padding:6px 14px; font-size:12px; border-radius:8px;">🔄 ریست دوره</button></a>
                                    <a href="/delete/${user.username}"><button class="btn-red" style="padding:6px 14px; font-size:12px; border-radius:8px;">حذف</button></a>
                                end
                                </td>
                            `;
                            tbody.appendChild(tr);
                        } catch(innerErr) {
                            console.error("Error rendering user row:", innerErr);
                        }
                    });
                }
            } catch (error) {
                console.error("Error updating web items:", error);
            }
        }
        fetchLiveStatus();
        setInterval(fetchLiveStatus, 2000);
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
        with db_lock:
            conn = get_db_connection()
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
        return jsonify({
            "users": users_list, 
            "online_users": get_online_users(),
            "system_stats": get_system_stats()
        })
    except Exception as e:
        return jsonify({"users": [], "online_users": [], "system_stats": {"cpu": 0, "ram": 0}, "error": str(e)})

@app.route('/reset_all_traffic')
def reset_all_traffic():
    try:
        with db_lock:
            conn = get_db_connection()
            cursor = conn.cursor()
            # صفر کردن مصرف کلیه کاربران بدون تغییر سایر متغیرها کلاینت
            cursor.execute("UPDATE users SET used_gb=0.0, status='Active'")
            conn.commit()
            conn.close()
        
        # باز کردن انسداد کلاینت‌ها در لایه لینوکس سرور بعد از صفر کردن ترافیک کلاینت
        try:
            with db_lock:
                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute("SELECT username FROM users")
                all_users = cursor.fetchall()
                conn.close()
            for u in all_users:
                subprocess.run(["sudo", "usermod", "-U", u[0]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass
            
        flash("ترافیک مصرفی تمامی کاربران با موفقیت صفر شد و قفل دسترسی‌ها بازگردانی شد.")
    except Exception as e:
        flash(f"خطا در ریست ترافیک کل: {str(e)}")
    return redirect('/')

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
        flash(f"کاربر {username} با موفقیت ساخته شد.")
    except Exception as e:
        print(f"Error adding user: {e}")
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
        flash(f"دوره کاربر {username} با موفقیت تمدید و ریست شد.")
    except Exception as e:
        print(f"Error renewing user: {e}")
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
        flash(f"کاربر {username} با موفقیت از سیستم حذف شد.")
    except Exception as e:
        print(f"Error deleting user: {e}")
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
        with db_lock:
            conn = get_db_connection()
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
        flash("دیتابیس پشتیبان با متد پایدار اولیه با موفقیت بازگردانی شد.")
    except Exception as e:
        flash(f"خطا در ریستور: {str(e)}")
    return redirect('/')

def safe_system_user_create(username, password):
    try:
        pwd.getpwnam(username)
        subprocess.run(["sudo", "userdel", "-r", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except KeyError:
        pass
        
    subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(f"echo '{username}:{password}' | sudo chpasswd", shell=True)

if __name__ == '__main__':
    init_db()
    threading.Thread(target=monitor_core_logic, daemon=True).start()
    threading.Thread(target=update_traffic_from_proc, daemon=True).start()
    app.run(host='0.0.0.0', port=5000)
EOF

    echo "[*] Aligning Custom Service Daemon..."
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

update_and_replace_logic
install_prerequisites
create_panel_app

echo -e "\e[1;32m==================================================\e[0m"
echo -e "\e[1;32m✔ CONVERSIONS CALIBRATED & DONT TOUCH OTHER APPS   \e[0m"
echo -e "\e[1;36m🌐 PANELS LIVE ON PORT 5000                        \e[0m"
echo -e "\e[1;32m==================================================\e[0m"
