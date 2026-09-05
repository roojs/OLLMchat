# 4.2.3. URGENT - SourceView inline diff (approve / reject)

> **Do not update `docs/plans/CODER-1.0-summary.md` for this plan.**

**Status:** **URGENT** · **⏳** phased — Phases **1–3** implementable on settled model; Phase **4** (per-hunk approval UI) **design open** until we reach it

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/4.2-DONE-code-editor-tool.md`](done/4.2-DONE-code-editor-tool.md) — Phase 6 (split from ⏳ FUTURE)

**Related:**

- ℹ️ Shipped list + approve/reject: [`done/2.10.4.26-DONE-file-history-approval-knock-on.md`](done/2.10.4.26-DONE-file-history-approval-knock-on.md)
- ℹ️ Daemon approve/revert: [`done/2.10.4.25-DONE-file-history-approval.md`](done/2.10.4.25-DONE-file-history-approval.md)
- ℹ️ Diff library: [`done/5.2-DONE-diff-match-patch-simple-port.md`](done/5.2-DONE-diff-match-patch-simple-port.md) — `OLLMfiles.Diff.Differ`
- ℹ️ Hunk merge reference: [`examples/oc-diff.vala`](../../examples/oc-diff.vala)
- ℹ️ Worked example (seven-line walkthrough): [`CODER-4.2.3.1-source-view-diff-walkthrough-hello.md`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md)

---

## Purpose

### Phases (ship order)

| Phase | Scope | Design |
| ----- | ----- | ------ |
| **1** | SQLite + migrate — `file_diff_part`, drop legacy `status` | **Settled** (DDL below) |
| **2** | `SourceView` inline unified-diff **rendering** (gutter, green/red) | **Settled** for whole pending chunk |
| **3** | **View** pending file with changes — wire backup vs disk into editor | **Settled** (baseline = `backup_path`) |
| **4** | Per-hunk / block **approval flow** (approve / reject / unapprove) | **Open** — design when Phase 3 lands |

### Confirmed (all phases)

- 🔷 **Disk vs review** — file on disk is **always the agent end result** (full diff already applied when the agent wrote). **Approve** = DB + UI only (does **not** write disk). **Reject** = restore disk from **`backup_path`** + DB (the only review action that undoes content on disk).
- 🔷 Pending-approval files show an **inline unified diff** in `SourceView` (not a second editor pane).
- 🔷 **Secondary gutter** — baseline line numbers beside the normal gutter.
- 🔷 **Added** lines: green background (pending hunk only).
- 🔷 **Removed** lines: red background (pending hunk only); interleaved rows (unified-diff style).
- 🔷 **Approved hunk** — DB + UI only; **disk unchanged** (Phase **4**):
  - **Added** lines: highlight **off**; normal editor text (already on disk).
  - **Removed** lines: **no red interleaved rows** in the diff view (deletion already on disk; overlay dropped).
- 🔷 **Rejected hunk** — **writes V_disk** (undo that hunk only); insert **`file_diff_part`** with **`accepted=0`**; overlay off (Phase **4**).
- ✔️ Per-file **Approve** / **Reject** / changed-files list on **`Approvals`** bar — shipped today; **placement of destructive / bulk actions** is still ⏳ (Phase **4**).
- 🔷 Destructive review actions (whole-file reject, **approve all files**, reject all) must **not** sit as casual primary UI — tuck away (e.g. changes-list menu), with explicit revert (Phase **4**).

### Open (Phase 4 — decide when we get there)

- 🔷 ⏳ **Partial approval** — user may accept **some** hunks/lines/chunks, not only whole-file approve.
- 🔷 **What the diff is against** — **settled for Phases 2–3:** `file_history.backup_path` (**V_backup**) vs **V_disk**.
- 🔷 **Intermediate approved state** — **`file_diff_part.accepted`** + diff UI only (disk already final); **`file_history.reviewed`** = all hunks decided, not “chunk accepted”.
- 🔷 **`reviewed` only on `file_history`** — `0` / `1` only; **no `reviewed` column on `file_diff_part`**.
- 🔷 ⏳ **Stacked LLM edits** — file still pending (or partly approved); agent writes again; what diff do we show?
- 🔷 ⏳ **Undo approval vs undo edit** — approval rollback must **not** rely on editor undo/redo (see **Cursor contrast** below).
- 🔷 ⏳ **Bulk approve all files** — if offered at all, placement, confirmation, and **revert bulk approve** (see **Destructive actions**).

**Suggested order**

1. 🔷 ⏳ **Phase 1** — DB + migrate (`file_diff_part`; drop legacy `status`). Spec fences in **Phase 1** before coding.
2. 🔷 ⏳ **Phase 2** — `SourceView` diff **render** (secondary gutter, green/red overlays). Spec after Phase 1.
3. 🔷 ⏳ **Phase 3** — open pending file → load **V_backup** vs **V_disk** → show Phase 2 overlay. Spec after Phase 2.
4. 🔷 ⏳ **Phase 4** — design per-hunk approve / reject / unapprove + destructive placement; then implement. **Do not invent UI** before this design pass.

---

## Phase 1 — Database + upgrade

- 🔷 Create **`file_diff_part`** (child of **`file_history`**).
- 🔷 Migrate **`file_history`**: drop legacy **`status`**; map old `status != 0` → `reviewed=1`.
- 🔷 ⏳ UNIQUE `(file_history_id, part_index)` when table lands.
- 🔷 ⏳ Daemon / client can **read** parts for a chunk (no UI yet).
- 🔷 ⏳ Derived hunk-file path helper (formula under **SQLite model**) — write path only; no approve RPC yet.
- 🚫 No SourceView changes in this phase.
- 🚫 No per-hunk approve / reject RPC beyond what whole-file already does.
- ℹ️ Full DDL + interaction rules: **Design — SQLite model** below.
- ℹ️ Implementation fences: add under this heading when coding starts (Remove / Replace / Add).

---

## Phase 2 — SourceView diff rendering

- 🔷 Inline **unified-diff** overlay in `SourceView` (not a second pane).
- 🔷 **Secondary gutter** — baseline (**V_backup**) line numbers beside the normal gutter.
- 🔷 **Added** lines: green background; **Removed** lines: red interleaved rows.
- 🔷 Drive from two strings (**V_backup**, **V_disk**) via **`OLLMfiles.Diff.Differ`** — no approval state yet (treat whole chunk as pending).
- 🔷 CSS / markers in `resources/style.css` (or existing SourceView styles).
- 🚫 No per-hunk approve / reject controls yet (Phase **4**).
- 🚫 Do not wire “which file is pending” here if that belongs in Phase **3** — render API can take two texts + show overlay.
- ℹ️ Touch points (names only until fences): `liboccoder/SourceView.vala`, `resources/style.css`.
- ℹ️ Implementation fences: add under this heading after Phase 1 lands.

---

## Phase 3 — View file with changes

- 🔷 When user opens / focuses a **pending-approval** file, editor enters **diff mode**.
- 🔷 Resolve active chunk: newest pending **`file_history`** for path; **V_backup** = `backup_path`; **V_disk** = current file content.
- 🔷 Call Phase **2** render with those two texts.
- 🔷 Leave / exit diff mode when file is no longer pending (whole-file approve / reject as shipped today still works).
- 🔷 Changed-files list / `Approvals` bar still drive **which** file is under review (shipped); this phase only shows the inline diff for that file.
- 🚫 No new per-hunk approval UI (Phase **4**).
- 🚫 No carry-forward / stacked-edit merge UI (v1: active chunk only — see Flow B deferred notes).
- ℹ️ Touch points (names only): `liboccoder/Approvals.vala`, `liboccoder/SourceView.vala`, `libocfiles/FileHistory.vala` / daemon as needed to expose backup text.
- ℹ️ Implementation fences: add under this heading after Phase 2 lands.

---

## Phase 4 — Approval flow of blocks (design then implement)

ℹ️ **Stop and design** when Phase 3 works. Do not invent gutter buttons / menus from this section alone.

- 🔷 Per-hunk **Approve** / **Reject** / **Unapprove** (Flows A, A1, D, E partial).
- 🔷 Insert / delete **`file_diff_part`** rows; set **`file_history.reviewed`** when every hunk decided.
- 🔷 Overlay off for decided hunks (approved = keep on disk; rejected = undo hunk on **V_disk**).
- 🔷 Destructive / bulk placement (changes-list menu, confirm, revert) — see **Destructive actions**.
- 🔷 ⏳ Close remaining open bullets (stacked edit, carry-forward, bulk) before coding fences.
- ℹ️ Walkthrough + SQLite model below stay the contract reference for this phase.
- 🚫 No Vala fences for Phase 4 until user signs off the design pass.

---

## Design — user walkthrough (flows)

ℹ️ **Goal:** one readable path from “agent wrote the file” → “user clicks approve on hunks” → “what SQLite holds” → “agent writes again” → “carry-forward / re-review”. Names below are **proposal** until you sign off.

### Vocabulary

- **V_backup** — snapshot at **`file_history.backup_path`** (content **before** that write chunk).
- **V_disk** — file content **on disk** (agent end result **after** that write; updates on each new agent write).
- **Write chunk** — one agent write → one **`file_history`** row linking **V_backup** and **V_disk**.
- **Hunk** — one contiguous block in the inline diff overlay (added/removed lines the user sees as a unit).
- **Diff part** — one acted-on hunk within a write chunk → one row in **`file_diff_part`** (child of **`file_history`**). **No row** = hunk still pending.

### Worked example — `hello.vala`

ℹ️ **Moved to sub-plan** — many nested code blocks broke Cursor markdown preview on this file.

- [`CODER-4.2.3.1-source-view-diff-walkthrough-hello.md`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md) — seven-line file, **SourceView** markers, **SQLite** snapshots at each step (partial approve, stacked edit, unapprove, per-hunk reject).

### Flow A — Agent writes; user partial-approves (happy path)

**Setup:** `foo.vala` **V_disk** is old content. Agent writes; **V_disk** becomes the new end result (hunks **A**, **B**). **V_backup** = snapshot before that write.

1. **Agent write**
   - User: file in changed-files list; editor in **diff mode**
   - **V_disk:** new end result (diff already applied)
   - **V_backup:** pre-write snapshot (`file_history.backup_path`)
   - SQLite: `file_history` **H1** — `reviewed=0`, `backup_path` → **V_backup**
2. **First look**
   - User: hunk **A** (~line 2) green/red overlay; hunk **B** (~5) pending overlay
   - **V_disk:** unchanged
3. **Approve hunk A**
   - User: clicks **Approve** on hunk **A**
   - **V_disk:** unchanged (approve does not write disk)
   - SQLite: insert **`file_diff_part` P1** — `file_history_id=H1`, `part_index=0`, `accepted=1`
4. **Partial state**
   - User: **A** — no diff overlay (normal text); **B** still green/red overlay
   - **V_disk:** unchanged
   - SQLite: **H1** still `reviewed=0` — hunk **B** has no part row yet
5. **Approve hunk B**
   - User: clicks **Approve** on hunk **B**
   - **V_disk:** unchanged
   - SQLite: insert **P2** — `part_index=1`, `accepted=1`; set **H1** `reviewed=1`; `filebase.is_need_approval=0`

ℹ️ **Whole-file Approve** (today and partial) = set **`file_history.reviewed=1`** — **no disk write**; per-hunk accept/reject detail lives on **`file_diff_part`** only when partial UI ships.

### Flow A1 — Same setup; user approves hunk A, rejects hunk B

**Setup:** same as Flow A through step 4 — **P1** approved, **B** still pending overlay.

1. **Reject hunk B**
   - User: clicks **Reject** on hunk **B** (destructive — per-hunk)
   - **V_disk:** **written** — undo **B** only (inverse of hunk **B** patch); **A** stays (already accepted)
   - SQLite: insert **`file_diff_part` P2** — `file_history_id=H1`, `part_index=1`, `accepted=0`
2. **After reject**
   - User: **A** — normal text (unchanged from step 4); **B** — overlay off; editor shows **V_disk** without **B**’s agent changes
   - **V_disk:** **V_backup + A** (agent’s **B** hunk reverted on disk)
   - SQLite: **P1** `accepted=1`; **P2** `accepted=0`; **H1** `reviewed=1`; `filebase.is_need_approval=0`

**Data snapshot after step 2**

```
file_history H1
  id=1  path=foo.vala  reviewed=1  backup_path -> V_backup

