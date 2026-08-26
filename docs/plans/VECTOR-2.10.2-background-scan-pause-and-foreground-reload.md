# Background Scan: Pause/Resume on Progress Bar and Foreground Reload on Save

## Status

**PROPOSAL** – for review

## Overview

Three changes:

1. **Progress bar: click to pause/resume** – Make the VectorScanBanner progress bar clickable to pause and resume the background scan, and show *(paused – click to resume)* when paused.
2. **Foreground reload on background save** – When the background thread saves to the database (after indexing a file), trigger a reload on the foreground so the in-memory project/file tree stays in sync.
3. **needs_reload and last_db_load** – Fix `Folder.needs_reload()` and `load_files_from_db()` so that updates to `last_vector_scan` (from the background Indexer) cause a reload. Today only `last_modified` is considered, so background indexer updates never trigger a reload.

---

## 1. Click-to-pause/resume on the progress bar

### 1.1 BackgroundScan: pause/resume and `paused_changed` signal

**File:** `libocvector/BackgroundScan.vala`

- **State:** Add `bool scan_paused` plus `GLib.Mutex pause_mutex` and `GLib.Cond resume_cond` (all `private`), used only for pausing in the background loop. The `scan_paused` flag is written from the main thread in `pause()`/`resume()` and read in the background loop under the mutex.
- **API:**
  - `public void pause()` – from main: lock, set `scan_paused = true`, unlock. Emit `paused_changed(true)` on the main thread.
  - `public void resume()` – from main: lock, set `scan_paused = false`, `resume_cond.signal()`, unlock. Emit `paused_changed(false)`.
  - `public bool paused { get; }` – lock, read `scan_paused`, unlock, return.
  - `public void toggle_pause()` – `if (paused) resume(); else pause();`
  - `public signal void paused_changed(bool paused)`
- **Loop in `startQueue()`:** At the top of the `while (true)` loop, *before* `poll()`:

  ```vala
  while (true) {
      // When paused, block until resume (only check when there is still work)
      if (this.scan_paused) {
          this.pause_mutex.lock();
          while (this.scan_paused) {
              this.resume_cond.wait(this.pause_mutex);
          }
          this.pause_mutex.unlock();
      }
      var next_item = this.file_queue.poll();
      // ... rest unchanged
  }
  ```

  Pausing only blocks before taking the next item; a file already being processed will finish first.

### 1.2 VectorScanBanner: clickable bar, paused label, `pause_toggle_requested`

**File:** `ollmapp/VectorScanBanner.vala`

- **State:** `bool scan_paused`, `int last_queue_size`, `string last_current_file` (so the normal label can be restored when unpausing).
- **Logic:**
  - `update_scan_status(queue_size, current_file)` – keep existing behaviour for progress and `total_scan`, and for `queue_size == 0` (hide). For `queue_size > 0`: set `last_queue_size`, `last_current_file`, then call `refresh_label()`, and ensure `reveal_child = true`.
  - `refresh_label()` – if `scan_paused` then `label.label = "Semantic Search Scanning: Paused – click to resume"`, else build the usual `"Semantic Search Scanning: %s - %d/%d files completed"` from `last_current_file`, `last_queue_size`, `total_scan`.
  - `public void update_paused(bool paused)` – set `scan_paused = paused`, call `refresh_label()`.
- **Interaction:**
  - `Gtk.GestureClick` on `progress_bar`. On `pressed` (or `released`), emit `pause_toggle_requested`.
  - `progress_bar.cursor = new Gtk.Cursor.from_name("pointer");` so it’s clear the bar is clickable.
- **Signal:** `public signal void pause_toggle_requested()`

### 1.3 Window: wire banner and BackgroundScan

**File:** `ollmapp/Window.vala`

- When creating and connecting `background_scan` (in the `init_codebase_search`-style block):
  - `vector_scan_banner.pause_toggle_requested` → `background_scan.toggle_pause()`.
  - `background_scan.paused_changed` → `vector_scan_banner.update_paused(paused)`.

