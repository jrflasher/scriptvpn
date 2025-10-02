from flask import Flask, request, jsonify
import sqlite3
import os

app = Flask(__name__)

# Path ke database
DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'database', 'accounts.db')
API_KEYS_DB = os.path.join(os.path.dirname(__file__), '..', 'database', 'api_keys.db')

# Fungsi untuk validasi API key
def is_valid_api_key(api_key):
    conn = sqlite3.connect(API_KEYS_DB)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM api_keys WHERE key=?", (api_key,))
    result = cursor.fetchone()
    conn.close()
    return result is not None

@app.route('/api/create_account', methods=['POST'])
def create_account():
    data = request.json
    api_key = data.get('api_key')
    
    if not is_valid_api_key(api_key):
        return jsonify({"status": "error", "message": "Invalid API key"}), 401
    
    # Ambil data lain
    username = data.get('username')
    password = data.get('password')
    ip_limit = data.get('ip_limit')
    speed_limit = data.get('speed_limit')
    expiry_days = data.get('expiry_days')
    
    # Generate UUID
    import uuid
    uuid_str = str(uuid.uuid4())
    
    # Simpan ke database
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("INSERT INTO accounts (username, password, uuid, ip_limit, speed_limit, expiry_days) VALUES (?, ?, ?, ?, ?, ?)",
                      (username, password, uuid_str, ip_limit, speed_limit, expiry_days))
        conn.commit()
        return jsonify({"status": "success", "uuid": uuid_str})
    except sqlite3.IntegrityError:
        return jsonify({"status": "error", "message": "Username already exists"}), 400
    finally:
        conn.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)