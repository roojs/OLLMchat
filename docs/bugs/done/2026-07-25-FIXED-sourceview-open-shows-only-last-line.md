# FIXED — SourceView: open short file shows only last line (others scrolled away)

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed 2026-07-25

**Started:** 2026-07-25

**Related:**

- ℹ️ Preceding empty-list / register bugs:
  [`2026-07-25-FIXED-write-file-no-project-index-ui.md`](2026-07-25-FIXED-write-file-no-project-index-ui.md)
  (after a later reopen the file finally appeared in the pull-down; this bug is
  what happened on **open**)
- ℹ️ Editor: `liboccoder/SourceView.vala` (`open_file`,
  `restore_cursor_position`, `restore_scroll_position`)
- ℹ️ Right pane show/resize: `ollmapp/WindowPane.vala` (`show_right_pane` —
  multi-idle window resize while editor may already be loading)
- ℹ️ File: `/home/alan/gitlive/app.RooTerm/docs/plans/0.1-base-plan.md`
- ℹ️ Client log: `~/.cache/ollmchat/ollmchat.debug.log` (session ~15:13)

---

## Problem

🔷 After the plan file finally showed in the file pull-down, opening it in the
editor showed **only the last line** (user: line **16**, caret at end of that
line). Other lines felt “hidden somewhere” — not missing from disk; viewport /
SourceView placement suspected.

🔷 Expected: open at top (or saved cursor/scroll); full file visible in a
normal scrolled view.

### Reproduction (observed)

1. Project `app.RooTerm`; file list eventually shows `0.1-base-plan.md`
   (after reopen / post-scan — see related bug).
2. Select file from pull-down → right editor pane opens / focuses.
3. Actual: essentially only the last line in view; content above not visible
   without (presumably) scrolling up.

---

## Evidence

### Disk content is complete

- ✔️ File has **15** newline-terminated lines (`wc -l`); ends with
  `…sessions.\n`. No `}` in the file (user “brace” likely **caret** / STT).
- ✔️ Trailing `\n` → Gtk TextBuffer often exposes an **empty line 16** at EOF.
  Seeing “line 16” + caret at end matches **scrolled to end of buffer**, not a
  truncated file.

### Saved cursor/scroll not the cause

SQLite `filebase` for this path after open attempt:

- ✔️ `cursor_line=0`, `cursor_offset=0`, `scroll_position=0`
- ✔️ `is_text=1`, `language=markdown`

So restore is not intentionally jumping to line 16 from DB.

### Open path (cold app ~15:13)

- ✔️ `Folder.fetch_files` → `total=1 loaded=1` (file listed).
- ✔️ User select → `File.activate` (`id=8` at 15:13:44).
- ℹ️ No `File.read` RPC (editor loads via local
  `GtkSourceFileBuffer.read_async` from disk).

### Repro with debug (17:09:47) — same file, `--debug`

Sequence after `File.activate` (`id=14`) opening
`…/app.RooTerm/docs/plans/0.1-base-plan.md` (18 disk lines → buffer
`buffer_lines=19`):

```text
17:09:47.412  open before restore
              buffer_lines=19 insert_line=18
              saved_cursor=0:0 saved_scroll=0
              realized=yes visible=yes
              vadj value=0.0 upper=18.0 page=0.0

17:09:47.418  navigate_to_line line=0 scroll_to_iter=yes
              realized=yes
              vadj value=0.0 upper=18.0 page=0.0

17:09:47.418  restore_cursor placed cursor=0:0
17:09:47.419  restore_scroll skipped scroll_position=0

17:09:47.419  open after restore
              insert_line=0 insert_offset=0
              vadj value=0.0 upper=18.0 page=0.0

17:09:47.647  open idle after layout (~230ms later)
              insert_line=0
              vadj value=0.0 upper=892.0 page=892.0
```

✔️ Confirmed from this dump:

1. After load, insert mark is at **EOF** (`insert_line=18`) before any restore.
2. DB restore targets are **top** (`saved_cursor=0:0`, `saved_scroll=0`) — not line 16.
3. Cursor/`scroll_to_iter` run while **`page_size=0`** (ScrolledWindow not laid
   out yet). `scroll_to_iter` returns yes but cannot place a real viewport.
4. `restore_scroll` **skips** when `scroll_position==0` — no Idle scroll-to-top
   after layout.
5. ~230ms later layout arrives (`page=892`, `upper=892`); insert stays at 0 /
   `value=0`, but placement already raced the zero-page restore.

---

## Root cause

✔️ **Scroll/cursor restore runs before the editor ScrolledWindow has a
non-zero `page_size`.** Buffer load leaves the insert mark at EOF; immediate
`navigate_to_line(0)` / `scroll_to_iter` with `page=0` does not establish a
stable top viewport; `restore_scroll` never Idle-scrolls when saved scroll is
0. Short files make the EOF / bottom-of-pane placement obvious.

🚫 Ruled out: missing bytes on disk; DB asking for line 16 / EOF.

---

## Proposed fix

✔️ Applied. Idle restore uses early return (no `else`) per user.

### Plain English

1. **Defer cursor + scroll restore until after layout** (Idle) — including when
   saved scroll is 0 (top). Today only `scroll_position > 0` gets Idle.
2. **Idle-scroll to line 0 when `scroll_position <= 0`** so first opens get a
   real top placement once `page_size > 0`.
3. **Remove temporary `GLib.debug`** in the same apply (debug already paid for).

