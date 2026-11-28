# Phone Agent Pi mid-file `write` re-activates edit mode instead of applying fences

**Status:** ✅ — **Closed (won't fix this path).** Enable-then fence streaming is abandoned; evidence preserved here. Product direction: [activation not viable](../2026-11-27-ISSUE-edit-mode-tool-activation-plan-not-viable.md).

## User decisions required

- None.

## User reported

- 🔷 On the phone yesterday, ran an edit-file / `write` harness test against the desktop project (same kind of test as gtktest1 on desktop).
- 🔷 It hit the same class of problems as before: the agent did not complete a clean edit-mode apply; chat felt stuck or messy; review queue and file state looked wrong.
- 🔷 Wants a new bug report using the prior gtktest1 analysis and standard report shape.

## Success scenario

- Android chat POC → desktop `ollmfilesd`, Agent Pi, `gtktest1/test-file.txt`, mid-file edit (~10 lines):
  - One `write` (`line_numbers` or `complete_file`) + streamed fence(s) in the same assistant turn, then STOP — no back-to-back “Edit mode activated” loop.
  - Edit applied via edit mode (not a long `bash` fallback spiral).

## Current behavior

- What you said
  - “this is a test file can you change say 10 lines in the middle of it to see if it works” (phone session `2026/11/22/03-22-18.json`).
- Tool calls (session `03-22-18.json`, opening ~03:22:44–03:22:57)
  - `read` — `…/gtktest1/test-file.txt` (twice; second read around lines 20–21).
  - `write` — same path, `edit_mode=line_numbers`, `overwrite=false` — **03:22:49** (Edit mode activated; tool reply below — same turn had think only, no fence, then a new turn called `write` again).
  - `write` — same path, `line_numbers` — **03:22:51** (activated again; empty body).
  - `write` — same path, `line_numbers` — **03:22:53** (activated again; empty body).
  - `write` — same path, `line_numbers`, `overwrite=true` — **03:22:57** (activated again; assistant streamed a fence — verbatim below).
  - `write` — same path, `complete_file` — **03:23:00** (activated again; assistant did not finish a single-fence apply before more `write` calls).
- After first `write` (**03:22:49**) — harness sent the model (verbatim tool result):

````text
Edit mode activated for file: /home/alan/gitlive/gtktest1/test-file.txt


Code blocks must include line range in format type:startline:endline e.g.,

```javascript:10:15
the output goes here
```

The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.


Edit mode is on for this path. In this same assistant message only:

1. Output one or more fenced edits per the instructions above.
2. Do not call write again or any other tool for this file in this message.
3. STOP generating after the last fence — the agent will send a confirmation message that your edits have been applied, and you may continue then.
````

- Same completion after that reply — **no fence**; turn ended with **model think-stream only** (not harness text):

```text
I'll replace lines 21-30 (10 lines). Line numbers 1-based inclusive of start, exclusive of end, so lines 21:30 gives lines 21-29 (9 lines). I need 10 lines, so lines 21:31.
```

  - That line is **`think-stream` from the model** (`ornith-1.5:35b`), not a user/agent reminder to follow the tool instructions.
  - After a no-fence turn, [`Stream.send_no_changes_response`](../../liboctools/EditMode/Stream.vala) should `send_append` a **user** message like “You enabled edit mode … but did not provide any code blocks with changes.” Saved session JSON has **no** such `user` line before **03:22:51**; the next visible step is another assistant `write` (empty body).

- First assistant message that included a fence (**03:22:57** `content-stream`) — verbatim:

````text
Editing lines 21–30 (10 lines) in the middle:

```
vala:21:31
The mountains tower high above the valleys below. → The mountains tower high above the shadowed valleys.
Rivers carve their paths through solid stone walls. → Rivers wear through rock over countless years.
Deserts stretch endlessly under the blazing hot sun. → Deserts shimmer under a merciless noon sun.
Oceans hold secrets we may never be able to learn. → Oceans keep secrets buried in the deep.
Forests breathe life into the thin grey air. → Old forests breathe deep in the mist.
Meadows bloom with colors bright and vibrant. → Meadows burst into color, wild and bright.
Waves crash upon the pale sandy shore. → Waves tumble onto the golden, sandy shore.
Thunder rumbles in the distant dark sky. → Thunder rolls across the gathering storm.
Lightning splits the heavy storm clouds above. → Lightning forks through clouds of lead.
Raindrops patter on the tile rooftops below. → Raindrops tap a rhythm on the tiles.
```
````

- Observable outcomes
  - Phone chat showed **Edit Mode Activated** repeatedly on back-to-back `write` calls without completing the mid-file edit.
  - **19** `write` tool rounds before the first `bash` in that session; later overlay/shell path and desktop review noise — **Debugging** / **LLM** (out of scope for the copy fix).

## Codebase observed behavior

- Repeat `write` on the same path replaces the prior edit-mode request — [`liboctools/EditMode/Tool.vala`](../../liboctools/EditMode/Tool.vala) (gtktest1: [`done/2026-11-20-FIXED-desktop-write-file-edit-loop.md`](done/2026-11-20-FIXED-desktop-write-file-edit-loop.md)):

```128:137:liboctools/EditMode/Tool.vala
			foreach (var req in existing_requests) {
				GLib.debug("Tool.activate_request: Cleaning up existing request for file %s (request_id=%d)",
					req.normalized_path, req.request_id);
				req.agent.remove_stream_monitor(req.request_id);
				this.active_requests.remove(req);
			}
			this.active_requests.add(request);
```

- LLM tool copy assembled in [`liboctools/EditMode/Request.vala`](../../liboctools/EditMode/Request.vala) `execute_request()` — today **`line_numbers` leads with** `INSTRUCTIONS_LINE_RANGE` (“Code blocks must include line range…”) **before** explaining that **write** means stream fenced output, not body in the tool call ([`done/2026-11-21-FIXED-write-tool-llm-copy.md`](done/2026-11-21-FIXED-write-tool-llm-copy.md) improved STOP rules but not this ordering).
- No-fence tail: [`Stream.vala`](../../liboctools/EditMode/Stream.vala) `send_no_changes_response` — short “did not provide any code blocks” line; does not point back at the tool result instructions.
- Pending diff load: [`liboccoder/SourceView.vala`](../../liboccoder/SourceView.vala) `show_pending_diff` → `FileHistory.parts` → `change_view.apply`:

```928:955:liboccoder/SourceView.vala
						response = yield this.manager.rpc.call(new OLLMrpc.Request() {
							method = "FileHistory.parts",
							args = OLLMrpc.args("x",
								this.manager.review_files.file_map.get(file.path).approve_id)
						});
					if (response.retval.type() != GLib.Type.INVALID) {
						parts = (Gee.ArrayList<OLLMfiles.FileDiffPart>) response.retval.get_object();
					}
				var proposal = this.change_view.proposal(file, parts);
				this.change_view.apply(proposal);
```

- Empty `parts` reply (no `retval`): [`ollmfilesd/FileHistory.vala`](../../ollmfilesd/FileHistory.vala):

```513:538:ollmfilesd/FileHistory.vala
					request.reply(new OLLMrpc.Response() {
						id = request.id
					});
					return;
			if (rows.size > 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("o", rows)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id
			});
```

- Stacked `file_history` baseline: [`done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md`](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md) — re-verify daemon build on re-test.

## Debugging

### Current debug output

- `~/.cache/ollmchat/ollmfilesd.debug.log` — 2026-11-22, after the opening `write` loop (~11:23 local).

- Same file — GValue criticals near `FileHistory.parts` (example **11:23:29**):

```text
gtype.c:4159: type id '0' is invalid
gvalue.c:104: cannot initialize GValue with type '(null)' …
```

- `~/.cache/ollmchat/ollmchat.debug.log` — review queue growth **11:23:29–11:23:35**:

```text
ReviewBar.vala:1756: review queue files=1 visible=true
…
ReviewBar.vala:1756: review queue files=3 visible=true
```

- `ollmchat.debug.log` — UTF-8 critical on diff load (example **11:24:31**):

```text
gtk_text_buffer_emit_insert: assertion 'g_utf8_validate (text, len, NULL)' failed
ReviewBar.vala:1208: review bar visible=true files=3 parts=1 hunks=1
```

- Desktop `ollmchat.debug.log` — review / `FileHistory.parts` during same run (no phone tool trace in that file).

### Debug code added (remove when complete)

None.

## Proposed fix

**Scope:** LLM-facing **text only** — [`liboctools/EditMode/Request.vala`](../../liboctools/EditMode/Request.vala) (all `edit_mode` values) and no-fence **`send_append`** in [`liboctools/EditMode/Stream.vala`](../../liboctools/EditMode/Stream.vala). No repeat-`write` guard.

- Why
  - Model re-calls `write` with empty body when the tool result leads with fence syntax instead of **how `write` works here**.

### Success tool result — all modes ✔️ applied 2026-11-23

Shared assembly order in `execute_request()`:

1. `Edit mode activated for file: …`
2. `INSTRUCTIONS_WRITE_STREAMING` (stream fences in the assistant message; not body in the tool call)
3. `CODE_BLOCK_REQUIREMENT_*` (same-message STOP rules)
4. Mode tail — `INSTRUCTIONS_LINE_RANGE`, `INSTRUCTIONS_COMPLETE_FILE`, or `INSTRUCTIONS_AST`
5. `OVERWRITE_MESSAGE` when `overwrite=true` on an existing file

`line_numbers` tail opens with “You may start writing…” + example fence, then line-range rules.

### No-fence follow-up (`send_no_changes_response`) ✔️ applied 2026-11-23

- Re-read the write tool result; output a fence in the assistant message; do not call `write` again for that path until then.

### Test

- Phone: repeat “10 lines in the middle” on `gtktest1/test-file.txt`; session should show one `write`, then fenced body, not a chain of empty `write` calls.
- Desktop (**2026-11-27**): Agent Pi, `gtktest1`, create `sample.txt` ~50 lines — same loop after merged tool copy; see **Current behavior** (desktop re-test).

### Re-test 2026-11-27 (desktop, copy fix **in tree**)

- Harness shows new lead copy (`INSTRUCTIONS_WRITE_STREAMING` in tool result — verified in session JSON).
- Model still ends post-`write` turns with **`content_total=0`** and another **`write` tool call** instead of a fence; then **`bash`** fallback. Same pattern as gtktest1 Nov 20 / phone Nov 22.
- Saved sessions: `~/.local/share/ollmchat/history/2026/11/27/08-12-21.json` (3× `write`, 2× `bash`); earlier same morning `08-10-56.json` (1× `write`, 1× `bash` on `test-file.txt`).
- No-fence **`send_append`** user lines **not** present in those JSON transcripts (either not emitted or not persisted before the next `write` — worth harness audit; phone Nov 22 had the same gap).
- **Conclusion:** Reordering tool-result text alone does **not** meet the success scenario for this model.

## LLM

- ℹ️ Repro metadata: 2026-11-22; Android POC → desktop `ollmfilesd`; project `gtktest1`; Agent Pi / `ornith-1.5:35b`; phone history `2026/11/22/03-22-18.json` (failed first send in `03-21-32.json` with UI “Exception has been thrown”).
- ℹ️ Desktop has no copy of that history under `~/.local/share/ollmchat/history/2026/11/22/` — source of truth is phone `…/androidpoc/files/ollmchat/history/…`.
- ℹ️ After **03:23:30** session shows `bash` / overlay rewrites; daemon log matches sandbox noise — not used for **Tool calls** ordering.
- 💩 Same failure family as gtktest1 desktop write-loop ([`done/2026-11-20-FIXED-desktop-write-file-edit-loop.md`](done/2026-11-20-FIXED-desktop-write-file-edit-loop.md)): repeat `write` re-activates edit mode instead of one fence-then-apply.
- ℹ️ Related closed: [desktop write loop](done/2026-11-20-FIXED-desktop-write-file-edit-loop.md), [write LLM copy](done/2026-11-21-FIXED-write-tool-llm-copy.md), [stream-handler criticals](done/2026-11-21-FIXED-edit-mode-stream-handler-criticals.md), [stacked diff baseline](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md).
- ℹ️ Android pairing 2026-11-22 is unrelated.
- ℹ️ **Follow-up criticals (desktop, same run — not fixed by copy change):**
  - **GValue** `type id '0' / cannot initialize GValue with type '(null)'** on `FileHistory.parts` (**11:23:29**) — same failure class as empty-list `retval` in [`done/2026-11-15-FIXED-review-queue-multi-history-and-db-sync.md`](done/2026-11-15-FIXED-review-queue-multi-history-and-db-sync.md); re-check daemon/build if it still fires on a **clean** edit-mode repro (one pending file, no bash spiral).
  - **`gtk_text_buffer_emit_insert: g_utf8_validate` failed** (**11:24:31**) while review bar loaded diff — likely bad on-disk bytes from sandbox/`bash` rewrites, not the phone chat path; confirm with `file` / `hexdump` on `test-file.txt` if it reproduces after copy fix.
  - **Review queue `files=1` → `3`** — stacked pending rows from overlay writes during fallback; related baseline [`done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md`](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md).
- ℹ️ Desktop criticals (GValue, UTF-8, review queue): [gtktest1 review criticals](done/2026-11-24-FIXED-gtktest1-review-criticals-overlay-run.md) (**✅** UTF-8 fixed + daemon restart).
- ✔️ Copy reorder applied in `Request.vala` (`line_numbers`, `complete_file`, `ast_path`) + `Stream.vala` no-fence text — **2026-11-23**; Android APK install attempt **2026-11-24** (see [install write-copy APK](25e5cf51-9f0a-4b98-b414-f78a36712623)).
- ℹ️ Archived **2026-11-28** — user concluded enable-then will **not** be made reliable for primary models; no further fence/copy work on this ticket.
- ℹ️ **Fixability (final):** failure class documented above; superseded by always-on `<write>` spec in [2026-11-27-ISSUE-edit-mode-tool-activation-plan-not-viable.md](../2026-11-27-ISSUE-edit-mode-tool-activation-plan-not-viable.md).
- ℹ️ Downstream: edit-mode loops → `bash` / review noise — [stacked modified chunk loop](../2026-11-24-ISSUE-stacked-modified-chunk-approval-loop.md) (separate).