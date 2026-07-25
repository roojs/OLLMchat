# FIXED — Model denies `run_command` / `browser` despite both being sent

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed 2026-07-25 (model now accepts browser + CLI)

**Started:** 2026-07-25

**Related:**

- ℹ️ Debug log: `~/.cache/ollmchat/ollmchat.debug.log`
- ℹ️ Sessions: `~/.local/share/ollmchat/history/2026/07/25/`
  (`09-08-23` just-ask; `09-15-51` / `09-21-15` code-assistant)

---

## Problem

🔷 With **code-assistant**, the model should report (and use) **command-line**
access (`run_command`) and a **real browser** (`browser`). Actual:

- Asked to use the CLI for git → model said it cannot run commands on the machine.
- Asked what tools it has for commands / browsers → listed file tools, then:
  *“While I do not have a traditional web browser (like Chrome or Firefox)…”*
  and never named `run_command` / `browser`. User wants the browser tool to
  advertise itself as Chrome/Firefox-like so the model recognizes it.

---

## Evidence

### Registration / wire (not missing)

- ✔️ `09:15:41` — `register_config` includes `run_command` and `browser`.
- ✔️ ChatCompletions payloads for `09-15-51` and `09-21-15` include both in
  `tools[]` (order starts `browser`, `run_command`, …).
- ✔️ Agent `code-assistant`, model `gemma4:31b`.

### Session behaviour

- ℹ️ `09-08-23` — agent **`just-ask`** (no tools). Denying CLI there is expected.
- ✔️ `09-15-51` — tools present; model still: *“I do not have direct access…”*
  and would not use `run_command`.
- ✔️ `09-21-15` — user: *“what tools … execute commands or … browsers?”*
  Model listed `LS` / `Glob` / `Read` / … / `session_fetch`, **omitted**
  `run_command` and `browser`, and denied a Chrome/Firefox-like browser.

### Current descriptions (why the denial wording matches)

- ℹ️ `libocwebkit/Tool.vala` — opens with *“You have control over a web
  browser…”* — never says Chrome / Firefox / Chromium / WebKit.
- ℹ️ `liboctools/RunCommand/Tool.vala` — opens with *“Run a terminal
  command…”* — never says “you have command-line / shell access”.

💩 Model training often refuses “shell” / “browser” unless the tool text
explicitly claims those capabilities in familiar product terms; gemma then
treats `browser` as “not a real browser” and skips naming `run_command`.

🚫 Not a missing registration / agent-tools filter bug for code-assistant
(payload already contains both tools).

---

## Root cause

✔️ Tools are enabled and sent. Failure is **model acknowledgment / wording**:
descriptions do not label the capabilities in the terms the user (and the
model’s refusal heuristics) use — “command line” and “Chrome or Firefox”.

---

## Proposed fix

🔷 Update tool **description** openers only (no behaviour change):

### `libocwebkit/Tool.vala` — browser description

#### Remove

```vala
		return """
You have control over a web browser for the lifetime of this chat session.
Navigating (fetch, search, press) returns an accessibility output of the page.
```

#### Replace with

```vala
		return """
You have a real web browser for this chat session (WebKit / Chromium-class —
like Chrome or Firefox), not a fetch-only API.
Navigating (fetch, search, press) returns an accessibility output of the page.
```

### `liboctools/RunCommand/Tool.vala` — run_command description intros

#### Remove

```vala
				var intro = "Run a terminal command in the home directory (or specified working directory) and return the output.";
```

#### Replace with

```vala
				var intro = "You have command-line (shell/terminal) access. Run a terminal command in the home directory (or specified working directory) and return the output.";
```

#### Remove

```vala
					intro = "Run a terminal command in the project's root directory (or specified working directory) and return the output.";
```

#### Replace with

```vala
					intro = "You have command-line (shell/terminal) access. Run a terminal command in the project's root directory (or specified working directory) and return the output.";
```

---

## Attempts / changelog

- ✔️ `libocwebkit/Tool.vala` — browser description opens as real WebKit/Chromium
  (Chrome/Firefox-like).
- ✔️ `liboctools/RunCommand/Tool.vala` — both intros lead with command-line
  (shell/terminal) access.

---

## Next

Archived to `docs/bugs/done/` as FIXED (user closed 2026-07-25 — model
accepts browser + command line).
