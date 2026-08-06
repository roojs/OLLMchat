# Agent Pi write: double Edit Mode Activated + file-written visibility

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval

## Problem

🔷 Session flow after `ls`: **Edit Mode Activated** → duration → **Edit Mode Activated again** → markdown → duration. Second activation feels unwanted.

🔷 After the markdown / duration, user wants a clear **"file has been written"** (or equivalent) in the chat.

## Evidence

ℹ️ Session `/home/alan/.local/share/ollmchat/history/2026/08/06/08-30-21.json` (`agent-pi`):

- ✔️ `012` — first `write` tool call: only `file_path` (no `edit_mode`) → default **`ast_path`**
- ✔️ `013`/`014` — UI + tool reply **"Edit mode activated"** with AST instructions
- ✔️ `016` — Total Duration
- ✔️ `017` — second `write`: `edit_mode=complete_file`, `overwrite=true`
- ✔️ `018`/`019` — second **"Edit Mode Activated"** (complete_file instructions)
- ✔️ `020` — markdown content stream (plan body)
- ✔️ `022` — Total Duration
- ✔️ `023` — **`Changes Applied`** / "Successfully applied changes to file: …" (**collapsed** fence) — already present after duration

## Root cause

✔️ Second activation is **not** a UI echo. The model called `write` twice because the first call omitted `edit_mode` and the tool defaulted to `ast_path`, which is wrong for creating a new markdown plan file. The model then retried with `complete_file`.

✔️ "File written" already exists as collapsed **"Changes Applied"** (`Stream.send_success_ui_message`) after duration. Easy to miss; title does not say "written".

## Proposed fix

🔷 When activating write/edit for a **new file** (`creating_file`), do not stay on `ast_path` / `line_numbers` — switch to **`complete_file`** and tell the model that in the tool reply (one activation, correct mode).

🔷 Make the success UI clearer and not collapsed: title **"File written"**.

### 1. `liboctools/EditMode/Request.vala` — `execute_request`: new-file mode

**Why:** Creating a new file cannot use AST/line edits; default `ast_path` caused a useless first activation.

**Where:** after `this.creating_file = …` / read-or-clear buffer, before `to_summary` / UI / LLM instructions.

**Depends on:** none.

#### Add — After the block that sets `creating_file` and reads/clears the buffer, before `var ui_message = this.to_summary ();`

```vala
			if (this.creating_file
				&& (this.edit_mode == "ast_path" || this.edit_mode == "line_numbers")) {
				this.edit_mode = "complete_file";
			}
```

### 2. `liboctools/EditMode/Stream.vala` — success UI title / collapsed

**Why:** Match user expectation: after duration, a clear "file written" frame.

**Where:** `send_success_ui_message`.

**Depends on:** none.

#### Remove

```vala
			this.request.agent.add_message(new OLLMchat.Message("ui",
				 OLLMchat.Message.fenced("text.oc-frame-success.collapsed Changes Applied", success_message)));
```

#### Replace with

```vala
			this.request.agent.add_message(new OLLMchat.Message("ui",
				OLLMchat.Message.fenced(
					"text.oc-frame-success File written",
					success_message)));
```

## Attempts / changelog

- ✔️ 2026-08-06 — Confirmed from session JSON (two `write` calls; Changes Applied already after duration).
- 🚫 Do not suppress second UI activation as a symptom if the model legitimately calls write twice for two different files.

## Next

⏳ 🔷 Await approval to apply §1–§2 (and confirm wording **"File written"** vs keep body "Successfully applied changes…").
