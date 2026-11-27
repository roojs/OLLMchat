# Edit-mode `write` activation + fence stream plan not viable for primary models

**Status:** ⏳

## User decisions required

- 💩 Pick product direction: **always-on** `<write>` parsing ([`EDIT-2.16` strategy plan](../plans/EDIT-2.16-edit-output-format-strategy.md) **Path A**) vs **keep `write` gate** but change tool/harness copy to the same tag syntax (**Path B**).
- 💩 Approve follow-up **CLI/harness probe** for Path B: real `write` tool + agent loop, tool result instructs tag output (not fence-after-activate) — **no product code** until strategy is chosen.

## User reported

- 🔷 The current plan — activate edit with `write`, then stream markdown fences in the **same** assistant message — will **not** work reliably enough to bet the product on (especially `ornith-1.5:35b`).
- 🔷 Always-on angle-bracket POC outside the harness **did** produce a full file in one turn; that is evidence for a different shape, not proof the old path is fixable with prompts.
- 🔷 Want a **bug report** capturing that conclusion, a **strategy** doc for the two options, and a **harder test idea** (pretend `write` turns edit on but model must emit tag syntax) that needs looping — **do not change product code yet**.

## Success scenario

- Strategy choice recorded; parent tickets ([phone edit loop](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md), [always-on POC](2026-11-27-FEATURE-always-on-edit-brace-syntax-poc.md)) point here for **why** prompt-only fence streaming is deprioritized.
- If Path B is chosen: a reproducible harness or CLI scenario shows whether models still **loop on `write`** when the tool result demands `<write>…</write>` instead of fences.
- If Path A is chosen: permissions, review, and sandbox rules for **un-gated** file tags are enumerated before parser work ships.

## Current behavior

- Harness repro (phone + desktop gtktest1)
  - User asks for a mid-file edit.
  - Model calls `write` with path + `edit_mode`.
  - Harness replies with fence / line-range instructions and “do not call `write` again in this message”.
  - Model often emits **think-only** or **empty** assistant content, then calls **`write` again** (sometimes many times) instead of streaming fences — see verbatim session blocks in [2026-11-23 issue](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md).
- Always-on CLI repro (no `write` tool registered)
  - `ollmchat-cli` `run_system_test` with [`tests/data/always-on-edit-brace-poc/`](../../tests/data/always-on-edit-brace-poc/) and `ornith-1.5:35b`.
  - Single assistant turn — opening tag (verbatim excerpt from [`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt)):

```text
<write file="sample-brace.txt" edit_mode="complete_file" overwrite="true">
1
2
3 A lone sem wandered across the frozen meadow at dusk, its breath ragged
…
```

  - Closed with `</write>`; ~fifty numbered lines; **no** `tool_calls` in that completion path.
- Gap
  - We have **not** run the hybrid probe: **`write` tool offered**, edit activated, tool result **requires tag syntax** in the continuing assistant stream inside a full agent loop (streaming handler, possible multi-turn).

## Codebase observed behavior

- [`liboctools/EditMode/Request.vala`](../../liboctools/EditMode/Request.vala) — after `write`, tool result text emphasizes **markdown fence** rules (`INSTRUCTIONS_LINE_RANGE`, STOP rules).
- [`liboctools/EditMode/Stream.vala`](../../liboctools/EditMode/Stream.vala) — applies **fenced** edits from assistant stream while edit mode is active; no parser for `<write>` tags today.
- [`ollmapp/ollmchat-cli.vala`](../../ollmapp/ollmchat-cli.vala) — `run_system_test()` can send raw system/user templates **without** tools (POC only).
- [`docs/plans/EDIT-2.15-active-edit-tool.md`](../plans/EDIT-2.15-active-edit-tool.md) — older “active edit” format (`---BEGIN---` / `Edit: path`) — related but not the same as the `<write>` POC syntax.

## Debugging

#### Current debug output

- None yet for Path B hybrid probe.

#### Debug code added (remove when complete)

- None.

## Proposed fix

**None in product code until strategy is chosen** — see [`EDIT-2.16-edit-output-format-strategy.md`](../plans/EDIT-2.16-edit-output-format-strategy.md).

**Investigation — B0 (observe output; apply may fail)**

- Tag copy on [`Write`](../../liboctools/EditMode/Write.vala) + [`Request.execute_request`](../../liboctools/EditMode/Request.vala); fence apply unchanged.
- Desktop Pi or `ollmchat-cli --project=…`; record tags, fences, think-only, repeat `write` in **Current behavior**.

**Later**

- **B1** — CLI script markers + stdin loop ([EDIT-2.16](../plans/EDIT-2.16-edit-output-format-strategy.md)).
- **B2** — full gtktest1 harness with tag parser if B0 looks promising.

**Deprioritize (unless user revives)**

- Further prompt-only reordering of fence instructions in [`Request.vala`](../../liboctools/EditMode/Request.vala) as the **primary** fix for `ornith-1.5:35b` — evidence from phone/desktop loops + successful no-tool tag POC.

## LLM

- ℹ️ Opened **2026-11-27** after always-on POC success; parent [FEATURE always-on brace POC](2026-11-27-FEATURE-always-on-edit-brace-syntax-poc.md).
- ℹ️ Strategy: [EDIT-2.16](../plans/EDIT-2.16-edit-output-format-strategy.md). Related: [EDIT-2.15](../plans/EDIT-2.15-active-edit-tool.md), [2026-11-23 phone issue](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md).
- ℹ️ **B0** tag copy in tree 2026-11-27; paste manual results into **Current behavior**.
- ⏳ CLI script markers (B1) documented in EDIT-2.16 only.