🚫 Do not change the markdown file on disk.

### `liboccoder/SourceView.vala` — `open_file` defer restore

#### Remove

```vala
			// Restore or set cursor position
			if (line_number != null) {
				GLib.debug("open navigate override line=%d path=%s", line_number, file.path);
				this.navigate_to_line(line_number);
			} else {
				this.restore_cursor_position(file);
				this.restore_scroll_position(file);
			}

			Gtk.TextIter insert_after;
			gtk_buffer.get_iter_at_mark(out insert_after, gtk_buffer.get_insert());
			GLib.debug(
				"open after restore path=%s insert_line=%d insert_offset=%d realized=%s vadj value=%.1f upper=%.1f page=%.1f",
				file.path,
				insert_after.get_line(),
				insert_after.get_line_offset(),
				this.source_view.get_realized() ? "yes" : "no",
				this.scrolled_window.vadjustment.value,
				this.scrolled_window.vadjustment.upper,
				this.scrolled_window.vadjustment.page_size
			);
			GLib.Idle.add(() => {
				if (this.current_file == null) {
					return false;
				}
				Gtk.TextIter idle_insert;
				this.source_view.buffer.get_iter_at_mark(
					out idle_insert,
					this.source_view.buffer.get_insert()
				);
				GLib.debug(
					"open idle after layout path=%s insert_line=%d realized=%s vadj value=%.1f upper=%.1f page=%.1f",
					this.current_file.path,
					idle_insert.get_line(),
					this.source_view.get_realized() ? "yes" : "no",
					this.scrolled_window.vadjustment.value,
					this.scrolled_window.vadjustment.upper,
					this.scrolled_window.vadjustment.page_size
				);
				return false;
			});
```

#### Replace with

Capture `line_number` / `file` for the Idle; restore only after layout.
Drop the temporary open-after / open-idle debug (before-restore debug block
above this — also remove in the same apply; see Attempts).

```vala
			var open_line = line_number;
			var open_file_ref = file;
			GLib.Idle.add(() => {
				if (this.current_file != open_file_ref) {
					return false;
				}
				if (open_line != null) {
					this.navigate_to_line(open_line);
				} else {
					this.restore_cursor_position(open_file_ref);
					this.restore_scroll_position(open_file_ref);
				}
				return false;
			});
```

Also **Remove** the whole `open before restore` debug block (bounds /
`insert_before` / `GLib.debug(...)`) immediately above that Restore section.

### `liboccoder/SourceView.vala` — `restore_scroll_position` always Idle

#### Remove

```vala
		private void restore_scroll_position(OLLMfiles.File file)
		{
			if (file.scroll_position <= 0) {
				GLib.debug(
					"restore_scroll skipped scroll_position=%d path=%s",
					file.scroll_position,
					file.path
				);
				return;
			}
			// Use Idle to restore scroll position after layout is complete
			GLib.Idle.add(() => {
				var buffer = this.source_view.buffer;
				Gtk.TextIter iter;
				if (!buffer.get_iter_at_line(out iter, file.scroll_position)) {
					GLib.debug(
						"restore_scroll idle line missing scroll_position=%d path=%s",
						file.scroll_position,
						file.path
					);
					return false;
				}
				var scrolled = this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.0);
				GLib.debug(
					"restore_scroll idle scroll_position=%d scroll_to_iter=%s vadj value=%.1f upper=%.1f page=%.1f path=%s",
					file.scroll_position,
					scrolled ? "yes" : "no",
					this.scrolled_window.vadjustment.value,
					this.scrolled_window.vadjustment.upper,
					this.scrolled_window.vadjustment.page_size,
					file.path
				);
				return false;
			});
		}
```

#### Replace with

Treat `scroll_position <= 0` as line 0; always Idle `scroll_to_iter` (no skip,
no debug).

```vala
		private void restore_scroll_position(OLLMfiles.File file)
		{
			var scroll_line = file.scroll_position > 0 ? file.scroll_position : 0;
			GLib.Idle.add(() => {
				if (this.current_file != file) {
					return false;
				}
				var buffer = this.source_view.buffer;
				Gtk.TextIter iter;
				if (!buffer.get_iter_at_line(out iter, scroll_line)) {
					return false;
				}
				this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.0);
				return false;
			});
		}
```

### Also strip remaining temporary debug

#### Remove from `restore_cursor_position` / `navigate_to_line`

All `GLib.debug(...)` added for this bug (skipped / placed / scroll_to_iter
vadj dumps). Keep behaviour; drop only the debug calls + any locals used solely
for those messages.

---

## Attempts / changelog

- ✔️ Checked disk bytes, SQLite cursor/scroll, `open_file` restore vs Idle,
  15:13 client log (`fetch_files` + `File.activate`).
- ✔️ **Debug added** in `liboccoder/SourceView.vala` (temporary).
- ✔️ **Repro log captured** at `17:09:47` in
  `~/.cache/ollmchat/ollmchat.debug.log` (quoted under Evidence).
- ✔️ Root cause confirmed from `page=0` during restore +
  `restore_scroll skipped` for 0.
- ✔️ Fix fences written above.
- ✔️ Applied: defer restore to Idle (early return, no else); Idle-scroll
  line 0 when `scroll_position <= 0`; removed temporary `GLib.debug`.
- ✔️ `open_file` takes `int line_number = -1` (not `int?` / null); override
  when `> -1`.

---

## Next

Archived to `docs/bugs/done/` as FIXED (user closed 2026-07-25).
