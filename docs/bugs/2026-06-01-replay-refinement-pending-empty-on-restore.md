# Replay: Gee assertion in `on_replay` (REFINEMENT `content-stream`) — empty `pending` on restore

**Status:** OPEN — proposed fix below; **awaiting approval** before code changes.

**Started:** 2026-06-01

**Process:** **`docs/bug-fix-process.md`** — diagnose → propose → **approval** → apply. **`.cursor/rules/CODING_STANDARDS.md`** — no new methods; no defensive guards that mask broken invariants.

**Related (prior fixes on same restore path):**

- **`docs/bugs/done/2026-04-07-FIXED-replay-refinement-oob.md`** — `user_request` from `NONE` + `user-sent`.
- **`docs/bugs/done/2026-05-07-FIXED-replay-hydration-link-validation.md`** — skip **`ValidateLink.validate_all`** when **`Runner.in_replay`**.
- **`docs/bugs/done/2026-04-07-FIXED-replay-execution-oob.md`** — reset **`replay_details_pos`** on REFINEMENT → EXECUTION **`agent-stage`**.

---

## Problem

GTK **`restore_messages`** → **`Skill.Runner.on_replay`** can abort in **`Gee.ArrayList.get`** on REFINEMENT + **`content-stream`**:

```
Runner.vala — pending.steps.get(replay_step_pos) / children.get(replay_details_pos)
Agent/Base.vala:194 → History/Session.vala:166
```

**Expected:** Restore hydrates **`pending`** from the transcript; refinement replay indexes into a populated task graph.

**Actual:** **`pending.steps`** is empty (or stale) → libgee assertion → abort.

---

## Root cause

1. **`parse_task_list()`** and **`parse_task_list_continue()`** replace **`runner.pending`** with an empty **`List`** when **`issues != ""`**. During restore, a transcript row that live already moved past (e.g. list-parse **retry**) can produce spurious **`issues`** (skill-catalog check, structural validation) even though link validation is already skipped when **`in_replay`**. Clearing **`pending`** wipes the graph the rest of the transcript expects.

2. **`on_replay`** has no **`TASK_LIST_CONTINUE`** branch — continue **`content-stream`** rows are never parsed; **`pending`** stays stale before refinement.

**Not the crash:** failed refinement markdown (e.g. LLM “try again” clarification). REFINEMENT **`content-stream`** is where the assert surfaces; the break is earlier list hydration.

---

## Scope

| In scope | Out of scope |
|----------|----------------|
| **`ResultParser.parse_task_list()`** — stop clearing **`pending`** during **`in_replay`** | New helper methods (**`replay_current_detail`**, etc.) |
| **`ResultParser.parse_task_list_continue()`** — same | Bounds guards / **`GLib.warning` + `break`** around every **`.get()`** in **`on_replay`** |
| **`Runner.on_replay`** — **`TASK_LIST_CONTINUE`** branch (continue sessions) | Changing **`parse_task_list_iteration()`** (already leaves **`pending`** on failure) |
| | **`validate_task()`** skill skip (see **Rejected** — not needed if **`pending`** is not cleared) |
| | Extra debug logging (unless repro still fails after fix) |

---

## Acceptance criteria

- **`meson compile -C build`**
- Reopen the session from the stack trace; restore completes past refinement without abort.
- Live task-list / continue / refinement paths unchanged (**`in_replay`** false).

---

## Implementation order

🔷 **§1** then **§2** then **§3**. §1–§2 fix the primary crash (empty **`pending`** after list parse during restore). §3 fixes continue sessions only.

---

## Concrete code proposals

Mandatory pattern: each block has a **`####`** heading whose first word is **Keep**, **Remove**, **Replace with**, or **Add**.

### 1. `liboccoder/Task/ResultParser.vala` — `parse_task_list()`

ℹ️ **`parse_task_list_iteration()`** already does **not** clear **`pending`** on failure — this aligns initial parse for restore only. Live behaviour unchanged (**`in_replay`** is false during **`send_async`**).

#### Replace with — missing **`goals-summary`** early return (one site)

```vala
		if (!this.document.headings.has_key("goals-summary")) {
			if (!this.runner.in_replay) {
				this.runner.pending = new List(this.runner);
			}
			return;
		}
```

