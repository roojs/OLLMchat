# Extensionless / API-written files stay `is_text=0`

**Status:** ✅ FIXED — user closed 2026-09-02 (extensionless / API-written files get `is_text=1`)

**Started:** 2026-08-13 · **Updated:** 2026-08-14

**Related:** [`2026-08-12-FIXED-changed-files-notification-approvals-ui.md`](done/2026-08-12-FIXED-changed-files-notification-approvals-ui.md) (Approvals click → `File.fetch` miss)

---

## Problem

🔷 Create a file **without an extension** via the API (e.g. `docs/Hello World Test` with plain text content).

**Expected:**
- Treated as a **text** file (`filebase.is_text = 1`)
- Appears in project file index / `project_files.child_map`
- Approvals (and editor) can `File.fetch` / open it like any other text file

**Actual:**
- DB row has **`is_text = 0`**, `language` empty, often `is_need_approval = 1`
- Excluded from `project_files.child_map` (only text files are added there)
- `File.fetch` looks up `child_map` only → miss
- Approvals click does nothing useful even though the path is pending and on disk

---

## Where `is_text` is set (daemon)

ℹ️ Property: `ollmfilesd/FileBase.vala` — `bool is_text` (DB column `is_text`).

| Site | File | When | How |
|------|------|------|-----|
| **A** `File.new_from_info` | `ollmfilesd/File.vala` | Filesystem scan (`Folder.enumerate_children` already requests `STANDARD_CONTENT_TYPE`) | `info.get_content_type()` → `text/*`, **or** `detect_language()` non-empty |
| **B** `File.to_real` | `ollmfilesd/File.vala` | API create: fake → indexed (`write` / `register`) | **`detect_language()` only**; `is_text = true` **iff** `language != ""` |
| **C** `File.new_fake` | `libocfiles/File.vala` | Client-side fake (outside daemon index) | `query_info(STANDARD_CONTENT_TYPE + TIME_MODIFIED)` → `text/*`, **or** language |

Consumers that care:

- `ProjectFiles.add_file_if_new` — skips `!is_text` → not in `child_map`
- `File.fetch` RPC — `child_map` only
- Vector scan / indexer — skip non-text

---

## Evidence

✔️ Live file `/home/alan/gitlive/OLLMchat/docs/Hello World Test` (12 bytes): DB `is_text=0`, language empty.

✔️ GIO on that path (2026-08-14):

```text
standard::content-type:      text/plain
standard::fast-content-type: application/octet-stream
ContentType.guess(path, null):  application/octet-stream (uncertain)
ContentType.guess(path, bytes): text/plain
query_info(STANDARD_CONTENT_TYPE).get_content_type(): text/plain
```

✔️ Scan path already asks for the right attribute:

```vala
// Folder.enumerate_children — STANDARD_CONTENT_TYPE (not fast)
```

✔️ Write order for **new** files (`File.write` default branch):

1. `yield file.to_real()` — sets `is_text` from language, `saveToDB`, `project_files.update_from` / `new_file_added`
2. `yield file.realize(p)` → `buffer.write_real` → bytes on disk → `update_file_metadata_after_write`

→ At **B**, the file **often does not exist yet**, so a disk `query_info` in `to_real` alone cannot fix the create-via-write path. `register` (file already on disk) can sniff in `to_real`.

🚫 **Wrong fix (reverted):** `File.fetch` → `all_files`. Papers over bad `is_text`.

🚫 **Do not use** `standard::fast-content-type` or `ContentType.guess(path, null)` for extensionless — both report `application/octet-stream` here.

---

## Root cause

✔️ **API promote path (`to_real`) never applies the same content-type rule as scan (`new_from_info`) / client (`new_fake`).**  
It only promotes `is_text` from extension→language. Extensionless plain text stays `0`.  
Additionally, **`project_files.update_from` runs in `to_real` before bytes (and thus before a reliable sniff)**, so even a later DB flip would need a second index refresh to enter `child_map`.

✔️ **Related — scan used to be unable to heal a bad row:** `Folder.read_dir_update` `copy_from` except list kept scan `is-ignored` / `is-repo` but not `is-text` / `language`, so a correct `new_from_info` sniff was overwritten by the stale DB value. **Fixed:** except those two and sync onto `old_item` (same pattern as ignored/repo).

