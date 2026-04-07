# Replay: Gee assertion in `on_replay` (REFINEMENT `content-stream`)

**Status: FIXED** — `user_request` is set during GTK restore in `Runner.on_replay` (`NONE` + `user-sent`). Build verified (`meson compile`). **Manual check:** open a skill-runner session that previously crashed on restore; confirm restore completes past refinement.

**Related (also FIXED, same restore path):** wrong exec detail cursor — `docs/bugs/2026-04-07-FIXED-replay-execution-oob.md`; empty **`exec_runs`** before **`exec_extract`** — `docs/bugs/2026-04-07-FIXED-replay-exec-runs-empty-on-restore.md`.

## Problem

On session restore, `Skill.Runner.on_replay` can abort inside `Gee.ArrayList.get` when handling a stored message (stack pointed at REFINEMENT + `content-stream` applying `pending.steps.get` / `children.get`). That implies the replay cursor and hydrated `pending` graph disagree (e.g. empty `steps` after list parse, or indices past list sizes).

## Debug added

**File:** `liboccoder/Skill/Runner.vala`

1. **Start of `on_replay`** (after `can_replay`) — one `GLib.debug` line per replayed message: session `fid`, numeric `phase`, `role`, cursor positions (`step`, `detail`, `tool`), `steps` count, `content_len` (only values that do not call `Gee.ArrayList.get`; no extra branches for logging).
2. **After initial task-list parse** (LIST + `content-stream`) — `steps` count and whether parser `issues` is empty (`initial_plan` in message).
3. **After revised list parse** (TASK_LIST_ITERATION + `content-stream`) — same (`revised_plan` in message).

No method/class name in the message text (see `.cursor/rules/CODING_STANDARDS.md`).

## How to run

Build the app, then run with **`--debug`** so `GLib.debug` reaches stderr (see `docs/bug-fix-process.md`; `G_MESSAGES_DEBUG` alone is not enough for apps that replace the GLib log handler).

## Conclusions (repro)

Logs show `initial_plan steps=0` with `issues_empty=false`: `ResultParser.parse_task_list()` runs, validation produces **non-empty** `issues`, then `parse_task_list()` replaces `pending` with an empty `List` when `this.issues != ""` (see `liboccoder/Task/ResultParser.vala` end of `parse_task_list()`). Replay then hits `agent-stage` → `refinement` and a REFINEMENT `content-stream` → `pending.steps.get(0)` asserts.

**Root cause:** During **live** task creation, `Runner.send_async` sets `this.user_request = tpl.user_to_document()` from `task_creation_prompt` **before** the model returns, so `ValidateLink` can resolve **fragment-only** references against that document. During **GTK `restore_messages` → `on_replay` only**, nothing set `user_request`. `ValidateLink.validate` treats unresolved `#…` anchors as errors when `user_request` does not supply the heading (`liboccoder/Task/ValidateLink.vala`). Same markdown can **pass** live and **fail** on restore → empty `steps` → crash at refinement.

## Implementation

**File:** `liboccoder/Skill/Runner.vala`, `on_replay`, `case OLLMcoder.Task.PhaseEnum.NONE:` → **`case "user-sent":`**.

`task_creation_prompt` is `throws GLib.Error` and `on_replay` is `void`; the implementation uses **`try` / `catch (GLib.Error)`** with **`GLib.error`** in the catch (fatal, per bug discussion — not `GLib.warning` and continue).

```vala
case "user-sent":
    try {
        var tpl = this.task_creation_prompt(
            m.content,
            "",
            "",
            this.sr_factory.skill_manager,
            this.sr_factory.project_manager);
        this.user_request = tpl.user_to_document();
    } catch (GLib.Error e) {
        GLib.error("%s", e.message);
    }
    break;
```

**Follow-ups (optional):** Task-list **iteration** replay may need the same treatment under **`TASK_LIST_ITERATION`** when a verified message role carries the iteration user payload.

## Tests / automation

- **`meson compile`** (build tree): succeeds.
- **`meson test`:** `test-bubble-*` pass; `test-markdown-parser`, `test-markdown-doc`, `test-file-ops` fail (unchanged baseline for this change — not regression from this fix).

## Changelog

- 2026-04-07 — Debug lines added for diagnosis.
- 2026-04-07 — Conclusions and proposed fix (`user_request` in `NONE` + `user-sent`).
- 2026-04-07 — **Fix applied** in `Runner.on_replay`; doc renamed **`FIXED`**; build verified.
