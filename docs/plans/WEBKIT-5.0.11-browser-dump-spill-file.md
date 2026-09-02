# 5.0.11 — Browser dump spill file (long a11y output)

**Status:** **proposed** — not implemented.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`WEBKIT-5.0-webkit-control.md`](WEBKIT-5.0-webkit-control.md)

**Supersedes:** [`done/TOOLS-1.15-SUPERSEDED-truncate-web-fetch-responses.md`](done/TOOLS-1.15-SUPERSEDED-truncate-web-fetch-responses.md) (truncate-only on deprecated `web_fetch`)

**Related:**

- ℹ️ `run_command` spill pattern (landed): [`done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md`](done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md), [`TOOLS-2.6.5-run-command-timeout-live-spill.md`](TOOLS-2.6.5-run-command-timeout-live-spill.md) §4b
- ℹ️ `web_fetch` inline cap (no file, tool retiring): `liboctools/WebFetch/Request.vala` — `TOOL_BODY_MAX_LINES = 200`
- ℹ️ Live path today: `libocwebkit/Request.vala` → `Browser.dump("a11y")` — no size policy
- ℹ️ `html` / `markdown` dump still `NOT_SUPPORTED` on `Browser.dump()` — this plan is for **`a11y`** (default `format`)

---

## Purpose

- **🔷** Cap what the LLM receives from `browser` dump actions (`fetch`, `search`, `press`, `whereami`).
- **🔷** When the a11y dump is long, write the **full** text to a spill file under `session.task_dir()` and tell the model to use **`read_file`** (with line range) for more.
- **🔷** Same **spill family** as `run_command` §4b — **not** live streaming (`ToolOutput` / `client.run_tool.output` chunks not needed; dump is one-shot after load settles).
- **🔷** Short dumps: full text in the tool return; **no** spill file left on disk.

---

## Behaviour

### Threshold

- **🔷** `DUMP_BODY_MAX_LINES = 200` (align with `web_fetch` / `TOOL_BODY_MAX_LINES`).
- **🔷** LLM slice: **first** N lines (page content — unlike `run_command` which tails the **last** 50).

### Spill file

- **🔷** Directory: `agent.session.task_dir()` — sibling of session JSON (same as `run_command`). Skip when dir is `""` (`EmptySession` / no session).
- **🔷** Filename: `browser-dump-` + `request_id` + `.log`
- **🔷** Write the **full** normalized dump once (after `browser.dump()` returns), not streamed line-by-line.
- **🔷** If `lines <= DUMP_BODY_MAX_LINES`: delete spill file if created; return full text.
- **🔷** If `lines > DUMP_BODY_MAX_LINES`: keep spill file; tool return = first N lines + footer with absolute path.

### Footer (LLM)

- **🔷** When chopped, append (after the first N lines):

```text

[Truncated: dump had {total} lines; showing the first {N} lines only.
Full dump: {absolute_path}
Use read_file on that path (start_line / end_line) for targeted slices.]
```

### Out of scope

- **🚫** Live `ToolOutput` / streaming UI for browser dumps.
- **🚫** Inline-only truncation with no file (`web_fetch` pattern) for browser.
- **🚫** `html` / `markdown` dump formats (still deferred on `Browser.dump()`).

---

## Implementation

### 1. `libocwebkit/Request.vala` — spill + cap after dump

**Where:** after the `switch (act)` block builds `result`, before the UI success fence and `return result`.

**Depends on:** `OLLMchat.Agent.Base` → `session.task_dir()` (same cast as `RunCommand.Request`).

#### Add — constant next to class fields (after `fill` property block / before `Request()`)

```vala
	/** Beyond this many lines, tool return is capped; full dump spills to session task_dir. */
	private const int DUMP_BODY_MAX_LINES = 200;
```

#### Remove

```vala
		var reply_prefix = (fmt == "markdown") ? "markdown" : "text";
		this.agent.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced(
				reply_prefix + ".oc-frame-success.collapsed browser reply",
				result)));
		return result;
```

#### Replace with

Normalize, count lines, optionally spill to `task_dir`, cap LLM return, then UI fence.

```vala
		if (act != "download" && result != "") {
			result = result.replace("\r\n", "\n");
			var parts = result.split("\n");
			var spill_path = "";
			var agent_base = this.agent as OLLMchat.Agent.Base;
			if (agent_base != null && parts.length > DUMP_BODY_MAX_LINES) {
				var dir = agent_base.session.task_dir();
				if (dir != "") {
					spill_path = GLib.Path.build_filename(
						dir, "browser-dump-" + this.request_id.to_string() + ".log");
					try {
						GLib.FileUtils.set_contents(spill_path, result);
					} catch (GLib.Error e) {
						spill_path = "";
					}
				}
			}
			if (parts.length > DUMP_BODY_MAX_LINES) {
				result = string.joinv("\n", parts[0:DUMP_BODY_MAX_LINES])
					+ "\n\n[Truncated: dump had " + parts.length.to_string()
					+ " lines; showing the first " + DUMP_BODY_MAX_LINES.to_string()
					+ " lines only.";
				if (spill_path != "") {
					result += "\nFull dump: " + spill_path
						+ "\nUse read_file on that path (start_line / end_line) for targeted slices.]";
				} else {
					result += "]";
				}
			}
		}
		var reply_prefix = (fmt == "markdown") ? "markdown" : "text";
		this.agent.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced(
				reply_prefix + ".oc-frame-success.collapsed browser reply",
				result)));
		return result;
```

**Note:** `download` action returns a short status string — skip spill logic (`act != "download"`).

### 2. `libocwebkit/Tool.vala` — description line

#### Add — under the existing `Default output (format "a11y"):` block (or an **Output:** subsection)

```text
Output:
- Large page dumps are capped (first 200 lines in the tool result). When capped, the full dump is saved beside the session; the tool return includes the path — use read_file with line ranges for more.
```

---

## Success

- **⏳** `browser` `fetch` on a long page: LLM gets ≤200 lines + spill path footer.
- **⏳** Short page: full dump in tool return; no `browser-dump-*.log` left in `task_dir()`.
- **⏳** `read_file` can open the spill path (same visibility as `run_command` spill — follow up if sandbox blocks).

---

## LLM notes

- **🚫** Do not add spill streaming or `ToolOutput` for browser.
- **🚫** Do not re-open `TOOLS-1.15` truncate-only work on `web_fetch`.
