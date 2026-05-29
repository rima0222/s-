#!/bin/bash
set +e
clear
echo -e "\e[1;36m[*] Upgrading to Glass-morphic UI & Fixing Resource Monitoring...\e[0m"

sudo fuser -k 5000/tcp 2>/dev/null
sudo mkdir -p /etc/custom-panel

sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, sqlite3, json, time, threading
from flask import Flask, request, render_template_string, redirect, jsonify

app = Flask(__name__)
DB_FILE = "/etc/custom-panel/panel.db"

def get_system_resources():
    try:
        cpu = subprocess.check_output("top -bn1 | grep 'Cpu(s)' | awk '{print 100 - $8}'", shell=True).decode().strip()
        ram = subprocess.check_output("free | grep Mem | awk '{print $3/$2 * 100.0}'", shell=True).decode().strip()
        return round(float(cpu), 1), round(float(ram), 1)
    except: return 0.0, 0.0

@app.route('/')
def index():
    return render_template_string('''
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <style>
        :root { --bg: #0f172a; --text: #fff; --glass: rgba(255,255,255,0.05); }
        body.light { --bg: #f8fafc; --text: #1e293b; --glass: rgba(0,0,0,0.05); }
        body { background: var(--bg); color: var(--text); font-family: Tahoma; transition: 0.3s; padding: 20px; }
        .glass { background: var(--glass); backdrop-filter: blur(15px); border: 1px solid rgba(255,255,255,0.1); border-radius: 15px; padding: 20px; }
        button { background: transparent; border: 1px solid var(--text); color: var(--text); padding: 8px 15px; border-radius: 8px; cursor: pointer; transition: 0.3s; }
        button:hover { background: var(--text); color: var(--bg); }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; border-bottom: 1px solid #444; text-align: center; }
    </style>
</head>
<body>
    <button onclick="document.body.classList.toggle('light')">تغییر تم</button>
    <div class="glass">
        <h3>منابع سرور: CPU: <span id="cpu">0</span>% | RAM: <span id="ram">0</span>%</h3>
        <h3>مجموع ترافیک: <span id="total">0</span> GB <button onclick="resetTraffic()">ریست</button></h3>
    </div>
    <table>
        <thead><tr><th>کاربر</th><th>مصرف</th><th>وضعیت</th></tr></thead>
        <tbody id="body"></tbody>
    </table>
    <script>
        async function update() {
            let res = await fetch('/api/data');
            let data = await res.json();
            document.getElementById('cpu').innerText = data.cpu;
            document.getElementById('ram').innerText = data.ram;
            document.getElementById('total').innerText = data.total.toFixed(2);
            let html = '';
            data.users.forEach(u => {
                html += `<tr><td>${u.u}</td><td>${u.used.toFixed(2)}</td><td>${u.status}</td></tr>`;
            });
            document.getElementById('body').innerHTML = html;
        }
        function resetTraffic() { fetch('/reset-traffic'); }
        setInterval(update, 1000);
    </script>
</body>
</html>
''')

@app.route('/api/data')
def api():
    conn = sqlite3.connect(DB_FILE)
    users = conn.execute("SELECT username, used_gb, status FROM users").fetchall()
    total = conn.execute("SELECT SUM(used_gb) FROM users").fetchone()[0] or 0
    conn.close()
    cpu, ram = get_system_resources()
    return jsonify({"users": [{"u": u[0], "used": u[1], "status": u[2]} for u in users], "total": total, "cpu": cpu, "ram": ram})

@app.route('/reset-traffic')
def reset():
    conn = sqlite3.connect(DB_FILE)
    conn.execute("UPDATE users SET used_gb = 0")
    conn.commit()
    conn.close()
    return "OK"

if __name__ == '__main__': app.run(host='0.0.0.0', port=5000)
EOF

sudo systemctl restart custom-panel.service
echo -e "\e[1;32m[*] Panel Updated with Glass Theme & Live Resource Monitor!\e[0m"
