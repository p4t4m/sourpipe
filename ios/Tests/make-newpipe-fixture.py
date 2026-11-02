#!/usr/bin/env python3
"""Writes SourPipeCoreTests/Fixtures/newpipe-backup.zip: synthetic data in NewPipe's real layout.

The CREATE TABLE statements follow NewPipe's schema version 9, plus Tubular's whitelist table and a
column no version has, because forks add their own. Run it from any directory.
"""
import io, os, sqlite3, tempfile, zipfile

SCHEMA = """
CREATE TABLE subscriptions (uid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, service_id INTEGER NOT NULL,
  url TEXT, name TEXT, avatar_url TEXT, subscriber_count INTEGER, description TEXT,
  notification_mode INTEGER NOT NULL, fork_only_column TEXT);
CREATE TABLE search_history (creation_date INTEGER, service_id INTEGER NOT NULL, search TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL);
CREATE TABLE streams (uid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, service_id INTEGER NOT NULL,
  url TEXT NOT NULL, title TEXT NOT NULL, stream_type TEXT NOT NULL, duration INTEGER NOT NULL,
  uploader TEXT NOT NULL, uploader_url TEXT, thumbnail_url TEXT, view_count INTEGER,
  textual_upload_date TEXT, upload_date INTEGER, is_upload_date_approximation INTEGER);
CREATE TABLE stream_history (stream_id INTEGER NOT NULL, access_date INTEGER NOT NULL,
  repeat_count INTEGER NOT NULL, PRIMARY KEY(stream_id, access_date));
CREATE TABLE stream_state (stream_id INTEGER NOT NULL, progress_time INTEGER NOT NULL,
  PRIMARY KEY(stream_id));
CREATE TABLE playlists (uid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, name TEXT,
  is_thumbnail_permanent INTEGER NOT NULL, thumbnail_stream_id INTEGER NOT NULL,
  display_index INTEGER NOT NULL);
CREATE TABLE playlist_stream_join (playlist_id INTEGER NOT NULL, stream_id INTEGER NOT NULL,
  join_index INTEGER NOT NULL, PRIMARY KEY(playlist_id, join_index));
CREATE TABLE remote_playlists (uid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, service_id INTEGER NOT NULL,
  name TEXT, url TEXT, thumbnail_url TEXT, uploader TEXT, display_index INTEGER NOT NULL,
  stream_count INTEGER);
CREATE TABLE feed_group (uid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, name TEXT NOT NULL,
  icon_id INTEGER NOT NULL, sort_order INTEGER NOT NULL);
CREATE TABLE feed_group_subscription_join (group_id INTEGER NOT NULL, subscription_id INTEGER NOT NULL,
  PRIMARY KEY(group_id, subscription_id));
CREATE TABLE sponsorblock_whitelist (uploader TEXT PRIMARY KEY NOT NULL);
"""

DATA = """
INSERT INTO subscriptions (uid, service_id, url, name, avatar_url, notification_mode) VALUES
  (1, 0, 'https://www.youtube.com/channel/blender', 'Blender', 'https://img/blender.jpg', 0),
  (2, 1, 'https://soundcloud.com/ambient', 'Ambient Label', NULL, 0),
  (3, 5, 'https://space.bilibili.com/1', 'BiliBili channel', NULL, 0);
INSERT INTO streams VALUES
  (1, 0, 'https://www.youtube.com/watch?v=sprite', 'Sprite Fright', 'VIDEO_STREAM', 629, 'Blender',
   'https://www.youtube.com/channel/blender', 'https://img/sprite.jpg', 1000, '5 years ago', 1600000000000, 1),
  (2, 0, 'https://www.youtube.com/watch?v=agent', 'Agent 327', 'VIDEO_STREAM', 231, 'Blender', NULL, NULL, NULL, NULL, NULL, NULL),
  (3, 0, 'https://www.youtube.com/watch?v=resume', 'Resume only', 'VIDEO_STREAM', 500, 'Blender', NULL, NULL, NULL, NULL, NULL, NULL),
  (4, 5, 'https://www.bilibili.com/video/x', 'BiliBili video', 'VIDEO_STREAM', 60, 'x', NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO stream_history VALUES (1, 1700000000000, 3), (2, 1600000000000, 1), (4, 1700000000001, 1);
INSERT INTO stream_state VALUES (1, 95500), (3, 40000);
INSERT INTO playlists VALUES (10, 'Empty list', 0, -1, 2), (11, 'Favourites', 0, 1, 1);
INSERT INTO playlist_stream_join VALUES (11, 1, 1), (11, 2, 0), (11, 1, 2), (11, 4, 3);
INSERT INTO remote_playlists VALUES
  (1, 0, 'Open Movies', 'https://www.youtube.com/playlist?list=PL1', 'https://img/pl.jpg', 'Blender', 0, 14),
  (2, 5, 'BiliBili list', 'https://www.bilibili.com/list', NULL, NULL, 1, 2);
INSERT INTO feed_group VALUES (1, 'Art', 0, 0);
INSERT INTO feed_group_subscription_join VALUES (1, 1), (1, 3);
INSERT INTO search_history VALUES (100, 0, 'older search', 1), (300, 0, 'newest search', 2), (200, 1, 'older search', 3);
INSERT INTO sponsorblock_whitelist VALUES ('Blender');
"""

with tempfile.TemporaryDirectory() as folder:
    path = os.path.join(folder, "newpipe.db")
    db = sqlite3.connect(path)
    db.executescript(SCHEMA + DATA)
    db.execute("PRAGMA user_version = 9")
    db.commit()
    db.close()
    with open(path, "rb") as f:
        database = f.read()

target = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "SourPipeCoreTests/Fixtures/newpipe-backup.zip")
with zipfile.ZipFile(target, "w") as z:
    z.writestr("stored.txt", b"stored entry", zipfile.ZIP_STORED)
    z.writestr("newpipe.db", database, zipfile.ZIP_DEFLATED)
    z.writestr("newpipe.settings", b"\xac\xed\x00\x05", zipfile.ZIP_DEFLATED)
    z.writestr("preferences.json", b'{"theme":"dark"}', zipfile.ZIP_DEFLATED)
print("wrote", target)
