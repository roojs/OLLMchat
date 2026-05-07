# Replay: `exec_runs` empty when applying EXECUTION `content-stream` (`on_replay`)

**Status: FIXED** — Replay now calls **`Details.build_exec_runs()`** when **`exec_runs`** is still empty before **`exec_extract`**, matching **`List.run_child`** (**`build_exec_runs()`** then **`run_exec()`**). Build verified (`meson compile`). **Manual check:** restore a session that reaches **exec**; no **`SIGABRT`** on first exec **`content-stream`**; debug line shows **`exec_runs`** ≥ **1**.

**Related (also FIXED, same restore path):** **`user_request`** on restore — `docs/bugs/done/2026-04-07-FIXED-replay-refinement-oob.md`; exec detail cursor — `docs/bugs/done/2026-04-07-FIXED-replay-execution-oob.md`.

## Problem

On session restore, **`Skill.Runner.on_replay`** handled **EXECUTION** **`content-stream`** by calling **`exec_extract`** on **`exec_runs.get(replay_tool_pos)`** while **`exec_runs`** had never been filled during replay (live path always **`build_exec_runs()`** first).

## Evidence

- **`~/.cache/ollmchat/ollmchat.debug.log`:** **`replay_exec … exec_runs=0`** before fix.
- GDB: **`exec_runs.get`** in **`Runner.on_replay`**.
- Session **`2026-04-07-12-15-34`**.

## Root cause

**`extract_refinement`** hydrates **`Details`**, but **`build_exec_runs()`** was only invoked from **`run_child`**, which replay does not run.

## Implementation

**File:** `liboccoder/Skill/Runner.vala` — **`on_replay`**, **`EXECUTION`**, **`content-stream`**

After **`d_exec`** is resolved, **`if (d_exec.exec_runs.size == 0) { d_exec.build_exec_runs(); }`** then **`exec_extract`**. Only when empty: **`build_exec_runs()`** clears and repopulates; later **`content-stream`** rows for the same detail must not reset.

## How to run

Build; restore a session that reaches **exec**; **`--debug`** / **`~/.cache/ollmchat/ollmchat.debug.log`**.

## Tests / automation

- **`meson compile`:** succeeds.
- Manual: restore session **`2026-04-07-12-15-34`** (or similar) past first exec **`content-stream`**.

## Changelog

- 2026-04-07 — Issue filed; proposed **`build_exec_runs()`** when empty.
- 2026-04-07 — **Fix applied**; doc renamed **`FIXED`**; cross-links added to sibling replay **`FIXED`** docs.