---

## Proposed fix (await approval)

🔷 Match **A** / **C**: use **`GLib.FileAttribute.STANDARD_CONTENT_TYPE`** via `query_info` / `get_content_type()`, then `has_prefix("text/")`, and keep the language override for `application/x-php`-style types.

🔷 Two sites (same rule, different timing):

1. **`to_real`** — after `detect_language()`: if still not text **and** `GLib.FileUtils.test(…, EXISTS)`, `query_info` (no try/catch — existence gated). Covers **`register`**; skips cleanly when create-via-`write` has no file yet.
2. **`FileBuffer.update_file_metadata_after_write`** — after a successful write, file is known to exist: if still `!is_text`, `query_info` **without** exists check or try/catch; if it becomes text, `saveToDB` (already happens) **and** `project_files.update_from(active_project)` so `child_map` picks it up. Covers **create-via-`write`**.

💩 Optional later: one-off backfill of existing `is_text=0` rows that sniff as `text/*` (not required for the forward fix).

---

### 1. `ollmfilesd/File.vala` — `to_real()`: sniff when on disk

**Why:** `register` and any promote where the file already exists must set `is_text` like `new_from_info`.

**Where:** `to_real`, after parent/`id` setup, around the language-only `is_text` block (before `children.append`).

**Depends on:** none.

#### Keep
```vala
			this.parent = parent_folder;
			this.parent_id = parent_folder.id;
			this.id = 0;
```

#### Remove
```vala
			this.detect_language();
			if (this.language != "") {
				this.is_text = true;
			}
```

#### Replace with
```vala
			this.detect_language();
			if (this.language != "") {
				this.is_text = true;
			}
			if (!this.is_text
				&& GLib.FileUtils.test(this.path, GLib.FileTest.EXISTS)) {
				var content_type = GLib.File.new_for_path(this.path).query_info(
					GLib.FileAttribute.STANDARD_CONTENT_TYPE,
					GLib.FileQueryInfoFlags.NONE,
					null
				).get_content_type();
				this.is_text = content_type != null && content_type != ""
					&& content_type.has_prefix("text/");
			}
```

#### Keep
```vala
			parent_folder.children.append(this);
			this.manager.buffer_provider.create_buffer(this);
			if (this.manager.db != null) {
```

---

### 2. `ollmfilesd/FileBuffer.vala` — `update_file_metadata_after_write()`: sniff after bytes

**Why:** Create-via-`write` only has reliable content-type **after** `write_to_disk`; also refreshes `child_map` when `is_text` flips true.

**Where:** start of `update_file_metadata_after_write` body, before `last_modified` / `saveToDB`.

**Depends on:** §1 for register-only; this section for write-create.

#### Keep
```vala
		protected void update_file_metadata_after_write()
		{
```

#### Add — insert sniff before `last_modified` update
New lines only: content-type sniff + optional `project_files.update_from` when `is_text` flips true.

```vala
			if (!this.file.is_text) {
				var content_type = GLib.File.new_for_path(this.file.path).query_info(
					GLib.FileAttribute.STANDARD_CONTENT_TYPE,
					GLib.FileQueryInfoFlags.NONE,
					null
				).get_content_type();
				this.file.is_text = content_type != null && content_type != ""
					&& content_type.has_prefix("text/");
				if (this.file.is_text && this.file.manager.active_project != null) {
					this.file.manager.active_project.project_files.update_from(
						this.file.manager.active_project
					);
				}
			}
```

#### Keep
```vala
			// Update last_modified from filesystem after writing
			this.file.last_modified = this.file.mtime_on_disk();
			
			// Save to database with sync to disk
			if (this.file.manager.db != null) {
				this.file.saveToDB(this.file.manager.db, null, true);
			}
			
			// Update last_viewed timestamp
			this.file.last_viewed = new GLib.DateTime.now_local().to_unix();
			
			// Notify ProjectManager that file contents have changed (triggers background scanning)
			this.file.manager.on_file_contents_change(this.file);
		}
```

---

## Next

- ✅ User closed 2026-09-02.

✔️ Follow-up applied: `"is-text"` / `"language"` on `read_dir_update` `copy_from` except list + assign onto `old_item` (same as `is-ignored` / `is-repo`).
