# Always-on edit: angle-bracket `<write>` blocks instead of `write` tool activation

**Status:** ⏳

## User decisions required

- 💩 Confirm tag names and attributes: `<write file="…" edit_mode="complete_file|line_numbers|ast_path" overwrite="true|false">` … `</write>` vs HTML/XML variant the harness will parse.
- 💩 Product spec: [EDIT-2.17](../plans/EDIT-2.17-always-on-edit-capabilities-syntax-permissions.md) (syntax + permissions); [activation not viable](2026-11-27-ISSUE-edit-mode-tool-activation-plan-not-viable.md).

## User reported

- 🔷 Treat edit mode as **always on**; trigger an edit with angle-bracket tags carrying file path and options (not a separate `write` tool round-trip).
- 🔷 Probe the LLM **out of the app** first — extend **`ollmchat-cli`** with file-based system/user templates, not the main chat harness.
- 🔷 Related pain: [phone Agent Pi edit loop](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md); plan sketch [EDIT-2.15-active-edit-tool](../plans/EDIT-2.15-active-edit-tool.md).

## Success scenario

- `ollmchat-cli --system-file=… --user-file=… -m ornith-1.5:35b` sends the template messages **without** registering `write` / edit-mode tools.
- Assistant reply contains at least one well-formed `<write …>…</write>` with ~50 lines of placeholder text for a create-file ask.
- No `tool_calls` for `write` in that same response.

## Current behavior

- Edit apply path requires a `write` tool call → stream fence in a **later** turn → model often loops ([2026-11-23 issue](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md)).
- POC run **2026-11-27** (`ornith-1.5:35b`, streaming CLI, no tools): **met** one-turn `<write>…</write>` create-file ask — full capture in [`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt).

## Codebase observed behavior

- [`ollmapp/ollmchat-cli.vala`](../../ollmapp/ollmchat-cli.vala) — `run_test()` → `manager.send()` with just-ask agent.
- [`liboctools/EditMode/Stream.vala`](../../liboctools/EditMode/Stream.vala) — fence capture on assistant stream after tool activation (unchanged in this POC).

## Proposed fix

**Phase POC (this ticket)**

- ✔️ `ollmchat-cli`: `--system-file`, `--user-file`; `run_system_test()` — one-shot `ChatCompletions` (no tools, no just-ask).
- Fixtures: [`tests/data/always-on-edit-brace-poc/`](../../tests/data/always-on-edit-brace-poc/).
- Runner: [`tests/run-always-on-edit-brace-poc.sh`](../../tests/run-always-on-edit-brace-poc.sh).

**Phase harness (later, user decision)**

- Parser for `<write>` in assistant stream; reuse `EditMode.Stream` apply path without `Tool.activate_request`.

## LLM

- ℹ️ CLI probe landed 2026-11-27; harness parser not started.
- ℹ️ Spec: [EDIT-2.17](../plans/EDIT-2.17-always-on-edit-capabilities-syntax-permissions.md).
- ℹ️ Parent: [2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md).