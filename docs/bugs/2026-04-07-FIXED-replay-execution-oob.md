# Replay: Gee assertion in `on_replay` (EXECUTION `content-stream`) — wrong detail index

**Status: FIXED** — Refinement replay left `replay_details_pos` on the **last** refined child; live execution starts **`run_child`** from **`children[0]`** (`List.vala` foreach). Restore now resets **`replay_details_pos`** and **`replay_tool_pos`** to **0** when **`agent-stage`** transitions **REFINEMENT → EXECUTION** (`exec`). Build verified (`meson compile`). **Manual check:** `~/.cache/ollmchat/ollmchat.debug.log` shows first exec line with **`detail=0`** (was **`detail=2`** before fix).

**Related (also FIXED, same restore path):** **`user_request`** on restore — `docs/bugs/2026-04-07-FIXED-replay-refinement-oob.md`; empty **`exec_runs`** before **`exec_extract`** — `docs/bugs/2026-04-07-FIXED-replay-exec-runs-empty-on-restore.md`.

## Problem (original)

On session restore, `Skill.Runner.on_replay` could abort in `Gee.ArrayList.get` on the first **EXECUTION** `content-stream`: **`children.get(replay_details_pos)`** with **`replay_details_pos`** still at the index left by **REFINEMENT** (e.g. **2** for three refined details) instead of **0** for the first executed task detail.

## Evidence

Session **`2026-04-07-12-15-34`**, `--debug`: **`phase=4`**, **`step=0 detail=2 tool=0 steps=5`** immediately before **`think-stream` / `content-stream`**. Transcript order: three **`refinement`** **`agent-stage`** rows, then **`exec`**.

Source JSON: `~/.local/share/ollmchat/history/2026/04/07/12-15-34.json` — first **`exec`** at message index **48** after three refinement blocks.

## Root cause

**REFINEMENT** replay advances **`replay_details_pos`** on empty **`agent-issues`** until the last refined detail. **EXECUTION** replay must apply the first executor **`content-stream`** to the **first** **`Details`** in step order, matching **`List.run_child`**.

## Implementation

**File:** `liboccoder/Skill/Runner.vala`, **`on_replay`**, **REFINEMENT** branch, **`case "agent-stage":`**

When **`PhaseEnum.from_string(m.content)`** is **`EXECUTION`**, set **`replay_details_pos = 0`** and **`replay_tool_pos = 0`**, then assign **`replay_phase`**.

Optional diagnostic: **`GLib.debug`** for **`replay_exec`** with **`children`**, **`detail`**, **`tool`**, **`exec_runs.size`** after resolving **`d_exec`** (see **`CODING_STANDARDS.md`**).

## Tests / automation

- **`meson compile`:** succeeds.
- After fix: debug shows **`detail=0`** at first exec **`content-stream`**. Companion fix for empty **`exec_runs`**: **`docs/bugs/2026-04-07-FIXED-replay-exec-runs-empty-on-restore.md`**.

## Changelog

- 2026-04-07 — Issue: wrong **`detail`** index on first exec **`content-stream`**.
- 2026-04-07 — **Fix:** reset **`replay_details_pos` / `replay_tool_pos`** on **REFINEMENT → EXECUTION**; doc renamed **`FIXED`**.
- 2026-04-07 — Cross-links updated; **`exec_runs`** restore fix documented in sibling **`FIXED`** file.
