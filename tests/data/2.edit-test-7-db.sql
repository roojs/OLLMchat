PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE filebase (id INTEGER PRIMARY KEY, path TEXT NOT NULL DEFAULT '', parent_id INT64 NOT NULL DEFAULT 0, base_type TEXT NOT NULL DEFAULT '', language TEXT, last_approved_copy_path TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 0, cursor_line INTEGER NOT NULL DEFAULT 0, cursor_offset INTEGER NOT NULL DEFAULT 0, scroll_position INTEGER NOT NULL DEFAULT 0, last_viewed INT64 NOT NULL DEFAULT 0, last_modified INT64 NOT NULL DEFAULT 0, points_to_id INT64 NOT NULL DEFAULT 0, target_path TEXT NOT NULL DEFAULT '', is_project INTEGER NOT NULL DEFAULT 0, is_ignored INTEGER NOT NULL DEFAULT 0, is_text INTEGER NOT NULL DEFAULT 0, is_repo INTEGER NOT NULL DEFAULT -1, last_scan INT64 NOT NULL DEFAULT 0);
INSERT INTO filebase VALUES(1,'/home/alan/.cache/ollmchat/testing/testproj7',0,'d','','',1,0,0,0,0,0,0,'',1,0,0,-1,0);
INSERT INTO filebase VALUES(2,'/home/alan/.cache/ollmchat/testing/testproj7/project_file.txt',1,'f','','',0,0,0,0,0,0,0,'',0,0,1,-1,0);
COMMIT;