---

## 2. Foreground reload when the background saves

### 2.1 `database_saved` signal and emit after `backupDB()`

**File:** `libocvector/BackgroundScan.vala`

- **Signal:** `public signal void database_saved()`
- **Emit:** In `startQueue()`, right after the existing:

  ```vala
  sync_source.set_callback (() => {
      this.sql_db.backupDB ();
      return false;
  });
  sync_source.attach (this.worker_context);
  ```

  add a call to `emit_database_saved()` inside that callback. The callback runs in the worker context; `emit_database_saved()` uses `main_context.invoke` to emit `database_saved` on the main thread.

  **Updated callback:**

  ```vala
  sync_source.set_callback (() => {
      this.sql_db.backupDB ();
      this.emit_database_saved ();
      return false;
  });
  ```

  **Helper (runs on main via `main_context.invoke`):**

  ```vala
  private void emit_database_saved () {
      this.main_context.invoke (() => {
          this.database_saved ();
          return false;
      });
  }
  ```

  So each time the background persists with `backupDB()`, the main thread is notified.

### 2.2 Window: debounced reload on `database_saved`

**File:** `ollmapp/Window.vala`

- **State:** `uint reload_project_timeout_id` (e.g. `0` when none).
- **Handler for `background_scan.database_saved`:**
  - If `reload_project_timeout_id != 0`, `Source.remove(reload_project_timeout_id)`.
  - `reload_project_timeout_id = Timeout.add_seconds(1, () => { ... })` where the callback:
    - Sets `reload_project_timeout_id = 0`.
    - If `project_manager.active_project != null`, call  
      `project_manager.active_project.load_files_from_db.begin((o, r) => { project_manager.active_project.load_files_from_db.end(r); });`
    - Returns `false` (one-shot).

So the foreground reloads at most once per second after the last `database_saved`, and only when there is an active project.

---

## 3. `needs_reload` and `last_db_load` so `last_vector_scan` matters

Today `needs_reload()` uses `MAX(last_modified) FROM filebase` and `last_db_load` is set to `DateTime.now_local().to_unix()`. The Indexer only updates `last_vector_scan`, not `last_modified`, so the max of `last_modified` never changes and the foreground never reloads. We need to treat `last_vector_scan` as a reason to reload and to set `last_db_load` from the DB, not from the clock.

### 3.1 `Folder.needs_reload()`

**File:** `libocfiles/Folder.vala`

- Replace the `SELECT MAX(last_modified) FROM filebase` with a single “max of the newer of the two timestamps per row”:

  ```vala
  var stmt = query.selectPrepare(
      "SELECT MAX(max(last_modified, last_vector_scan)) FROM filebase"
  );
  ```

  (`max(a,b)` is the two-argument SQLite scalar; the outer `MAX` is the aggregate.)

- Keep: `max_mtime = results.get(0)` and `return max_mtime > this.last_db_load` (and the `last_db_load == 0` / `manager.db == null` early returns). The variable can stay `max_mtime` even though it now represents “max of (last_modified, last_vector_scan)”.

### 3.2 `Folder.load_files_from_db()` – set `last_db_load` from DB

**File:** `libocfiles/Folder.vala`

- At the end, replace:

  ```vala
  this.last_db_load = new GLib.DateTime.now_local().to_unix();
  ```

  with the same aggregate used in `needs_reload`:

  ```vala
  var stmt = query.selectPrepare(
      "SELECT MAX(max(last_modified, last_vector_scan)) FROM filebase"
  );
  var results = query.fetchAllInt64(stmt);
  this.last_db_load = (results.size > 0) ? (int64) results.get(0) : 0;
  ```

  so `last_db_load` reflects the DB state at the time of the load. When the background later updates `last_vector_scan`, `MAX(max(last_modified, last_vector_scan))` increases and `needs_reload()` becomes true.

---

## 4. Avoiding the foreground syncing an “old” database

