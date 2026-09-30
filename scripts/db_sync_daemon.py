import subprocess
import os
import time

WORKSPACE_DB = os.path.abspath('pulse_music.db')
APPDATA_DB = os.path.expandvars(r'%APPDATA%\music\pulse_music.db')

def save_db_bytes(data):
    if len(data) < 100 or data[:15] != b'SQLite format 3':
        return False
    for p in [WORKSPACE_DB, APPDATA_DB]:
        try:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'wb') as f:
                f.write(data)
            print(f'[SyncDaemon] Updated {p} ({len(data)} bytes)', flush=True)
        except Exception as e:
            print(f'[SyncDaemon] Error writing {p}: {e}', flush=True)
    return True

def run_sync():
    last_data = None
    print('[SyncDaemon] Background Android database sync started.', flush=True)
    while True:
        try:
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

if __name__ == '__main__':
    run_sync()
