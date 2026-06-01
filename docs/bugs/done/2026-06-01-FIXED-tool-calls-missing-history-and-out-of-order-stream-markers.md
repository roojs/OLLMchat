# Tool calls missing from history, with out-of-order stream markers

**Status:** FIXED (2026-06-01) — §1–§3 applied in tree

**Started:** 2026-06-01

**Pointer:** `.cursor/rules/CODING_STANDARDS.md` (checklist for all plans), `docs/guide-to-writing-plans.md` (code proposal format), `docs/bug-fix-process.md`.

**Related:**

- ℹ️ `docs/bugs/done/2026-05-31-FIXED-chatcompletions-v1-metrics-missing.md`
- ℹ️ `docs/plans/done/1.2-DONE-refactor-client-chat-relationship.md`

**Plan shape:** `docs/guide-to-writing-plans.md` — **`## Concrete code proposals`** is the contract.

---

## Purpose

- 🔷 Tool-driven turns must persist assistant `tool_calls` messages and `tool` replies in session history.
- 🔷 Stream terminal markers (`end-stream`, runtime `done`, metrics `ui`) must not produce duplicate or out-of-order history noise.
- 🔷 v1 ChatCompletions must deserialize `function.arguments` so tools receive parameters the model sent (e.g. `query` for `web_search`).
- ✅ §1 — persist assistant tool-call + tool reply messages in `ChatBase.toolsReply()` (applied in tree).
- ✅ §2 — stop persisting `"done"` rows from `Session.finalize_streaming()` (applied in tree).
- ✅ §3 — v1 string `arguments` (`Json.NodeType.VALUE`) + `Json.Parser` (applied in tree).
- 💩 ⏳ Optional: suppress metrics `ui` on internal tool-handoff cycles.
- 💩 ⏳ Optional: merge partial argument string fragments in `Response.Chat.addChunk()` if a model streams arguments across chunks (not seen on `qwen3.6:latest`).

---

## Problem

- 🔷 Expected: tool records in history; one terminal stream cycle per visible answer; tools run with parsed arguments.
- 🔷 Actual (original session `11-12-27.json`): no `role: "tool"` or assistant `tool_calls` in history; repeated `end-stream` / `done` / metrics `ui` for one user turn.
- 🔷 Actual (after §1–§2, session `12-08-22.json`): tool records persist but `tool-calls[].function.arguments` are empty `{}`.
- 🔷 Actual (§3, v1 stream): wire sends `arguments` as a **string**; after deserialize `first_argument_members=0` and tools see `{}` → `Query parameter is required`.

---

## Verification environment (do not rediscover)

- 🔷 **Ollama host:** LAN server `http://192.168.88.14:11434/api` — default in `~/.config/ollmchat/config.2.json` (`connections` / `usage.default_model`). **Not** `127.0.0.1`.
- 🔷 **Model:** `qwen3.6:latest` — same config `usage.default_model.model`. Required for real v1 `tool_calls` + string `arguments`. Local `ollama list` models (e.g. `gemma3:latest`) often emit **no** `tool_calls` or fake tool text in `content`.
- 🔷 **CLI:** v1 default (no `--legacy`). Built binary: `./build/oc-test-cli`.
- ℹ️ **Debug already in tree:** `ChatCompletions.exec_stream()` logs each SSE chunk and stream end (`ChatCompletions.vala` ~409, ~466). Use `--debug`; do **not** add extra `GLib.debug()` in `CallFunction` for this investigation (see `.cursor/rules/CODING_STANDARDS.md` — Debug and Warning Statements).

**Reproduce §3 (from repo root):**

```bash
./build/oc-test-cli --debug \
  --url http://192.168.88.14:11434/api \
  -m qwen3.6:latest \
  "Use the web_search tool to look up the latest Vala programming language release version."
```

**Expect before §3 fix (stderr):**

- `chunk tool_calls=1` payload contains `"arguments":"{\"query\":...}"` (string, not object).
- `stream finished tool_calls=1 first_argument_members=0`
- `Query parameter is required` from `web_search` / `google_search`

**Expect after §3 fix:**

- `first_argument_members>=1`
- No `Query parameter is required` when the model sent `query`

ℹ️ History JSON sessions:

- `2026/06/01/11-12-27.json` — missing tool records (pre §1–§2).
- `2026/06/01/12-08-22.json` — tool records present, empty `{}` arguments (post §1–§2).

---

## Root cause (code-backed)

**History persistence — ✅ fixed by §1–§2:**

- ℹ️ `ChatBase.toolsReply()` used in-memory `messages_to_send` for API continuation but did not call `agent.add_message()` for the assistant tool-call message or tool replies.
- ℹ️ `Session.finalize_streaming()` appended `"done"` directly to `this.messages` even though `on_message_created()` skips persisting that role elsewhere.

