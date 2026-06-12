# Replay: Gee assertion in `on_replay` (REFINEMENT `content-stream`) — empty `pending` on restore

**Status:** FIXED (2026-06-01) — Phase 1 applied and verified on session restore

**Started:** 2026-06-01

**Pointer:** **`docs/coding-standards.md`** (checklist for all plans); **`docs/guide-to-writing-plans.md`** (Keep / Remove / Replace with); **`docs/bug-fix-process.md`**.

**Related:** **`docs/bugs/done/2026-04-07-FIXED-replay-refinement-oob.md`**, **`docs/bugs/done/2026-05-07-FIXED-replay-hydration-link-validation.md`**, **`docs/bugs/done/2026-04-07-FIXED-replay-execution-oob.md`**.

---

## Purpose

- GTK session restore aborts in **`Gee.ArrayList.get`** when **`on_replay`** reaches REFINEMENT because **`pending.steps`** was cleared during list-parse hydration.
- **Phase 1:** one edit so restore keeps the parsed task graph when validation **`issues`** differ from live; no new UI, no new methods.

---

## Problem

**Expected:** Restore hydrates **`pending`**; refinement replay indexes a populated graph.

**Actual:** **`parse_task_list()`** clears **`pending`** on **`issues != ""`** during **`in_replay`** → empty **`steps`** → assert at REFINEMENT **`content-stream`**.

---

## Root cause (this repro)

- Live accepted a LIST **`content-stream`** row; restore re-parses it, builds steps, then spurious **`issues`** (e.g. skill-catalog check; link validation already skipped when **`in_replay`**).
- Final clear at end of **`parse_task_list()`** wipes **`pending`** before refinement messages replay.
- Failed list **retry** rows are not the issue — each LIST replay starts fresh; progress UI already skipped when **`p0.issues != ""`**.

**⏳ Separate (Phase 2):** continue sessions — missing **`TASK_LIST_CONTINUE`** in **`on_replay`**. Not in this stack trace.

---

## Scope

| In scope (Phase 1) | Out of scope |
|--------------------|--------------|
| One **`parse_task_list()`** edit (final clear gated by **`!in_replay`**) | Early-return clears in **`parse_task_list()`** |
| | **`parse_task_list_continue()`**, **`TASK_LIST_CONTINUE`** arm (Phase 2) |
| | New methods, bounds guards on **`.get()`**, skill-validation skip |

---

## Acceptance criteria (Phase 1)

- **`meson compile -C build`**
- Failing session from stack trace restores past refinement without abort.
- Live **`send_async`** list path unchanged (**`in_replay`** false).

---

## Concrete code proposals

Intro: hunks are **Remove** / **Replace with** from the tree; verify surrounding context before applying.

### 1. `liboccoder/Task/ResultParser.vala` — `parse_task_list()`: keep graph on replay validation failure

**Why:** Restore must hydrate **`pending.steps`** from transcript rows live already passed. Clearing **`pending`** when **`issues != ""`** during **`in_replay`** leaves an empty graph for REFINEMENT replay.

**Where:** **`parse_task_list()`**, end of method — block after the **`foreach`** that validates step-0 children.

**Depends on:** none. **`Runner.on_replay`** already sets **`in_replay = true`** before replaying messages (**`docs/bugs/done/2026-05-07-FIXED-replay-hydration-link-validation.md`**).

#### Keep

```vala
		foreach (var t in this.runner.pending.steps.get(0).children) {
			this.validate_task(t, PhaseEnum.LIST);
			var vl_list = new ValidateLink(t.runner, t, PhaseEnum.LIST);
			vl_list.validate_all(t.references);
			t.issues += vl_list.issues;
			if (t.issues == "") {
				continue;
			}
			this.issues += "\n" + t.issue_label() + " (References): " + t.issues;
		}
```

#### Remove

```vala
		if (this.issues != "") {
			this.runner.pending = new List(this.runner);
		}
```

#### Replace with

```vala
		if (this.issues != "" && !this.runner.in_replay) {
			// Live: discard a failed parse so send_async retries on a clean List.
			// Replay (GTK restore / ReplayChat): keep the parsed steps — the transcript
			// already passed live; spurious validation issues must not wipe pending before
			// on_replay reaches refinement / exec (docs/bugs/done/2026-06-01-FIXED-replay-refinement-pending-empty-on-restore.md).
			this.runner.pending = new List(this.runner);
		}
```

---

## Phase 2 (⏳ deferred — not in Phase 1)

**🚫** Do not apply until a **continue** session reproduces after Phase 1 verification.

When opened, add separate **`###`** sections (each with **Keep** / **Remove** / **Replace with**):

- **`parse_task_list_continue()`** — three clear sites (same **`!in_replay`** gate).
- **`Runner.on_replay`** — **`TASK_LIST_CONTINUE`** arm (mirror live **`run_task_list_continue`**).

---

## Rejected

**🚫** **`replay_current_detail()`** or bounds guards on **`.get()`** — masks empty **`pending`**.

**🚫** Multiple **`in_replay`** gates in Phase 1 — over-scoped for this repro.

**🚫** **`validate_task()`** skill skip — unnecessary if graph is not cleared.

---

## Verify

1. **`meson compile -C build`**
2. Reopen failing session → restore past refinement.
3. If OK, stop. If a continue session still crashes → Phase 2 with that repro.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-01 | Bug opened; exploratory fix rolled back. |
| 2026-06-01 | Narrowed to Phase 1 (single clear gate). |
| 2026-06-01 | **Concrete code proposals** rewritten: **Keep** / **Remove** / **Replace with** per **`docs/guide-to-writing-plans.md`**. |
| 2026-06-01 | **Phase 1 applied** in **`ResultParser.parse_task_list()`** (comment + **`!in_replay`** gate). Build verified. |
