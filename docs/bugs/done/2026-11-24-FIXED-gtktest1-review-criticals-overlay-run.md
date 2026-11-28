# Desktop review criticals after gtktest1 overlay writes (phone harness fallout)

**Status:** ✅

## User decisions required

None.

## User reported

- 🔷 Split from [phone Agent Pi edit-file test](2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md): fix the **GLib criticals** and broken review UX on desktop during that run, not the `write` tool copy.
- 🔷 **2026-11-24** — close report for now: desktop critical pass; **only** hitting UTF-8 insert critical before **ollmfilesd** restart; clear after daemon reboot.

## Success scenario

- Repro or equivalent harness: opening pending review for `gtktest1/test-file.txt` after sandbox overlay edits.
  - No `gtk_text_buffer_emit_insert: assertion 'g_utf8_validate' failed` when the review diff loads.
- Desktop critical sweep (current pass): no new review-load criticals after daemon restart.

## Current behavior

- Context
  - **2026-11-22** phone → desktop `gtktest1`; overlay writes on `test-file.txt` ([phone report](2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md)).
- **2026-11-24** (user)
  - Same UTF-8 critical until **ollmfilesd** restarted (stale in-memory diff parts vs rebuilt reads).
  - After reboot: pending review opens without UTF-8 critical; only critical tracked here was that one.

## Codebase observed behavior

- Daemon empty `parts` reply omits `retval` when rebuild yields no rows — [`ollmfilesd/FileHistory.vala`](../../ollmfilesd/FileHistory.vala) `parts()` (same pattern as [review-queue fix](2026-11-15-FIXED-review-queue-multi-history-and-db-sync.md)).
- Client pending diff: [`liboccoder/SourceView.vala`](../../liboccoder/SourceView.vala) `show_pending_diff` skips `get_object` when `retval` is `GLib.Type.INVALID`.
- `FileHistory.parts` can serve **`live`** hunks without `rebuild_parts` when stamp matches — restart clears bad cached `hunk_*` text built before UTF-8 read fixes.

## Debugging

### Current debug output

- Original run — `~/.cache/ollmchat/ollmfilesd.debug.log` **11:23:29** (`FileHistory.parts`):

```text
gtype.c:4159: type id '0' is invalid
gvalue.c:104: cannot initialize GValue with type '(null)' …
```

- `~/.cache/ollmchat/ollmchat.debug.log` — UTF-8 **11:24:31**:

```text
gtk_text_buffer_emit_insert: assertion 'g_utf8_validate (text, len, NULL)' failed
ReviewBar.vala:1208: review bar visible=true files=3 parts=1 hunks=1
```

### Debug code added (remove when complete)

None.

## Proposed fix

### Phase 1 — `FileHistory.parts` GValue criticals

- Why
  - GObject criticals on Nov 22 run when handling `FileHistory.parts`.
- Outcome
  - **Deferred** — not seen in **2026-11-24** desktop critical pass; reopen if `type id '0'` returns on fresh logs.

### ✅ Phase 2 — Invalid UTF-8 on diff insert

- Root cause
  - Text paths cast `uint8[]` → `string` without UTF-8 validation; `hunk_add`/`hunk_remove` → `ChangeView.apply` → `gtk_text_buffer_set_text`.
  - Stale **`live`** cache on running **ollmfilesd** can keep pre-fix hunks until restart.
- Applied
  - `validate()` / `make_valid()` on text reads: `ollmfilesd`/`libocfiles` `FileBuffer`, `DummyFileBuffer`; `FileHistory.rebuild_parts` backup.
- Verified
  - User: **ollmfilesd** reboot → review diff loads without UTF-8 critical (desktop).

### Phase 3 — Stacked review queue (`files=3`)

- Outcome
  - **Deferred** — not pursued for this close; see [stacked diff baseline](2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md) if queue growth returns.

## LLM

- ✔️ **2026-11-24** — archived to `done/`; user confirmed UTF-8 critical cleared after daemon restart.
- ℹ️ Parent: [2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md](2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md).
- ⏳ Follow-up (optional): Phase 1 GValue decode if criticals recur; `File.read` `msg` cast in `ollmfilesd/File.vala` if client buffer loads bad bytes without local read path.