file_diff_part
  P1  file_history_id=1  part_index=0  accepted=1  decided_at=...
  P2  file_history_id=1  part_index=1  accepted=0  decided_at=...

filebase (foo.vala)
  is_need_approval=0

disk
  V_disk = V_backup with hunk A kept, hunk B reverted
```

ℹ️ **`file_history.reviewed`** = user finished this write chunk (`0` pending, `1` all hunks decided). **Accept vs reject** lives only on **`file_diff_part.accepted`** — a chunk can mix accepted and rejected parts (Flow A1). **No accept/reject flag on `file_history`.**

ℹ️ **Approve** vs **Reject** on a part:

- **Approve part** — **V_disk** unchanged; insert **`file_diff_part`** with **`accepted=1`**; overlay off.
- **Reject part** — **V_disk** written (undo that hunk); insert **`file_diff_part`** with **`accepted=0`**; overlay off.

🔷 **Chunk closed** when every hunk has a **`file_diff_part`** row (mix of **`accepted`** is fine). Set **`file_history.reviewed=1`** — means no hunks left to decide, **not** “whole chunk accepted” or “whole chunk rejected”.

🔷 ⏳ **Per-hunk reject** uses hunk file at derived path + **`PatchApplier`** (or equivalent) on daemon — only action besides whole-file **Flow E** that writes **V_disk**.

### Flow B — Agent writes again while review incomplete (stacked edit)

**Setup:** After Flow A step 4 (only **A** approved), agent writes again before user approves **B**.

1. **Second write**
   - User: notification — file changed again
   - **V_disk:** updated end result
   - **V_backup** for **H2:** snapshot before this write (= prior **V_disk**)
   - SQLite: `file_history` **H2** pending, `backup_path` → **V_backup**
2. **Active diff switches to H2**
   - User: diff overlay for **H2** (**V_backup** vs **V_disk**)
   - SQLite: **H1** partial; **P1** still `accepted=1` on **H1**; no **P2** row (hunk **B** pending)
3. **New chunk only** (no Flow C in v1)
   - User: diff overlay for **H2** only (**V_backup** vs **V_disk**)
   - SQLite: **H1** partial; **P1** frozen — no cross-chunk match

🔷 ⏳ **Open:** does partial progress on **H1** **block** the agent, **merge** into **H2**, or **fork** a new review session? Walkthrough assumes **H2** is the active diff; **H1** hunks not yet approved may be **obsolete** or **re-targeted**.

### Flow C — Carry-forward / re-approve after newer write

ℹ️ **Consumer job** (daemon + `SourceView` / approvals UI) — **not** `OLLMfiles.Diff` or any generic diff library.

- Library provides: **`Differ`**, hunks/patches between two texts (**V_backup** vs **V_disk**).
- Consumer provides: which **`file_history`** is active, what's already approved in **`file_diff_part`**, whether to match old parts into a new chunk, overlay on/off.

When **H2** exists, consumer **may** (⏳ deferred — see below):

1. Read hunk file at derived path for an approved **`file_diff_part`** on an older chunk.
2. Call **`Differ`** for **H2** (**V_backup** vs **V_disk**).
3. Match hunk in the new diff (app logic + UI) — **no library API for “carry-forward”**.

🔷 ⏳ **Deferred for v1** — if **H2** lands, review **H2** only; do not ship cross-chunk matching until explicitly requested.

🔷 ⏳ No silent auto-approve on carry-forward unless user prefers “trust carried hunks” setting.

### Flow D — Unapprove one hunk (not editor undo)

1. User **Unapprove** on hunk **A** (was **P1**)
   - SQLite: **delete P1** row ⏳
   - Disk: **unchanged**
2. Diff overlay for **A** returns — green added / red removed rows for **A**
   - **H1** `reviewed=0` until every hunk has a part row again

ℹ️ **Not** `Ctrl+Z`. **`file_diff_part`** + **`file_history`** is the audit trail. **Reject** (Flow E) is what actually rewrites disk.

### Flow E — Reject (writes disk)

User picks **Reject** (destructive; menu/bar TBD):

- **Disk:** restore from **`reject_id`** **`backup_path`** (today: newest `file_history` row with backup) — **undoes the agent diff on disk**.
- **SQLite:** **`file_history.reviewed=1`** (chunk done — not “accepted”); insert pending hunks as **`file_diff_part`** with **`accepted=0`** ⏳.
- **`filebase.is_need_approval=0`**; client **`File.read`**.

🔷 ⏳ **Per-hunk reject** — undo one hunk on **V_disk** (see **Flow A1**); **whole-file reject** — restore full **V_backup** (**Flow E**).

### Flow F — Bulk approve all files

User opens **changes-list menu** → **Approve all pending** → confirm “**N** files, **M** parts”:

- One RPC: for each pending **`file_history`**, set `reviewed=1`; insert all hunks as **`file_diff_part`** with `accepted=1`.
- **Disk unchanged** (same as single approve — DB only).

---

## Design — SQLite model (proposal)

ℹ️ Shipped DDL today: [`ollmfilesd/FileHistory.vala`](../../ollmfilesd/FileHistory.vala) **`init_db`** (still has legacy **`status`** column until this plan ships — drop on migrate). **Partial approve adds one child table** — not a second parallel timeline.

### `file_history.reviewed`

🔷 **`file_history.reviewed`** — `0` = chunk not fully reviewed; `1` = every hunk in the chunk has a **`file_diff_part`** row. **No accept/reject on the parent row** — mixed outcomes live on parts only.

🔷 **No `reviewed` on `file_diff_part`** — per-hunk state:

- **No row** — hunk pending (green/red overlay).
- **Row + `accepted=1`** — user approved; overlay off; **V_disk** unchanged.
- **Row + `accepted=0`** — user rejected; overlay off; hunk undone on **V_disk**.

🔷 **Whole-file paths without parts** (shipped today, or bulk): set **`file_history.reviewed=1`** only — no **`accepted`** column on **`file_history`**. Whole-file **reject** still writes disk; insert all hunks as **`file_diff_part`** with **`accepted=0`**, or just **`reviewed=1`** when there are no part rows yet.

### What we already store (whole-file review)

**`file_history`** already holds the write chunk:

- **`backup_path`** — **V_backup**
- **`reviewed`** — `0` / `1` (chunk open / all hunks decided)
- **`path`**, **`filebase_id`**, **`timestamp`**, **`change_type`**, **`since_id`**, …

**`filebase.is_need_approval`** — file is in the pending review list.

Whole-file approve ([`FileHistory.approve`](../../ollmfilesd/FileHistory.vala)): set **`reviewed=1`** on pending **`file_history`** rows — **no disk write**, no per-hunk rows until partial UI. Partial world: **`reviewed=1`** on **`file_history`** + **`accepted=1`** on all part rows (or **`reviewed=1`** alone when no part rows). **`backup_path`** exists for **reject** and diff baseline only.

### Proposed: one child table

Each diff hunk belongs to exactly one **`file_history`** row. **No `file_approval_batch`**, **no duplicate `filebase_id`**, **no `seq`**, **no path column on the child** — hunk file location is **derived** from row ids + parent **`file_history.path`** (same cache family as backups).

```sql
CREATE TABLE IF NOT EXISTS file_history (
	id INTEGER PRIMARY KEY,
	path TEXT NOT NULL DEFAULT '',
	filebase_id INT64 NOT NULL DEFAULT 0,
	timestamp INT64 NOT NULL DEFAULT 0,
	change_type TEXT NOT NULL DEFAULT '',
	base_type TEXT NOT NULL DEFAULT '',
	backup_path TEXT NOT NULL DEFAULT '',          -- before-write snapshot file; diff + reject
	reviewed INTEGER NOT NULL DEFAULT 0,           -- 0 chunk open, 1 all hunks decided
	since_id INT64 NOT NULL DEFAULT 0,             -- pending-list delta poke
	alias_target TEXT NOT NULL DEFAULT '',
	moved_to TEXT NOT NULL DEFAULT '',
	moved_from TEXT NOT NULL DEFAULT '',
	agent_id INTEGER NOT NULL DEFAULT 0
);
-- migrate: drop legacy status column; map old status != 0 -> reviewed=1

