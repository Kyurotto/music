import sqlite3
import os
import subprocess

paths = [
    os.path.abspath('pulse_music.db'),
    os.path.expandvars(r'%APPDATA%\music\pulse_music.db')
]

for p in paths:
    if os.path.exists(p):
        conn = sqlite3.connect(p)
        c = conn.cursor()
        c.execute("DELETE FROM user_sessions WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'google.user%' OR email LIKE 'facebook.user%' OR display_name LIKE 'google.user%')")
        c.execute("DELETE FROM users WHERE email LIKE 'google.user%' OR email LIKE 'facebook.user%' OR display_name LIKE 'google.user%'")
        
        # Ensure John Laurence is the real Google account
        c.execute("""
            INSERT OR REPLACE INTO users (id, email, display_name, photo_url, role, auth_provider, created_at, last_login_at, password_hash)
            VALUES ('usr-john-laurence', 'johnlaurencenovicio@gmail.com', 'John Laurence', NULL, 'user', 'google', 1790001211941, 1790409015045, NULL)
        """)
        c.execute("DELETE FROM user_sessions")
        c.execute("INSERT INTO user_sessions (user_id, saved_at) VALUES ('usr-john-laurence', 1790409015045)")
        conn.commit()
        
        c.execute('SELECT id, email, display_name, auth_provider FROM users')
        print(p, 'Users:')
        for u in c.fetchall():
            print(' ', u)
        c.execute('SELECT * FROM user_sessions')
        print(p, 'Active Session:', c.fetchall())
        conn.close()

try:
    with open('pulse_music.db', 'rb') as f:
        data = f.read()
    p = subprocess.Popen(['adb', 'exec-in', 'run-as', 'com.example.music', 'sh', '-c', 'cat > /data/data/com.example.music/files/pulse_music.db'], stdin=subprocess.PIPE)
    p.communicate(input=data, timeout=5)
    print('Pushed clean db to Android device successfully!')
except Exception as e:
    print('ADB push error:', e)
