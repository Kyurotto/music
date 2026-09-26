import http.server
import socketserver
import subprocess
import os
import time
import threading

PORT = 58321
WORKSPACE_DB = os.path.abspath('pulse_music.db')
APPDATA_DB = os.path.expandvars(r'%APPDATA%\music\pulse_music.db')

def setup_adb_reverse():
    try:
        subprocess.run(['adb', 'reverse', f'tcp:{PORT}', f'tcp:{PORT}'], capture_output=True, timeout=3)
    except Exception:
        pass

def save_db_bytes(data):
    if len(data) < 100 or data[:15] != b'SQLite format 3':
        return False
    for path in [WORKSPACE_DB, APPDATA_DB]:
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'wb') as f:
                f.write(data)
            print(f'[SyncDaemon] Updated {path} ({len(data)} bytes)')
        except Exception as e:
            print(f'[SyncDaemon] Error writing {path}: {e}')
    return True

class SyncHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        if self.path == '/sync-db':
            if save_db_bytes(post_data):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'OK')
                return
        self.send_response(400)
        self.end_headers()
        self.wfile.write(b'ERR')

    def log_message(self, format, *args):
        pass

def adb_poller():
    last_data = None
    while True:
        try:
            setup_adb_reverse()
            p = subprocess.Popen(
                ['adb', 'exec-out', 'run-as', 'com.example.music', 'cat', '/data/data/com.example.music/files/pulse_music.db'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            out, _ = p.communicate(timeout=4)
            if out and len(out) > 1000 and out[:15] == b'SQLite format 3':
                if out != last_data:
                    last_data = out
                    save_db_bytes(out)
        except Exception:
            pass
        time.sleep(2)

def start_server():
    setup_adb_reverse()
    t = threading.Thread(target=adb_poller, daemon=True)
    t.start()
    with socketserver.TCPServer(('0.0.0.0', PORT), SyncHandler) as httpd:
        print(f'[SyncDaemon] Listening on port {PORT}...')
        httpd.serve_forever()

if __name__ == '__main__':
    start_server()