CREATE TABLE IF NOT EXISTS file_diff_part (
	id INTEGER PRIMARY KEY,
	file_history_id INT64 NOT NULL DEFAULT 0,      -- parent write chunk (required)
	part_index INTEGER NOT NULL DEFAULT 0,         -- hunk index in unified diff for that chunk
	accepted INTEGER NOT NULL DEFAULT 0,             -- 0 reject hunk, 1 accept hunk
	decided_at INT64 NOT NULL DEFAULT 0             -- unix time when row inserted; 0 = never (no row)
);
-- UNIQUE (file_history_id, part_index) ⏳
-- hunk pending: no row for that part_index
-- chunk open: file_history.reviewed=0 OR any hunk lacks a part row
-- chunk closed: every hunk has a row -> file_history.reviewed=1
-- whole-file approve (no parts): file_history.reviewed=1 only
```

### Derived hunk file path (not in SQLite)

ℹ️ Shipped backups: [`FileHistory.create_backup`](../../ollmfilesd/FileHistory.vala) stores **`backup_path`** in DB (written once at insert). **Hunk files differ:** path is **computed** from ids + parent path — no extra column.

🔷 ⏳ **Formula** (one shared helper in daemon + client when spec exists):

```
~/.cache/ollmchat/edited/parts/{file_history_id}-{file_diff_part.id}-{part_index}-{basename}.patch
```

- **`basename`** — `GLib.Path.get_basename(file_history.path)` from join on **`file_history_id`**
- **`file_history_id`** + **`part_index`** + **`file_diff_part.id`** — unique, stable after row insert
- **Exists?** — `GLib.FileUtils.test(derived_path, EXISTS)`; no row field needed
- **Format** ⏳ — unified-diff hunk text or serialised **`OLLMfiles.Diff.Patch`**
- **Cleanup** — delete derived path when parent **`file_history`** row cleaned up / rejected

ℹ️ Carry-forward: read hunk **files** at derived paths for approved parts; match against new diff overlay.

ℹ️ **Partial approve does not apply patches to disk** — disk already matches agent end result; **`file_diff_part`** + SourceView overlay track what the user has reviewed.

### How tables interact

```
  V_disk: always agent end result (updates on each agent write)

  file_history H1 (backup_path -> V_backup, reviewed=0)
        |
        +-- file_diff_part  P1  accepted=1   (overlay off; hunk kept)
        +-- (no P2 row)                  (hunk B pending; green/red overlay)

  Approve part  ->  insert part accepted=1  (+ UI; V_disk unchanged)
  Reject part   ->  insert part accepted=0  (+ undo hunk on V_disk)
  Unapprove     ->  delete part row         (+ UI; V_disk unchanged)
  Reject chunk  ->  V_disk = V_backup      (Flow E; whole-file; parent reviewed=1)
  Chunk closed  ->  file_history.reviewed=1 (every hunk has a part row)
