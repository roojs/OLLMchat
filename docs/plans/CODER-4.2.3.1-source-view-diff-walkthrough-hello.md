# 4.2.3.1 — SourceView diff walkthrough — `hello.vala`

**Status:** **DESIGN OPEN** · design doc only (no implementation)

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md)

**Pointer:** `docs/guide-to-writing-plans.md` — checklist; vocabulary and named flows (**Flow A** … **F**) live in the parent plan.

---

## Purpose

- 🔷 **`reviewed` only on `file_history`** — `0` / `1`. **`file_diff_part`** has **`accepted`** only; **no row** = hunk pending.
- 🔷 Each step shows **SourceView overlay**, **V_disk**, and **SQLite** row snapshots (code blocks — not bullet paraphrases).
- ℹ️ Split from parent plan — many nested code blocks break Cursor markdown preview on the main doc.

---

## Worked example — `hello.vala` (seven lines)

ℹ️ **Goal:** same flows as **Flow A / A1 / B / D** in the parent plan, with explicit **SourceView** markers and **SQLite row snapshots** at each step.

**Legend (editor diff overlay only — not written to disk)**

- **plain line** — normal text; no overlay
- **`[-]` red row** — removed line (unified diff interleaved)
- **`[+]` green row** — added line (unified diff interleaved)
- **`{A}` / `{B}` / `{C}`** — hunk id in gutter / approve control

**Hunks in this example**

- **Hunk A** — line 2: `Legacy Line Two` → `Hello World Two`
- **Hunk B** — line 4: `Legacy Line Four` → `Hello World Four`
- **Hunk C** — line 6 (second agent write only): `Hello World Six` → `Hello World Six Updated`

**V_backup** (before first agent write — stored at **H1** `backup_path`)

```
Hello World One
Legacy Line Two
Hello World Three
Legacy Line Four
Hello World Five
Hello World Six
Hello World Seven
```

---

### Step 1 — Agent write (chunk **H1**)

User: `hello.vala` appears in changed-files list; editor enters diff mode for **H1**.

**SourceView (diff overlay — what user sees)**

```
Hello World One
[-] Legacy Line Two          {A}
[+] Hello World Two            {A}
Hello World Three
[-] Legacy Line Four           {B}
[+] Hello World Four             {B}
Hello World Five
Hello World Six
Hello World Seven
```

**V_disk (file on disk — agent end result; approve does not change this)**

```
Hello World One
Hello World Two
Hello World Three
Hello World Four
Hello World Five
Hello World Six
Hello World Seven
```

```
file_history
  id  path         reviewed  backup_path
  1   hello.vala   0         .../backup-1-hello.vala   → V_backup above

file_diff_part
  (no rows yet — hunks A and B pending)

filebase
  path=hello.vala  is_need_approval=1
```

---

### Step 2 — Approve hunk **A** (half-approved / partial state)

User: clicks **Approve** on `{A}`. **V_disk** unchanged.

**SourceView**

```
Hello World One
Hello World Two                plain — hunk A approved, overlay off
Hello World Three
[-] Legacy Line Four           {B}
[+] Hello World Four             {B}
Hello World Five
Hello World Six
Hello World Seven
```

**V_disk** — same as step 1 (both agent hunks still on disk).

```
file_history
  id  path         reviewed  backup_path
  1   hello.vala   0         .../backup-1-hello.vala

file_diff_part
  id  file_history_id  part_index  accepted  decided_at
  1   1                0           1         169…

filebase
  path=hello.vala  is_need_approval=1
```

ℹ️ **H1** stays `reviewed=0` — hunk **B** not acted on yet. Mixed overlay: **A** plain, **B** still green/red.

---

### Step 3 — Agent writes again (stacked edit — chunk **H2** while **H1** still open)

User: notification “file changed again”. Active diff switches to **H2** only (v1 — no carry-forward). **H1** hunk **B** is still pending in DB but not shown in the **H2** overlay.

Agent change: line 6 only (**hunk C**). **H2** `backup_path` = **V_disk** at end of step 2 (includes **A** and **B** agent text).

**SourceView (active diff = H2)**

```
Hello World One
Hello World Two
Hello World Three
Hello World Four
Hello World Five
[-] Hello World Six            {C}
[+] Hello World Six Updated      {C}
Hello World Seven
```

**V_disk (after second agent write)**

```
Hello World One
Hello World Two
Hello World Three
Hello World Four
Hello World Five
Hello World Six Updated
Hello World Seven
```