**v1 tool arguments — 🔷 ⏳ open; §3:**

- ℹ️ `CallFunction` `case "arguments":` is correct for **`Json.NodeType.OBJECT`** (`get_object()`).
- ℹ️ v1 SSE delivers **`arguments` as a JSON string** (`Json.NodeType.VALUE`); the string’s *contents* are a second JSON document; we never parse it, so `else` assigns `{}`.

**🚫 Rejected for §3 (do not implement):**

- 🚫 Replacing the working `OBJECT` branch with `default_deserialize_property()` — not required for this bug.
- 🚫 Applying §3 in code before explicit approval (bug-fix process step d).

---

## Attempts / changelog

- ℹ️ 2026-06-01: Traced `ChatBase.toolsReply()`, `Agent.Base.execute_tools()`, `Session.finalize_streaming()`, `Session.on_message_created()`, `SessionBase.handle_tool_message()`.
- ✅ 2026-06-01: Applied §1–§2. Verified on `12-08-22.json`: assistant `tool-calls` and `tool` replies persist.
- ℹ️ 2026-06-01: Verified on **remote** `192.168.88.14` + `qwen3.6:latest` (see **Debug evidence** below). Localhost / other models are invalid for this bug.
- ℹ️ 2026-06-01: Draft §3 — keep `OBJECT` path; add `typeof(string)` wire → `Json.Parser` second decode.
- ✅ 2026-06-01: Applied §3 per approved plan (`CallFunction.deserialize_property`).
- ✅ 2026-06-01: Remote verify `192.168.88.14` + `qwen3.6:latest`: `first_argument_members=1`, no `Query parameter is required` on web_search turn.

---

## §3 — what we get vs what we need

**On the wire** (Ollama v1 `/v1/chat/completions` stream, `delta.tool_calls[].function`):

```json
"function": {
  "name": "web_search",
  "arguments": "{\"query\":\"Vala latest version\"}"
}
```

- `arguments` in JSON is a **string** → `property_node.get_node_type() == Json.NodeType.VALUE`.
- The string value is JSON text for an **object** (must be parsed again).

**What existing code handles** (native / object wire — unchanged):

```json
"arguments": {
  "query": "Vala latest version"
}
```

- `arguments` is an **object** node → `property_node.get_object()` works.

**What happens today on v1**

| Step | Result |
| ---- | ------ |
| json-glib passes `property_node` | `Json.NodeType.VALUE`, string `{"query":"…"}` |
| `get_node_type() == OBJECT` | false |
| `else` | `this.arguments = new Json.Object()` → `{}` |
| `first_argument_members` | `0` |
| `web_search` | `Query parameter is required` |

**After §3**

| Step | Result |
| ---- | ------ |
| `OBJECT` | same as today — `get_object()` |
| `VALUE` (after `!= VALUE` guard) | `Json.Parser.load_from_data(get_string())` → `parsed.get_object()` |
| `first_argument_members` | `>= 1` when model sent `query` |

## Debug evidence (2026-06-01, remote `qwen3.6:latest`)

Wire (SSE chunk, `ChatCompletions.vala:409`):

```
chunk tool_calls=1 payload={..."function":{"name":"web_search","arguments":"{\"query\":\"latest Vala programming language release version\"}"}...}
```

After deserialize (`ChatCompletions.vala:466`):

```
stream finished tool_calls=1 first_argument_members=0
```

Tool failure (same run):

```
RequestBase.execute: Tool 'google_search' threw error: Query parameter is required
```

So: payload has `query` in a **string**; `CallFunction` leaves `arguments` empty; tool correctly complains.

## §3 design

- 🔷 Top of `case "arguments":`: `this.arguments = new Json.Object();` and `value = Value(typeof(Json.Object));` once; failure branches only `set_boxed` + **return**.
- 🔷 **`== OBJECT`** → `get_object()`, `set_boxed`, **return**.
- 🔷 **`!= VALUE`** → `set_boxed`, **return** (already empty `{}`).
- 🔷 Remaining (`VALUE`) → `get_string()`, `Json.Parser`; parse/`parsed` failures → `set_boxed`, **return**; else `get_object()`, **return**.
- 🚫 No new helper; no `default_deserialize_property()` for `arguments`.

---

## Concrete code proposals

Hunks are `Remove` / `Replace with` from the tree. `Keep` means unchanged context and is not used as an edit directive here.

### 1. `libollmchat/Call/ChatBase.vala` — `toolsReply()`: persist assistant tool-call and tool replies

**Status:** ✅ Applied in tree.

**Why:** Tool recursion used transient message arrays and lost tool records in persisted history.

**Where:** `toolsReply()`, inside `if (this.agent != null)` block before `send_append()`.

**Depends on:** none.

#### Remove