```

### Queries (names only)

- Parts for open chunk: `SELECT … FROM file_diff_part WHERE file_history_id = ? ORDER BY part_index`
- Pending file: newest pending **`file_history`** for path + its **`file_diff_part`** rows
- Carry-forward: read derived hunk files for approved parts vs diff built from **`H2.backup_path`**

### Walkthrough → open questions (short map)

- **Partial granularity** — hunk → **`file_diff_part`** child of **`file_history`**
- **Disk model** — always agent end result; approve = DB + UI; reject = disk restore
- **Baseline for diff overlay** — **`file_history.backup_path`** vs current disk content
- **Stacked LLM edit** — new **`file_history`** row; new disk end result; match old approved parts in new overlay
- **Undo approve** — delete **`file_diff_part`** row (+ UI) — **not** disk, **not** GtkSource undo
- **Bulk approve** — loop pending **`file_history`** (+ parts); DB only

---

## Design — approval baseline and partial approval

ℹ️ Parent context: [`done/4.2-DONE-code-editor-tool.md`](done/4.2-DONE-code-editor-tool.md) Phase 6 mentioned “temporary approved copy” — **superseded:** disk is always end result; review is overlay + DB.

ℹ️ **Baseline for Phases 2–3:** diff overlay = **`file_history.backup_path`** (**V_backup**) vs current **V_disk**. Partial / stacked / bulk remain Phase **4**.

ℹ️ Shipped today ([`done/2.10.4.25-DONE-file-history-approval.md`](done/2.10.4.25-DONE-file-history-approval.md)):

- One **file** row in `ReviewFiles` with **`approve_id`** (newest pending `file_history` row) and **`reject_id`** (newest row with backup).
- **Approve (whole file):** marks that row and all older pending rows on the file approved.
- **Reject (whole file):** restores from **`reject_id`** backup; disk + DB update; client `File.read`.
- Multiple **`file_history`** rows per file already exist (timeline); UI collapses to one popover row per file.

### Cursor contrast (what to avoid)

ℹ️ In Cursor, rolling back an approval decision is **hard** — it is effectively bundled into **undo/redo**, not a first-class “I changed my mind about this approve” action. That is **counterintuitive** for a review workflow.

ℹ️ Cursor also exposes **approve all changes** across **multiple files** alongside per-file approve — both classes of action are **highly destructive** but easy to hit from the general review UI.

- 🔷 Approval state changes must be **explicit review actions**, not aliases of **`Ctrl+Z` / `Ctrl+Shift+Z`** on the text buffer.
- 🔷 ⏳ **Unapprove / rollback approval** — dedicated affordance(s) with clear semantics:
  - whole-file “undo approve” while file still in review?
  - per-hunk “unaccept” after partial approve?
  - distinct from **Reject** (which **restores disk** from backup)?
  - **bulk** “undo approve all” if bulk approve exists?
- 🔷 ⏳ **`file_history` timeline** should be the audit trail for approve/unapprove — not the GtkSource undo stack.
- 🔷 ⏳ After user **edits the file manually** during review, undo stack and approval state must stay **separate** (manual edit undo ≠ unapprove LLM hunk).

### Destructive actions (placement + revert)

🔷 **Reject** (and **reject all** ⏳) **writes disk** — treat as **destructive**. **Approve** / **approve all** = DB + UI only — lower risk but still confirm for bulk.

- 🔷 ⏳ **Primary bar** — navigation + non-destructive review chrome; **Reject** not casual; **Approve** may stay accessible ⏳.
- 🔷 ⏳ **Bulk actions** — if we ship **approve all pending files** (Cursor parity), place in **changes-list overflow** (popover / dropdown menu on the changed-files control), **not** next to everyday editor chrome.
- 🔷 ⏳ **Confirmation** — bulk approve all and bulk reject all likely need an explicit confirm step (count of files + chunks).
- 🔷 ⏳ **Revert bulk actions** — must exist as first-class operations:
  - revert last bulk approve (restore pending state per file)?
  - or per-file unapprove only (no single “undo all”)?
  - backed by **`file_history`** / **`file_diff_part`** flips — **not** editor undo.
- ℹ️ Shipped today: per-file Approve/Reject on [`liboccoder/Approvals.vala`](../../liboccoder/Approvals.vala) header — redesign may move or restyle when diff UI lands.

### Questions to close (Phase 4 design pass)

ℹ️ Phases **1–3** do not need these closed. Revisit before Phase **4** coding.

- 🔷 ⏳ **Sign off walkthrough** — Flow A–F and **`file_diff_part`** columns: correct mental model?
- 🔷 ⏳ **When to insert `file_diff_part` rows** — on first user approve/reject (no row = pending); not upfront on agent write ⏳
- 🔷 ⏳ **Hunk file format** — unified-diff text vs serialised **`Patch`** object (cache only; not applied to disk on approve)?
- 🔷 ⏳ **Carry-forward** — auto-trust **`carried`** hunks vs always show for re-click?
- 🔷 ⏳ **Stacked edit (Flow B)** — obsolete hunks on **H1** when **H2** arrives: hide, merge, or show both sessions?
- 🔷 ⏳ **Relationship to whole-file Approve/Reject on `Approvals` bar** — demote, move to menu, or keep for selected file only?
- 🔷 ⏳ **Approve all files** — ship at all? Menu-only? Reversible how?
- 🔷 ⏳ **Reject all pending** — same placement rules as approve all?
- 🔷 ⏳ **Undo approve vs Reject** — **Unapprove** = DB + diff overlay only (disk stays). **Reject** = disk restore. Neither is editor undo.
- 🔷 ⏳ **Partial unapprove** — walk back one hunk, one chunk, or only all-or-nothing?

### UI (Phase 4 — not designed yet)

- 🔷 ⏳ Where partial-approve controls live — gutter icons, per-hunk bar, context menu, keyboard?
- 🔷 ⏳ Read-only diff buffer vs editable file with overlays?
- 🔷 ⏳ How user sees progress when some hunks approved and others not (counts, approved hunks in normal text only, second list)?
- 🔷 ⏳ Secondary baseline gutter — always visible in diff mode, or only on changed hunks? (Phase **2** can default to always-on in diff mode.)
- 🔷 ⏳ **Unapprove** control placement — bar, diff hunk, history list, changes menu; must **not** be “use undo”.
- 🔷 ⏳ **Changes-list menu** — home for approve all, reject all, revert last bulk action?

### Working notes (not decisions)

- 💩 Partial state = some hunks have **`file_diff_part`** rows, not all; **`file_history.reviewed=0`** until every hunk has a row. **Mixed accept/reject on one chunk is normal** — only parts carry **`accepted`**.
- 💩 Wire may need active **`file_history.id`** on **`FileWithHistory`** once partial approve ships — not required for whole-file Phases **1–3**.

### Out of scope until Phase 4 design

- 🔷 ⏳ **Per-hunk approval UI** — layout, partial-approve affordances, interaction model.
- 🔷 ⏳ Per-chunk popover UI promised as “later” in 2.10.4.25 — may merge into Phase **4** once that design pass runs.

---

## Implementation spec

ℹ️ **Phases 1–3:** add **Remove / Replace with / Add** fences **under each phase heading** when that phase is ready to code (per `docs/guide-to-writing-plans.md`).

ℹ️ **Phase 4:** **no** Vala fences until the Phase **4** design pass closes.

- ℹ️ Likely touch points:
  - Phase **1:** `ollmfilesd/FileHistory.vala`, migrate / `init_db`
  - Phase **2:** `liboccoder/SourceView.vala`, `resources/style.css`
  - Phase **3:** `liboccoder/Approvals.vala`, client/daemon `FileHistory` (backup text)
  - Phase **4:** same + part RPCs / hunk overlay state
- ℹ️ Diff **library** ([`OLLMfiles.Diff.Differ`](../../libocfiles/Diff/)): diff two strings → hunks/patches only.
- ℹ️ Diff **consumer** (`ollmfilesd`, `liboccoder/SourceView`, `Approvals`): pending state, overlay, approve/reject RPC, **`file_diff_part`** — including any future carry-forward (Flow C).

---

## LLM notes

- 🚫 **Phase 4 Vala fences** until user signs off Phase **4** design.
- 🚫 Skip ahead to per-hunk approve UI before Phases **1–3** land.
- 🚫 Conflate **approve / unapprove** with GtkSource **undo/redo** or buffer edit history.
- 🚫 **Approve all** / **reject all** as primary header buttons beside everyday editor controls.
- 🚫 Do not invent Phase **4** gutter buttons / menus from the open UI bullets alone.
- 🚫 Rewrite disk on **approve** (whole-file or partial) — disk is already the agent end result.
- 🚫 Add **`file_approval_batch`**, **`seq`**, line-range columns, or duplicate **`filebase_id`** on the child table without user sign-off.
- 🚫 Put approval state, carry-forward, or **`file_history`** awareness in **`OLLMfiles.Diff`** — consumer only.
