# Desktop review criticals after gtktest1 overlay writes (phone harness fallout)

**Status:** ⏳

## User decisions required

None.

## User reported

- 🔷 Split from [phone Agent Pi edit-file test](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md): fix the **GLib criticals** and broken review UX on desktop during that run, not the `write` tool copy.

## Success scenario

- Repro or equivalent harness: opening pending review for `gtktest1/test-file.txt` after sandbox overlay edits.
  - No `type id '0' is invalid` / `cannot initialize GValue with type '(null)'` on `FileHistory.parts` handling.
  - No `gtk_text_buffer_emit_insert: assertion 'g_utf8_validate' failed` when the review diff loads.
- Review bar reflects pending edits without spurious multi-file queue growth from a single-file test (when only one file was meant to be pending).

## Current behavior

- Context
  - **2026-11-22** phone → desktop `gtktest1`; after failed edit-mode loop, agent used many `bash` / overlay writes on `test-file.txt` ([phone report](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md)).
- Observable outcomes (desktop)
  - **11:23:29** — GObject criticals cluster when client handles `FileHistory.parts` (same window as review refresh).
  - **11:23:29–11:23:35** — review queue `files=1` → `files=3`.
  - **11:24:31** — UTF-8 critical inserting diff text into the review buffer (`ReviewBar` visible, `files=3`).

## Codebase observed behavior

- Daemon empty `parts` reply omits `retval` when rebuild yields no rows — [`ollmfilesd/FileHistory.vala`](../../ollmfilesd/FileHistory.vala) `parts()` (same pattern as [review-queue fix](done/2026-11-15-FIXED-review-queue-multi-history-and-db-sync.md)).
- Client pending diff: [`liboccoder/SourceView.vala`](../../liboccoder/SourceView.vala) `show_pending_diff` skips `get_object` when `retval` is `GLib.Type.INVALID`.
- Criticals on **2026-11-22** imply another decode or notification path still initializes a `GValue` from invalid type (wire decode, dual RPC connections phone UI vs tool runner — unconfirmed).

## Debugging

### Current debug output

- `~/.cache/ollmchat/ollmfilesd.debug.log` — **11:23:29** (`FileHistory.parts` interleaved with `fetch_pending_approvals`):

```text
gtype.c:4159: type id '0' is invalid
gvalue.c:104: cannot initialize GValue with type '(null)' …
```

- `~/.cache/ollmchat/ollmchat.debug.log` — review queue:

```text
ReviewBar.vala:1756: review queue files=1 visible=true
…
ReviewBar.vala:1756: review queue files=3 visible=true
```

- Same file — UTF-8 (**11:24:31**):

```text
gtk_text_buffer_emit_insert: assertion 'g_utf8_validate (text, len, NULL)' failed
ReviewBar.vala:1208: review bar visible=true files=3 parts=1 hunks=1
```

### Debug code added (remove when complete)

None.

## Proposed fix

Apply after a tight repro (overlay edit on `gtktest1/test-file.txt`, open pending review). No symptom-only guards.

### Phase 1 — `FileHistory.parts` GValue criticals

- Why
  - Criticals persist on Nov 22 run though daemon empty reply omits `retval`.
- Investigate
  - Client decode path for responses with no `retval` (`libocrpc/Client.vala`, notifications vs `call` reply).
  - Whether phone + desktop RPC on same project interleave `parts` with empty live cache.
- Outcome
  - **Remove** / **Replace with** once fault site is confirmed (do not change `OLLMrpc.val` empty-list API — [review-queue fix](done/2026-11-15-FIXED-review-queue-multi-history-and-db-sync.md)).

### Phase 2 — Invalid UTF-8 on diff insert

- Why
  - Review buffer insert fails `g_utf8_validate` after overlay-written file bytes.
- Investigate
  - On-disk `gtktest1/test-file.txt` and `~/.cache/ollmchat/edited/` backup for that run (`file`, `hexdump`).
  - Read/apply path: overlay RPC → buffer → `File.read` → `ChangeView.apply` — fix at byte source, not GTK-only silence.

### Phase 3 — Stacked review queue (if still visible after 1–2)

- Why
  - `files=3` during single-file harness may be multiple `file_history` rows from overlay writes.
- Investigate
  - Re-check [stacked diff baseline](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md) on running daemon; `files.sqlite` for `test-file.txt`.

## LLM

- ℹ️ Parent: [2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md) (**✔️** write copy applied; criticals tracked here).
- ℹ️ Related closed: [review-queue multi-history](done/2026-11-15-FIXED-review-queue-multi-history-and-db-sync.md), [stacked diff baseline](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md).
- ⏳ DEBUG first: reproduce on desktop with `--debug`, then Phase 1 decode investigation.