#### Replace with — final validation failure clear (one site)

```vala
		if (this.issues != "" && !this.runner.in_replay) {
			this.runner.pending = new List(this.runner);
		}
```

**Total in §1:** two condition edits in **`parse_task_list()`** only.

---

### 2. `liboccoder/Task/ResultParser.vala` — `parse_task_list_continue()`

Same rule as §1 — three clear sites, each gated with **`!this.runner.in_replay`**.

#### Replace with — missing **`goals-summary`**

```vala
		if (!this.document.headings.has_key("goals-summary")) {
			if (!this.runner.in_replay) {
				this.runner.pending = new List(this.runner);
			}
			return;
		}
```

#### Replace with — empty goals summary

```vala
		if (this.runner.pending.goals_summary_md.strip() == "") {
			this.issues += "\n" + "Goals / summary: revised goals must not be empty.";
			if (!this.runner.in_replay) {
				this.runner.pending = new List(this.runner);
			}
			return;
		}
```

#### Replace with — final validation failure clear

```vala
		if (this.issues != "" && !this.runner.in_replay) {
			this.runner.pending = new List(this.runner);
		}
```

**Total in §2:** three condition edits in **`parse_task_list_continue()`** only.

---

### 3. `liboccoder/Skill/Runner.vala` — `on_replay` **`TASK_LIST_CONTINUE`**

ℹ️ Insert **after** the **`TASK_LIST_ITERATION`** **`case`** closes, **before** **`REFINEMENT`**. Mirror live **`run_task_list_continue`**: on parse failure restore **`existing_proposed`** (same as lines 587–590 in **`run_task_list_continue`**).

#### Add — new **`switch`** arm

```vala
			case OLLMcoder.Task.PhaseEnum.TASK_LIST_CONTINUE:
				switch (m.role) {
				case "content-stream":
					var existing_proposed_cont = this.pending;
					this.pending = new OLLMcoder.Task.List(this);
					var p_cont = new OLLMcoder.Task.ResultParser(this, m.content);
					p_cont.parse_task_list_continue();
					if (p_cont.issues != "") {
						this.pending = existing_proposed_cont;
					} else {
						var pr_cont = new OLLMcoder.Task.ProgressRunner(this) {
							in_creation = false,
							try_max = 5,
							try_no = 0,
							status = OLLMcoder.Task.PhaseEnum.COMPLETED,
						};
						pr_cont.assign_message(m);
						this.progress.add(pr_cont);
						this.progress.add_pending(true);
					}
					this.replay_step_pos = 0;
					this.replay_details_pos = 0;
					this.replay_tool_pos = 0;
					break;
				case "agent-stage":
					this.replay_phase = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					break;
				case "agent-issues":
					break;
				default:
					break;
				}
				break;
```

#### Keep — REFINEMENT and all other **`on_replay`** arms unchanged

No edits to **`pending.steps.get`** / **`children.get`** call sites.

---

## Rejected

🚫 **`replay_current_detail()`** or any new method — user / coding standards; fix hydration, do not scatter guards.

🚫 **Bounds checks before every `.get()` in `on_replay`** — over-guard; masks empty **`pending`** instead of fixing why it is empty.

🚫 **`validate_task()` skill skip when `in_replay`** — not required for this fix. §1–§2 keep the parsed step graph even when skill validation sets **`issues`**; that is enough for the reported crash. Revisit only if verification shows a separate failure mode.

🚫 **`SessionBase.restoring_history`** or other new flags.

🚫 **Broader “skip all validation during replay”** — link skip already exists; do not expand without evidence.

---

## Verify

1. **`meson compile -C build`**
2. Open the failing session → restore past refinement.
3. If still failing: **`--debug`**, check LIST **`content-stream`** replay leaves **`pending.steps.size > 0`** before first REFINEMENT row (optional; no new debug code in minimal fix unless this step is needed).

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-01 | Bug opened from restore crash stack trace. |
| 2026-06-01 | Exploratory fix rolled back (manual, no git). |
| 2026-06-01 | **Concrete code proposals** added per planning guidelines; scope trimmed to minimal diff (5 **`in_replay`** gates + one **`on_replay`** arm). |
