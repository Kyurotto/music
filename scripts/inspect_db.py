import sqlite3

def main():
    conn = sqlite3.connect('phone_pulse_music.db')
    cur = conn.cursor()
    print("=== USERS ===")
    cur.execute("SELECT id, email, display_name FROM users")
    for r in cur.fetchall():
        print(r)

    print("\n=== PLAYLISTS ===")
    cur.execute("SELECT id, user_id, title, subtitle FROM imported_playlists")
    playlists = cur.fetchall()
    for r in playlists:
        pid = r[0]
        cur.execute("SELECT count(*) FROM imported_playlist_songs WHERE playlist_id = ?", (pid,))
        count = cur.fetchone()[0]
        print(f"Playlist: {r} -> {count} songs")

    print("\n=== USER 3 PLAYLIST SONGS ===")
    cur.execute("""
        SELECT p.title, s.id, s.title, s.artist, s.audio_url, s.is_preview, s.is_youtube_audio
        FROM imported_playlists p
        JOIN imported_playlist_songs ps ON p.id = ps.playlist_id
        JOIN imported_songs s ON s.id = ps.song_id
        WHERE p.user_id = '3'
        LIMIT 30
    """)
    for r in cur.fetchall():
        print(r)

if __name__ == '__main__':
    main()