- **Shared in-memory DB:** The main-thread `ProjectManager` and the background worker both use the same `sql_db` (in-memory). Writes from the Indexer (e.g. `file.saveToDB(..., sync: false)`) and `backupDB()` in the background update that shared DB. Any `backupDB()` from the main thread would therefore persist the same, up-to-date in-memory state. The risk is not the on-disk file being overwritten by an “older” in-memory copy.
- **Stale in-memory tree:** The risk is the main thread’s in-memory `Folder`/`File` tree being out of date (e.g. `last_vector_scan` not yet refreshed). If some path were to write filebase rows from that tree without reloading, it could overwrite newer `last_vector_scan` (and similar) values. The intended fix is:
  - **Reload on `database_saved`** (plus debounce) so the active project’s tree is refreshed shortly after each background save.
  - **`needs_reload` and `last_db_load`** so that when we do call `load_files_from_db`, we do not skip it when only `last_vector_scan` has changed.
- **Recommendation:** Any future logic that does a batch write to `filebase` from the in-memory `Folder`/`File` tree should first call `load_files_from_db()` (or otherwise ensure it has the latest DB-backed state) so it does not overwrite `last_vector_scan` or other columns updated by the background. This can be enforced by code review and/or a short note in `Folder` or `ProjectManager`.

---

## 5. Summary of code changes

| File | Changes |
|------|---------|
| `libocvector/BackgroundScan.vala` | `scan_paused`, `pause_mutex`, `resume_cond`; `pause()`, `resume()`, `paused` getter, `toggle_pause()`; `paused_changed` signal; in `startQueue()` block when `scan_paused` and emit `database_saved` after `backupDB()` via `emit_database_saved()`. |
| `ollmapp/VectorScanBanner.vala` | `scan_paused`, `last_queue_size`, `last_current_file`; `refresh_label()`, `update_paused()`; `update_scan_status` uses `refresh_label()`; `Gtk.GestureClick` on `progress_bar` and `pause_toggle_requested`; pointer cursor on the bar. |
| `ollmapp/Window.vala` | `reload_project_timeout_id`; connect `pause_toggle_requested` → `toggle_pause`, `paused_changed` → `update_paused`; connect `database_saved` to debounced `load_files_from_db` for `active_project` (1s, one-shot, cancel previous). |
| `libocfiles/Folder.vala` | `needs_reload()`: `SELECT MAX(max(last_modified, last_vector_scan))`; `load_files_from_db()`: set `last_db_load` from that same query instead of `DateTime.now_local().to_unix()`. |

---

## 6. Behaviour in corner cases

- **Pause then queue empty:** The queue cannot empty while paused because we only `poll()` when not paused. No extra handling.
- **Resume after pause:** The loop continues, `poll()` runs, and processing and `scan_update` continue as before. The banner’s next `update_scan_status` will replace the “Paused – click to resume” text.
- **`database_saved` with no active project:** The debounce callback does nothing if `active_project == null`.
- **Rapid `database_saved`:** The 1s debounce keeps at most one pending `load_files_from_db`; the latest `database_saved` effectively wins.
- **`needs_reload` with empty `filebase`:** `MAX(...)` over no rows is NULL; `fetchAllInt64` gives no rows, so `last_db_load` stays 0 and the existing `if (last_db_load == 0) return true` in `needs_reload` continues to force a load when there is nothing in the DB.

---

## 7. Optional / follow-ups

- **Banner area:** Only the progress bar is clickable. The same `GestureClick` could be attached to the whole banner (or the top bar containing it) if we want a larger hit area; the proposal keeps it to the bar as specified.
- **Pause state across runs:** `scan_paused` is not persisted. A new scan (e.g. new project or new batch) starts unpaused. If we want “remember pause across sessions,” that would be a separate change.
- **Reload duration:** If `load_files_from_db` is slow on huge projects, we might later add a longer debounce or only reload when the codebase UI is visible; for now, 1s debounce is a reasonable default.