```
file_history
  id  path         reviewed  backup_path
  1   hello.vala   0         .../backup-1-hello.vala   → original V_backup
  2   hello.vala   0         .../backup-2-hello.vala   → step-2 V_disk

file_diff_part
  id  file_history_id  part_index  accepted  decided_at
  1   1                0           1         169…
  (no P2 — hunk B on H1 still pending)

filebase
  path=hello.vala  is_need_approval=1
```

🔷 ⏳ **Open (Flow B):** **H1** / hunk **B** — obsolete, hidden, or re-targeted when user returns to **H1**? v1 assumes review **H2** only until **H1** is explicitly reopened.

---

### Step 4 — Unapprove hunk **A** on **H1** (walk back approval — Flow D)

User: opens **H1** review (history / chunk picker — not `Ctrl+Z`). Clicks **Unapprove** on `{A}`.

**V_disk** — unchanged (unapprove is DB + overlay only).

**SourceView (focused on H1 again — diff vs H1 V_backup)**

```
Hello World One
[-] Legacy Line Two            {A}   overlay restored
[+] Hello World Two              {A}
Hello World Three
[-] Legacy Line Four             {B}
[+] Hello World Four               {B}
Hello World Five
Hello World Six Updated          plain on disk; no H1 hunk here
Hello World Seven
```

ℹ️ Lines 6–7 reflect **current V_disk** (post-**H2**). **H1** overlay still diffs **H1** `backup_path` vs disk for **A** and **B** only — exact interleaving TBD in UI spec.

```
file_history
  id  path         reviewed  backup_path
  1   hello.vala   0         .../backup-1-hello.vala
  2   hello.vala   0         .../backup-2-hello.vala

file_diff_part
  (P1 deleted — hunk A pending again)

filebase
  path=hello.vala  is_need_approval=1
```

ℹ️ **Unapprove** = **delete P1** row. **Not** editor undo. **Not** a disk write. **H1** `reviewed=0`.

---

### Step 5 — Re-approve **A**, then reject **B** on **H1** (Flow A1 — mixed chunk close)

User: on **H1**, **Approve** `{A}` again, then **Reject** `{B}` (destructive — writes disk for **B** only).

**SourceView (after both actions — chunk **H1** closed)**

```
Hello World One
Hello World Two                plain — A accepted
Hello World Three
Legacy Line Four               plain — B rejected; agent B undone on disk
Hello World Five
Hello World Six Updated
Hello World Seven
```

**V_disk (after per-hunk reject of B)**

```
Hello World One
Hello World Two
Hello World Three
Legacy Line Four
Hello World Five
Hello World Six Updated
Hello World Seven
```

```
file_history
  id  path         reviewed  backup_path
  1   hello.vala   1         .../backup-1-hello.vala
  2   hello.vala   0         .../backup-2-hello.vala

file_diff_part
  id  file_history_id  part_index  accepted  decided_at
  1   1                0           1         169…
  2   1                1           0         169…

filebase
  path=hello.vala  is_need_approval=1
```

ℹ️ **H1** `reviewed=1` — both hunks have part rows (`accepted` mixed). **H2** still pending.

---

### Step 6 — Approve hunk **C** on **H2** (close second chunk)

User: switches active diff back to **H2**; **Approve** `{C}`.

**SourceView**

```
Hello World One
Hello World Two
Hello World Three
Legacy Line Four
Hello World Five
Hello World Six Updated        plain — C approved
Hello World Seven
```

**V_disk** — unchanged from step 5 (approve does not write disk).

```
file_history
  id  path         reviewed  backup_path
  1   hello.vala   1         .../backup-1-hello.vala
  2   hello.vala   1         .../backup-2-hello.vala

file_diff_part
  id  file_history_id  part_index  accepted  decided_at
  1   1                0           1         169…
  2   1                1           0         169…
  3   2                0           1         169…

filebase
  path=hello.vala  is_need_approval=0
```

ℹ️ All chunks closed → file leaves pending list. Final **V_disk** = **H1** outcome (**A** kept, **B** reverted) plus **H2** line-6 update.

---

### Step map → named flows

- **Steps 1–2** — **Flow A** — agent write → partial approve
- **Step 3** — **Flow B** — stacked agent write while **H1** incomplete
- **Step 4** — **Flow D** — unapprove / walk back **P1**
- **Step 5** — **Flow A1** — re-approve + per-hunk reject (mixed close)
- **Step 6** — **Flow A** — finish **H2**

---

## LLM notes

- 🚫 Do not duplicate this walkthrough back into the parent plan (preview size).
- 🚫 Do not add **`reviewed`** to **`file_diff_part`**.
- 🚫 Do not use **`status`** on **`file_history`** in this design — **`reviewed` only**.
- 🚫 No Vala code fences — design sign-off only.