```vala
			if (this.agent != null) {
				var tool_reply_messages = yield this.agent.execute_tools(response.message.tool_calls);
				var messages_to_send = new Gee.ArrayList<Message>();
				messages_to_send.add(response.message);
				foreach (var reply_msg in tool_reply_messages) {
					messages_to_send.add(reply_msg);
				}
				var next_response = yield this.send_append(messages_to_send);
```

#### Replace with

```vala
			if (this.agent != null) {
				this.agent.add_message(response.message);
				var tool_reply_messages = yield this.agent.execute_tools(response.message.tool_calls);
				var messages_to_send = new Gee.ArrayList<Message>();
				messages_to_send.add(response.message);
				foreach (var reply_msg in tool_reply_messages) {
					this.agent.add_message(reply_msg);
					messages_to_send.add(reply_msg);
				}
				var next_response = yield this.send_append(messages_to_send);
```

---

### 2. `libollmchat/History/Session.vala` — `finalize_streaming()`: do not persist `"done"` marker rows

**Status:** ✅ Applied in tree.

**Why:** `"done"` is a runtime completion signal and should not be stored in history.

**Where:** `finalize_streaming()`, block that creates and stores `done_msg`.

**Depends on:** none.

#### Remove

```vala
			// Create a "done" message to signal completion (for tools like RequestEditMode)
			// Note: The response body is in response.message (already persisted above)
			// The "done" message is just a completion marker with no content needed
			var done_msg = new Message("done", "");
			// Add to messages to trigger message_created signal (Session will skip persisting it)
			this.messages.add(done_msg);
			// Relay to Manager to trigger message_created signal for tools
			this.manager.message_added(done_msg, this);
```

#### Replace with

```vala
			// Create a "done" message to signal completion (for tools like RequestEditMode)
			// Keep this as a runtime signal only; do not persist it in session history.
			var done_msg = new Message("done", "");
			this.manager.message_added(done_msg, this);
```

---

### 3. `libollmchat/Response/CallFunction.vala` — `deserialize_property()`: unwrap string `arguments`

**Status:** ✅ Applied in tree.

**Why:** v1 sends `arguments` as a JSON string; code only handles object nodes — string nodes hit `else` and become `{}`.

**Where:** `deserialize_property()`, `case "arguments":` — `value` once at top; `!= VALUE` guard; parser for string wire.

**Depends on:** none.

🔷 Verify: command in **Verification environment**; stderr must show `first_argument_members>=1` and no `Query parameter is required`.

#### Remove

```vala
				case "arguments":
					if (property_node.get_node_type() == Json.NodeType.OBJECT) {
						this.arguments = property_node.get_object();
					} else {
						this.arguments = new Json.Object();
					}
					value = Value(typeof(Json.Object));
					value.set_boxed(this.arguments);
					return true;
```

#### Replace with

```vala
				case "arguments":
					this.arguments = new Json.Object();
					value = Value(typeof(Json.Object));
					if (property_node.get_node_type() == Json.NodeType.OBJECT) {
						this.arguments = property_node.get_object();
						value.set_boxed(this.arguments);
						return true;
					}
					if (property_node.get_node_type() != Json.NodeType.VALUE) {
						value.set_boxed(this.arguments);
						return true;
					}
					Json.Node? parsed = null;
					var parser = new Json.Parser();
					try {
						parser.load_from_data(property_node.get_string(), -1);
						parsed = parser.get_root();
					} catch (Error e) {
						value.set_boxed(this.arguments);
						return true;
					}
					if (parsed == null
						|| parsed.get_node_type() != Json.NodeType.OBJECT) {
						value.set_boxed(this.arguments);
						return true;
					}
					this.arguments = parsed.get_object();
					value.set_boxed(this.arguments);
					return true;
```

---

## Conclusions

- 🔷 Missing history: persistence asymmetry in `toolsReply()` — **§1** fixes it (✅ applied).
- 🔷 Out-of-order `"done"` rows: `finalize_streaming()` stored runtime markers — **§2** fixes it (✅ applied).
- 🔷 Broken tool execution on v1: `arguments` as JSON **string** — **§3** applied (`CallFunction` + `VALUE` unwrap).
- 💩 Metrics `ui` noise on tool-handoff cycles may need a separate follow-up if still annoying after §1–§2.
- 💩 Partial argument streaming across SSE chunks may need `Response.Chat.addChunk()` merge logic if seen in the wild.

---

## After fix (later)

When all fixes are implemented and verified:

1. Rename file with `FIXED` in filename.
2. Move to `docs/bugs/done/`.
3. Add verification evidence (history before/after, `oc-test-cli --debug` with `first_argument_members>0`, successful tool execution).
4. Remove temporary debug in `ChatCompletions.exec_stream()` when merged (note in log if helpful).
