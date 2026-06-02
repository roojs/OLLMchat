# Task progress strip: expand causes strip to disappear

**Status:** OPEN

**Started:** 2026-06-02

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval.

**Related plans (context only — not a diagnosis):**

- **`docs/plans/7.14.14-progress-tree-collapse-header.md`** — collapse header (“Skill activity”) + `Gtk.Revealer` around the progress grid; default collapsed; `set_runner` re-applies collapsed state.
- **`docs/plans/done/7.14-DONE-task-progress-tree-ui.md`** — overall task progress strip design.

---

## Problem

While the **Skills agent** is running a **task list**, the **task progress strip** (`ProgressView`) above the chat input shows a collapsed **“Skill activity”** header. When the user clicks the expand control to open the progress tree, the strip **disappears** instead of revealing the `ColumnView` grid.

**Expected:** Clicking expand shows the progress tree (title / stage / idx columns) at ~288 px height while tasks run.

**Actual:** The progress strip vanishes — user is unsure whether the header, the grid, or the entire widget is gone.

---

## Reproduction

(To be tightened during investigation.)

1. Activate the **Skills** agent on a session with an active or in-progress **task list** run.
2. Confirm the collapsed **“Skill activity”** header is visible above the chat input.
3. Click the expand button (`go-next-symbolic` → should become `go-up-symbolic`).
4. Observe: strip disappears rather than showing the progress grid.

**Environment notes:** Record app build, `--debug` usage, live run vs restored session, and whether progress rows were already populated before expand.

---

## Suspected areas (hypotheses only — not verified)

| Area | Why it might matter |
| ---- | ------------------- |
| **`ProgressView.set_runner()`** | Called on every `Skill.Factory.activate()`; always sets `body_revealer.reveal_child = false` — could race with user expand if activate re-fires during a task run. |
| **`Gtk.Revealer` + `SLIDE_DOWN`** | Revealer child is `ScrolledWindow` with `min_content_height = 288`; layout or transition bug could collapse parent height to zero. |
| **`Skill.Factory.deactivate()`** | Sets `progress_view.visible = false` — wrong agent switch timing could hide the strip. |
| **CSS `.oc-task-progress columnview header`** | `max-height: 0; opacity: 0` hides column titles only — verify it does not zero out the whole grid. |
| **Parent packing** | Strip lives in `host.above_input_widget()` (`liboccoder/Skill/Factory.vala`); pane resize (`schedule_pane_update`) during task activity might reclaim space. |

**Key files:**

- `liboccoder/Task/ProgressView.vala` — collapse header, `body_revealer`, `set_runner`
- `liboccoder/Skill/Factory.vala` — create/show/hide progress strip
- `resources/style.css` — `.oc-task-progress` rules

---

## Debug strategy (evidence-first)

1. **Establish reliable repro** — same session, same task-list phase, expand always fails.
2. **Trace widget visibility** at expand click:
   - `ProgressView.visible`, `body_revealer.reveal_child`, `scrolled.visible`, `column_view.get_n_items()` (via selection model).
   - Whether `set_runner` runs again immediately after expand (log in `set_runner` + expand handler).
3. **Run with `--debug`**; add minimal `GLib.debug()` at:
   - Expand button click (before/after `reveal_child` toggle).
   - `set_runner` entry (runner identity, item count, revealer state).
   - `Factory.activate` / `deactivate` (visibility changes).
4. **Inspect GTK inspector** if available — confirm widget tree and allocated height after expand.
5. Record each experiment below before proposing a fix.

---

## Attempts / changelog

| Date | Change | Purpose | Result |
| ---- | ------ | ------- | ------ |
| 2026-06-02 | Bug report filed | Capture user report | — |

---

## Conclusions

- **Root cause:** Unknown — investigation not started.
- **Ruled out:** Nothing yet.

**Next step:** Reproduce with `--debug`, determine whether the header, revealer body, or entire `ProgressView` is hidden, and whether `set_runner` or `visible = false` fires on expand.
