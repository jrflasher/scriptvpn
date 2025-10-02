from flask import Flask, request, jsonify, render_template_string
from flask_httpauth import HTTPBasicAuth
import sqlite3
import os

app = Flask(__name__)
auth = HTTPBasicAuth()

# Konfigurasi
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, '..', 'config', 'web_config.ini')
DB_PATH = os.path.join(SCRIPT_DIR, '..', 'database', 'accounts.db')

# Baca konfigurasi
import configparser
config = configparser.ConfigParser()
config.read(CONFIG_PATH)

users = {
    config.get('auth', 'username'): config.get('auth', 'password')
}

@auth.verify_password
def verify_password(username, password):
    return users.get(username) == password

@app.route('/')
@auth.login_required
def index():
    # Template HTML sederhana
    html = """
    <h1>JR-XRAY Web Panel</h1>
    <h2>Account Management</h2>
    <table border="1">
        <tr>
            <th>ID</th>
            <th>Username</th>
            <th>IP Limit</th>
            <th>Speed Limit</th>
            <th>Expiry (days)</th>
        </tr>
        {% for account in accounts %}
        <tr>
            <td>{{ account[0] }}</td>
            <td>{{ account[1] }}</td>
            <td>{{ account[4] }}</td>
            <td>{{ account[5] }}</td>
            <td>{{ account[6] }}</td>
        </tr>
        {% endfor %}
    </table>
    """
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM accounts")
    accounts = cursor.fetchall()
    conn.close()
    
    return render_template_string(html, accounts=accounts)

@app.route('/api/accounts', methods=['GET'])
@auth.login_required
def get_accounts():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM accounts")
    accounts = cursor.fetchall()
    conn.close()
    return jsonify(accounts)

if __name__ == '__main__':
    app.run(host=config.get('web', 'host'), port=config.getint('web', 'port'), debug=config.getboolean('web', 'debug'))