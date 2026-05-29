#!/bin/bash
sudo fuser -k 5000/tcp 2>/dev/null
sudo mkdir -p /etc/custom-panel

sudo tee /etc/custom-panel/app.py > /dev/null << 'EOF'
import os, subprocess, sqlite3, threading, time, json
from flask import Flask, request, render_template_string, redirect, jsonify

app = Flask(__name__)
DB_FILE = "/etc/custom-panel/panel.db"

def init_db():
    conn = sqlite3.connect(DB_FILE)
    conn.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, password TEXT, limit_gb REAL, used_gb REAL DEFAULT 0, expire_days INTEGER)')
    conn.commit(); conn.close()

def get_sys_data():
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
        body { background: #0f172a; color: white; font-family: Tahoma; }
        .glass { background: rgba(255,255,255,0.05); backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.1); border-radius: 15px; padding: 20px; margin: 20px; }
        button { background: transparent; border: 1px solid white; color: white; padding: 8px 15px; cursor: pointer; border-radius: 5px; }
        button:hover { background: white; color: black; }
        table { width: 95%; margin: auto; border-collapse: collapse; background: rgba(255,255,255,0.05); }
        th, td { padding: 12px; border: 1px solid rgba(255,255,255,0.1); text-align: center; }
    </style>
</head>
<body>
    <div class="glass">
        <h3>وضعیت منابع: CPU: <span id="cpu">0</span>% | RAM: <span id="ram">0</span>%</h3>
        <h3>ترافیک کل: <span id="total">0</span> GB <button onclick="fetch('/reset-all')">ریست ترافیک کل</button></h3>
    </div>
    <div class="glass">
        <form action="/add" method="POST">
            <input name="u" placeholder="نام کاربری" required> <input name="p" placeholder="رمز" required>
            <input name="gb" placeholder="حجم(GB)" required> <button type="submit">ثبت کاربر</button>
        </form>
    </div>
    <table>
        <thead><tr><th>کاربر</th><th>رمز</th><th>مصرف</th><th>عملیات</th></tr></thead>
        <tbody id="body"></tbody>
    </table>
    <script>
        async function update() {
            let res = await fetch('/api'); let d = await res.json();
            document.getElementById('cpu').innerText = d.cpu;
            document.getElementById('ram').innerText = d.ram;
            document.getElementById('total').innerText = d.total.toFixed(2);
            let h = '';
            d.users.forEach(u => h += `<tr><td>${u.u}</td><td>${u.p}</td><td>${u.used} GB</td><td><button onclick="location.href='/del/${u.u}'">حذف</button></td></tr>`);
            document.getElementById('body').innerHTML = h;
        }
        setInterval(update, 1000);
    </script>
</body>
</html>
''')

@app.route('/api')
def api():
    conn = sqlite3.connect(DB_FILE)
    users = conn.execute("SELECT username, password, used_gb FROM users").fetchall()
    total = conn.execute("SELECT SUM(used_gb) FROM users").fetchone()[0] or 0
    conn.close()
    cpu, ram = get_sys_data()
    return jsonify({"users": [{"u": u[0], "p": u[1], "used": u[2]} for u in users], "total": total, "cpu": cpu, "ram": ram})

@app.route('/add', methods=['POST'])
def add():
    u, p, gb = request.form['u'], request.form['p'], request.form['gb']
    subprocess.run(["sudo", "userdel", "-f", u])
    subprocess.run(["sudo", "useradd", "-M", "-s", "/bin/false", u])
    subprocess.run(f"echo '{u}:{p}' | sudo chpasswd", shell=True)
    conn = sqlite3.connect(DB_FILE)
    conn.execute("INSERT INTO users (username, password, limit_gb) VALUES (?,?,?)", (u, p, gb))
    conn.commit(); conn.close()
    return redirect('/')

@app.route('/del/<u_name>')
def dele(u_name):
    subprocess.run(["sudo", "userdel", "-f", u_name])
    conn = sqlite3.connect(DB_FILE)
    conn.execute("DELETE FROM users WHERE username=?", (u_name,))
    conn.commit(); conn.close()
    return redirect('/')

@app.route('/reset-all')
def reset():
    conn = sqlite3.connect(DB_FILE)
    conn.execute("UPDATE users SET used_gb = 0")
    conn.commit(); conn.close()
    return redirect('/')

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
EOF
sudo python3 /etc/custom-panel/app.py
