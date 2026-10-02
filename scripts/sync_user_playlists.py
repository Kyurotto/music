import sqlite3, os

db_paths = ['pulse_music.db', os.path.expandvars(r'%APPDATA%\music\pulse_music.db')]

for db_path in db_paths:
    if not os.path.exists(db_path):
        continue
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # Check if playlists exist for user 3
    cur.execute("SELECT id, title FROM imported_playlists WHERE user_id = '3'")
    existing = cur.fetchall()
    print(db_path, 'User 3 existing playlists:', existing)
    
    if not existing:
        cur.execute("SELECT id, title, subtitle, spotify_url, gradient_colors, created_at, updated_at FROM imported_playlists WHERE user_id = '5'")
        novi_pls = cur.fetchall()
        for pl in novi_pls:
            new_id = pl[0] + '-john'
            cur.execute(
                "INSERT OR REPLACE INTO imported_playlists (id, user_id, title, subtitle, spotify_url, gradient_colors, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (new_id, '3', pl[1], pl[2], pl[3], pl[4], pl[5], pl[6])
            )
            cur.execute("SELECT song_id, position FROM imported_playlist_songs WHERE playlist_id = ?", (pl[0],))
            tracks = cur.fetchall()
            for t in tracks:
                cur.execute(
                    "INSERT OR REPLACE INTO imported_playlist_songs (playlist_id, song_id, position) VALUES (?, ?, ?)",
                    (new_id, t[0], t[1])
                )
        conn.commit()
        print(db_path, 'Created user 3 playlists from user 5!')
    
    cur.execute("SELECT id, user_id, title FROM imported_playlists")
    print(db_path, 'All playlists now:', cur.fetchall())
    conn.close()
