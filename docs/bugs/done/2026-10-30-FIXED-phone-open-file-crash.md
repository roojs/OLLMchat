# Phone crashes when a file is opened

**Status:** ✅ 2026-10-30. Opening a file no longer aborts. `pending_after` returns `-1` on an empty hunk list.

**Device:** SM-S9380, Android 16, wireless `adb-R5CY134DA0W`. Package `org.roojs.ollmchat.androidpoc` 0.2.0, installed 15:50.

## Problem

- 🔷 Opening a file from the phone file list kills the app. Expected: the file opens and the process stays up.
- 🔷 Actual, 2026-10-30 15:54 and 15:55: the GTK thread aborted. The process was gone by 15:55:40.

## Evidence

- ✔️ 15:54:13 pid 19251, GTK tid 19286, `SIGABRT`. Uptime 53 s. Project `/home/alan/gitlive/OLLMchat`. `File.read` id=11 replied, then `SourceView.vala:532` `path=/home/alan/gitlive/OLLMchat/docs/bugs/2026-10-28-sandbox-git-status-truncates-index.md loaded=true chars=8927`.
- ✔️ Same second, before the abort, on that markdown open:
  - `gtk_source_buffer_set_language: assertion 'GTK_SOURCE_IS_BUFFER (buffer)' failed`
  - `gtk_text_buffer_get_tag_table` / `gtk_text_tag_table_lookup` / `gtk_text_buffer_set_text` / `gtk_text_buffer_set_modified` each `GTK_IS_TEXT_BUFFER` or `GTK_IS_TEXT_TAG_TABLE` failed
- ✔️ The abort line is `gee/arraylist.vala:172:gee_array_list_real_get: assertion failed: (index < _size)`, then `Bail out!`.
- ✔️ Backtrace, both crashes, GTK thread: `abort` ← `g_assertion_message_expr` ← `gee_abstract_list_get` ← `oll_mcoder_diff_hunk_list_pending_after` ← `oll_mcoder_diff_review_bar_update_diff` ← `oll_mcoder_source_view_show_pending_diff` ← `g_task_return_pointer` ← `libocfiles.so` ← `g_main_context_iteration`.
- ✔️ 15:55:16 pid 19786, GTK tid 19808, same abort and the same backtrace. Project `/home/alan/gitlive/app.webkitpdf`. `SourceView.vala:532` `path=/home/alan/gitlive/app.webkitpdf/README.txt loaded=true chars=444`.
- ℹ️ `adb logcat -b crash -d`. The process was not running at 15:55:40 (`pidof` empty).

## Root cause

- ✔️ `ReviewBar.update_diff` clears `hunks`, then calls `this.hunks.pending_after(-1)` when the file is not in the mock-inactive state. `HunkList.pending_after` copies `this` and calls `work.get(0)` with no size check. An open whose part list adds no bands leaves `hunks` empty, and `get(0)` fails `index < _size`. `index_at` in the same class already returns `-1` when `size < 1`. `liboccoder/Diff/ReviewBar.vala`. Caller is `SourceView.show_pending_diff`.
- 💩 The `GTK_SOURCE_IS_BUFFER` lines are a second failure on the markdown open. They are not the abort. The `README.txt` open aborted with the same Gee assertion and those GTK lines were not in that slice.

## Proposed fix

### 1. `liboccoder/Diff/ReviewBar.vala` — `HunkList.pending_after`: empty list

**Why:** `work.get(0)` on an empty copy is the abort. `index_at` already returns `-1` for that case.

**Where:** Start of `pending_after`, before the copy.

**Depends on:** none.

#### Add

Before `var work = new Gee.ArrayList<HunkBand>();`.

```vala
			if (this.size < 1) {
				return -1;
			}
```

## Attempts / changelog

- ℹ️ 2026-10-30 15:55 — crash buffer and pid 19251 / 19786 logcat. No product change.
- ✔️ 2026-10-30 16:01 — `HunkList.pending_after` returns `-1` when `this.size < 1`, same as `index_at`. No other change.
- ✔️ 2026-10-30 16:04 — `adb install -r` of `app-arm64-v8a-debug.apk` succeeded. Launched `ToplevelActivity`, pid 22048.
- ✅ 2026-10-30 16:10 — opening a file on the phone no longer crashes.

## Next

- 🚫 None. Fixed.
