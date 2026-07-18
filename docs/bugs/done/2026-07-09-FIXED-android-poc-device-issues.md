# Android chat POC — history + tool HTTPS (TLS)

**Status:** FIXED (2026-07-18) — Problems 1, 2, 4 ✅; Problem 3 deferred with POC close. Plan 9.0 DONE.

**Started:** 2026-07-09

**Package:** `org.roojs.ollmchat.androidpoc`

**Process:** `docs/bug-fix-process.md`

**Related:**

- [`docs/plans/done/9.0-DONE-android-poc-summary.md`](../plans/done/9.0-DONE-android-poc-summary.md) — POC summary (archived)
- [`docs/android-tls.md`](../android-tls.md) — TLS backend + bundled CA (connection API calls work)
- [`docs/bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md`](2026-06-17-FIXED-android-runtime-tls-ime-paste.md) — prior TLS investigation
- [`docs/bugs/done/2026-06-18-FIXED-android-popover-touch-grab.md`](2026-06-18-FIXED-android-popover-touch-grab.md) — popover near-tap (workaround)

---

## Problem 1 — Chat history not recorded / not loading

**Expected:** 🔷 After sending messages on device, sessions appear in the history overlay and survive `force-stop` / cold start. Selecting a past session loads its messages.

**Actual:** 🔷 History looks empty / incomplete after cold start. ✔️ Device evidence (2026-07-18) shows this is a **JSON save** failure, not “nothing written.”

**Reproduce:**

1. Install chat POC APK; complete bootstrap (connection + model).
2. Send at least one chat turn (preferably a second session on the same calendar day).
3. `adb logcat --pid=$(adb shell pidof org.roojs.ollmchat.androidpoc) | grep -E 'session save|Failed to save'`
4. Inspect external history dir (not internal `files/`):
   `/sdcard/Android/data/org.roojs.ollmchat.androidpoc/files/ollmchat/history/`

### Evidence (2026-07-18)

- ℹ️ Location: `…/files/ollmchat/history/` on external storage (`XDG` beside `share/`).
- ✔️ `history.db` has rows (21+ sessions; newest ids 22–24 from this morning). `saveToDB()` runs before JSON write, so DB metadata updates even when JSON fails.
- ✔️ Session JSON: only the **first** save of the day often succeeds. Example: `2026/07/18/00-48-08.json` written; later fids `00-48-27`, `00-57-25` never got JSON.
- ✔️ Existing JSONs stay stale (often only `user-sent` + `ui`) while DB `total_messages` grows (e.g. 13–14).
- ✔️ Logcat (pid 7215), long reply / multi-turn this morning:

```
08:48:08 D Session.vala:412: session save
08:48:08 D Session.vala:447: session saved
08:48:27 D Session.vala:412: session save
08:48:27 W Session.vala:399: Failed to save session: Failed to create directory
  …/history/2026/07/18: … File exists
08:57:45 W … Failed to create directory …/2026/07/18: File exists
08:58:11 W … Failed to create directory …/2026/07/18: File exists
```

Seven `Failed to save session` warnings in this run after the first successful mkdir.

### Root cause

✔️ `Session.write()` uses `query_exists()` then `make_directory_with_parents()`, and treats **any** mkdir error as fatal. On Android external storage, after the day directory already exists, GIO still hits mkdir and returns `File exists`; the catch in `save_async` aborts **before** writing JSON (DB row already committed).

Same class of bug already fixed for `History.Manager` constructor and `AndroidApplication.ensure_directory` (EXISTS-tolerant). `Session.write()` / `task_dir()` were left on the brittle pattern.

🚫 Not primarily a load-path bug: load cannot restore messages that were never written to JSON.

### Proposed fix → ✔️ applied

✔️ `Session.write()` / `task_dir()` use `GLib.FileUtils.test(…, EXISTS)` before mkdir. Device verify 2026-07-18 09:28: repeated `session saved`; `01-28-46.json` is 34KB / 32 messages; DB rows present.

✔️ Load path still empty after cold start: `History.Manager.load_sessions()` skipped every row via `file.query_exists()` (same Android GIO lie). Fix: `FileUtils.test` there too (✔️ applied in tree).

**Status:** ✅ FIXED (user, 2026-07-18) — history overlay / persistence OK after FileUtils save+load fixes.

---

## Problem 4 — Selected model not remembered across restart

**Status:** ✅ FIXED (user, 2026-07-18)

**Expected:** 🔷 Pick Qwen (or any model) in the chat-bar dropdown, force-stop / cold start → same model stays selected.

**Actual:** 🔷 Always came back as `llama3.1:70b`.

### Evidence (2026-07-18 ~09:49, pid 27293)

- ✔️ On-disk `config.2.json` still had `"model" : "llama3.1:70b"` under `usage.default_model`.
- ✔️ Cold start:

```
AndroidStartup: initialize_model ok model=llama3.1:70b
AndroidApplication: saved config to …/config.2.json
AndroidStartup: run ok model=llama3.1:70b
Config2.vala:585: Failed to create config directory: …/ollmchat: File exists
```

- ✔️ `ChatBar` **does** update `default_model_usage` and calls `config.save()` on dropdown change — persistence was not “missing a call.”
- ✔️ `Config2.save()` treated **any** mkdir error as fatal and **`return`ed before writing JSON**. On Android external storage the dir already exists; GIO still reports `File exists` after a false-negative existence check → model change never reaches disk. Startup keeps loading llama3.1.
- ℹ️ Android startup persist path (`AndroidApplication.persist_config` → `FileUtils.set_contents`) succeeds; only the shared `Config2.save()` path used by ChatBar was failing.

### Root cause

✔️ `Config2.save()` early-returned on mkdir `File exists` instead of writing. Same Android external-storage class as Problem 1.

### Fix → ✅ verified

- `Config2.save()`: same pattern as `Session.write()` — `FileUtils.test(dir_path, EXISTS)` then bare `make_directory_with_parents` (no EXISTS special-case / early return).

---

## Problem 3 — Screen timeout kills in-flight LLM stream → “Network error”

**Status:** DEFERRED (2026-07-18) — POC 9.0 closed; reopened as **C1** in [`docs/bugs/2026-07-18-android-poc-completion.md`](../2026-07-18-android-poc-completion.md).

**Expected:** Long replies can finish even if the user is not touching the screen, **or** an interrupted stream fails gracefully with partial reply preserved and a clear message (not a generic network fault).

**Actual:** While the assistant is streaming from the remote Ollama server, the phone screen times out / locks for inactivity. Android suspends the app or tears down the TCP connection. The libsoup SSE read fails; the UI shows **“Network error: …”** (`ChatWidget` default `GLib.IOError` branch). Feels like a broken session even though the chat is still there.

**Reproduce:**

1. Start a long chat turn on device (model that streams visibly).
2. Do not touch the screen until display timeout / lock.
3. Wait for lock (or dim); unlock after a few seconds.
4. Observe stream abort + error banner in chat.

**Architecture (what is / is not remote):**

| Piece | Where it lives | Survives screen lock? |
|-------|----------------|------------------------|
| **Session / message history** | Local — `OLLMchat.History.Session.messages` + JSON under `files/history/` | **Yes** — session is not on the server |
| **Partial streamed text** | Local — appended to `content-stream` / `think-stream` messages in `Session.handle_stream_chunk` | **Usually yes** — chunks already received are in `messages` |
| **In-flight HTTP/SSE stream** | Remote — `ChatCompletions` → `connection.soup.send_async` + `read_line_async` on Ollama URL | **No** — OS drops the socket when the app is backgrounded / Doze |
| **Resume same generation** | N/A | **Not feasible** — Ollama has no “continue this SSE from offset N”; a new request is a new completion |

So: **the session is local**, but **the current reply’s network pipe is not**. On wake you still have the same session file and any tokens already streamed; you **cannot** reconnect mid-generation and pick up where the server left off.

**Current error path (code):**

- Stream read: `libollmchat/Call/ChatCompletions.vala` — `read_line_async` throws `GLib.IOError` when the connection drops.
- Bubble: `Agent.Base.send_async` → `Session.send` → `ChatWidget.send_message` catch → `handle_error("Network error: …")` (`libollmchatgtk/ChatWidget.vala` ~631–662).
- `handle_error` finalizes the assistant bubble, adds a danger UI frame, saves session, clears `is_running` — partial assistant text is kept (comment in code: “keep partial response content”).

**What is ruled in / out**

| Idea | Verdict |
|------|---------|
| “Restore remote session on wake” like a web app | **Out** — no server-side session; only local JSON |
| Resume the **same** Ollama SSE stream after reconnect | **Out** — not in Ollama API |
| Keep partial reply + soften error copy | **In** — UX improvement only |
| Prevent timeout **while streaming** | **In** — Android `FLAG_KEEP_SCREEN_ON` / GTK equivalent when `session.is_running` |
| Keep network alive with screen off (`PARTIAL_WAKE_LOCK`) | **Maybe** — OEM-dependent; permission + battery; needs spike |
| Auto-retry full turn on wake | **Risky** — duplicate user message or double assistant reply unless carefully designed |
| Foreground service for whole generation | **Out for POC** — heavy; Play policy |

**Options (for later approval — not ranked as fix yet):**

1. **🔷 Keep screen on while `session.is_running`** (Android-only) — wire `FLAG_KEEP_SCREEN_ON` on the GTK toplevel when streaming starts; clear in `cleanup_streaming_state` / `agent_status_change`. Stops timeout during active generation; battery cost if user walks away. No project uses this today (grep: no `keep_screen_on`).

2. **Softer interrupt UX (shared `ChatWidget`)** — On non-cancel `GLib.IOError` during stream, if `current_stream_message` has content: finalize stream, save, show *“Reply interrupted (connection lost). Partial text kept.”* instead of generic *Network error*. Same underlying failure; less alarming.

3. **💩 `PARTIAL_WAKE_LOCK` during stream** — Investigate whether holding a partial wake lock without keeping the display on preserves libsoup reads on test devices. Manifest + runtime permission; may still fail under aggressive power management.

4. **🚫 Auto-resume generation on unlock** — Would require re-sending the last user turn to Ollama (new completion), not resuming SSE. Easy to duplicate content; defer unless product wants explicit “Retry” only (input already auto-fills last text on error today).

5. **ℹ️ User workaround (no code)** — Tap **Stop** before locking, or increase system screen timeout during long chats.

**Next (debug, when we pick this up):**

- Reproduce with `adb logcat` during lock: libsoup / `GLib.IOError` code (`TIMED_OUT`, `BROKEN_PIPE`, etc.).
- Confirm partial assistant message + session JSON after error (`adb` pull `files/history/…`).
- Spike (1): `keep_screen_on` for one device build — does it stop the failure entirely?

---

## Problem 2 — `google_search` / `web_fetch` fail with unacceptable TLS certificate **✅ FIXED**

**Status:** **FIXED** — user verified `google_search` on device (2026-07-09). TLS fix shipped (Tool.soup + `AndroidConnectionTls` in `fill_tools()`). Mid-test **HTTP 400** was **bad engine-id in on-device config**, not TLS — corrected in Settings → Tools.

**Expected:** With Google Custom Search API key + engine ID configured in settings, a model that invokes `google_search` during an LLM turn fetches results from `https://www.googleapis.com/customsearch/v1`.

**Actual (user report, 2026-07-09):** Tool returns **Failed to fetch search results** / **error to fetch** with **Unacceptable TLS certificate** — same class of failure as pre-fix remote API calls before bundled CA wiring on connections.

**Reproduce:**

1. Configure `google_search` tool (`api_key`, `engine_id`) in Android settings.
2. Use a model + agent that can call search tools.
3. Send a prompt that triggers `google_search`.
4. Observe tool error in chat UI; capture logcat (`OLLMchat TLS`, `GSocketClient`, `g-tls-error-quark`).

**Likely root cause (code review, not yet verified on device):**

Remote **connection** HTTPS works because Android startup applies bundled CA trust to each `OLLMchat.Settings.Connection.soup` session:

- `AndroidConnectionConfigTls.apply_to_config` → `AndroidConnectionTls.apply_to_session(connection.soup)`

**Tools create their own `Soup.Session` without that wiring:**

```215:217:liboctools/GoogleSearch/Request.vala
				var session = new Soup.Session();
				message = new Soup.Message("GET", url);
				content = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
```

Same pattern in `liboctools/WebFetch/Request.vala` — so `web_fetch` is probably broken on device for HTTPS URLs too, even though 9.0 marks it ✅.

**Hypothesis:** Missing `GTlsFileDatabase` on tool-owned sessions → `UNKNOWN_CA` / `Unacceptable TLS certificate` when hitting public HTTPS hosts (Google APIs, arbitrary URLs).

**Approved approach (2026-07-09):** Mirror `Connection` — `Soup.Session` on the **Tool** (constructor), **Request** uses `this.tool.soup`, Android applies bundled CA in `fill_tools()` right after each HTTP tool is created. Same pattern as `AndroidConnectionConfigTls.apply_to_connection` — no GLib patch, no `#if` in `liboctools` for TLS.

**What is ruled in / out**

| Hypothesis | Verdict |
|------------|---------|
| Missing / wrong API key or engine ID | **Out** for TLS symptom — would be HTTP 4xx or config error, not cert rejection |
| `GDummyTlsBackend` (no TLS at all) | **Out** — remote Ollama HTTPS on connection works |
| Tool `Soup.Session` lacks bundled CA DB | **In** — matches connection-vs-tool split |
| Google-specific cert issue | **Out (likely)** — same error class as earlier generic HTTPS failures |

**🚫 Do not:** disable cert verification, `g_setenv` for CA paths, or add `#if OLLM_ANDROID` inside `liboctools` request code.

**Verification plan:**

1. Reproduce `google_search` failure with logcat cert error flags (optional — root cause already clear from code).
2. After fix: `google_search` returns results; `web_fetch` to `https://` URL succeeds.
3. Logcat: `OLLMchat TLS: Soup.Session tls_database=.../ca-certificates.crt` when tools run.
4. Regression: connection chat + model list still works.

**After fix (verified):**

- TLS: `google_search` reaches Google APIs on device (no cert error).
- HTTP 400 during bring-up: `adb` config compare showed corrupted **engine-id** on phone vs desktop; user corrected settings → search works.
- **💩** Follow-up (optional): `SettingsDialog/Rows/String.vala` does not `.strip()` entry text (connection rows do) — can leave trailing newlines in tool API key; not blocking once engine-id is correct.

---

### Proposed fix — Problem 2 (TLS on tool HTTP sessions) **✔️ implemented**

Implement and verify **one file at a time**. Code fences use **Remove** / **Replace with** / **Add** per `docs/guide-to-writing-plans.md`.

**Design:**

- **🔷** `Soup.Session` lives on `GoogleSearch.Tool` and `WebFetch.Tool` (like `Connection.soup`).
- **🔷** `Request.execute_request()` uses `(Tool) this.tool` → `tool.soup` (`RequestBase.tool` is set in `BaseTool.execute()` before `execute_request()`).
- **🔷** Android-only: `AndroidToolsRegistration.fill_tools()` calls `AndroidConnectionTls.apply_to_session(tool.soup)` after each HTTP tool is constructed.
- **ℹ️** `session_fetch` — no HTTP; unchanged.
- **ℹ️** Desktop — `Soup.Session` without `tls-database` is fine (system CAs).

---

#### T1. `liboctools/GoogleSearch/Tool.vala` — session on tool

**Where:** after `project_manager` property; in constructor.

##### Add — field after `project_manager`

```vala
		/**
		 * HTTP session for Google Custom Search API requests.
		 * On Android, the app applies bundled CA trust to this session at registration.
		 */
		public Soup.Session soup;
```

##### Replace — constructor body

```vala
		public Tool(OLLMfiles.ProjectManager? project_manager = null)
		{
			base();
			this.project_manager = project_manager;
			this.soup = new Soup.Session();
		}
```

(`clone()` returns `new Tool(...)` → fresh session; Android only TLS-wires instances from `fill_tools()`.)

---

#### T2. `liboctools/GoogleSearch/Request.vala` — use tool session

**Where:** `execute_request()`, fetch block (~214–217).

##### Remove

```vala
			try {
				var session = new Soup.Session();
				message = new Soup.Message("GET", url);
				content = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
```

##### Replace with

```vala
			var tool_obj = (Tool) this.tool;
			try {
				message = new Soup.Message("GET", url);
				content = yield tool_obj.soup.send_and_read_async(
					message, GLib.Priority.DEFAULT, null);
```

---

#### T3. `liboctools/WebFetch/Tool.vala` — session on tool

**Where:** after `project_manager` property; in constructor.

##### Add — field after `project_manager`

```vala
		/**
		 * HTTP session for URL fetch requests.
		 * On Android, the app applies bundled CA trust to this session at registration.
		 */
		public Soup.Session soup;
```

##### Replace — constructor body

```vala
	public Tool(OLLMfiles.ProjectManager? project_manager = null)
	{
		base();
		this.project_manager = project_manager;
		this.soup = new Soup.Session();
	}
```

---

#### T4. `liboctools/WebFetch/Request.vala` — use tool session (two sites)

**Where:** `execute_request()` main fetch (~86–89) and `fetch_url()` (~189–192).

##### Remove — `execute_request()` fetch block

```vala
			try {
				// Note: libsoup 3.0 handles redirects automatically, but we check status codes
				// and handle redirects manually below to require approval
				var session = new Soup.Session();
				message = new Soup.Message("GET", this.url);
				message.request_headers.replace("User-Agent", USER_AGENT);
				content = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
```

##### Replace with

```vala
			var tool_obj = (Tool) this.tool;
			try {
				// Note: libsoup 3.0 handles redirects automatically, but we check status codes
				// and handle redirects manually below to require approval
				message = new Soup.Message("GET", this.url);
				message.request_headers.replace("User-Agent", USER_AGENT);
				content = yield tool_obj.soup.send_and_read_async(
					message, GLib.Priority.DEFAULT, null);
```

##### Remove — `fetch_url()`

```vala
		protected async Bytes fetch_url(string url) throws Error
		{
			var session = new Soup.Session();
			var message = new Soup.Message("GET", url);
			message.request_headers.replace("User-Agent", USER_AGENT);
			var bytes = yield session.send_and_read_async(message, GLib.Priority.DEFAULT, null);
```

##### Replace with

```vala
		protected async Bytes fetch_url(string url) throws Error
		{
			var tool_obj = (Tool) this.tool;
			var message = new Soup.Message("GET", url);
			message.request_headers.replace("User-Agent", USER_AGENT);
			var bytes = yield tool_obj.soup.send_and_read_async(
				message, GLib.Priority.DEFAULT, null);
```

---

#### T5. `ollmapp/android/AndroidToolsRegistration.vala` — apply bundled CA

**Where:** `fill_tools()`.

##### Remove

```vala
		public static void fill_tools(OLLMchat.History.Manager manager)
		{
			manager.register_tool(new OLLMtools.WebFetch.Tool(null));
			manager.register_tool(new OLLMtools.SessionFetch.Tool());
			var google_search = new OLLMtools.GoogleSearch.Tool(null);
			manager.register_tool(google_search);
			manager.tools.set("web_search", google_search);
		}
```

##### Replace with

```vala
		public static void fill_tools(OLLMchat.History.Manager manager)
		{
			var web_fetch = new OLLMtools.WebFetch.Tool(null);
			AndroidConnectionTls.apply_to_session(web_fetch.soup);
			manager.register_tool(web_fetch);

			manager.register_tool(new OLLMtools.SessionFetch.Tool());

			var google_search = new OLLMtools.GoogleSearch.Tool(null);
			AndroidConnectionTls.apply_to_session(google_search.soup);
			manager.register_tool(google_search);
			manager.tools.set("web_search", google_search);
		}
```

**ℹ️** Same hook as `AndroidBootstrapConnectionAdd` / `ConnectionAdd` — apply TLS immediately after `new Connection()` / `new Tool()`, before first HTTPS use.

**💩 Optional follow-up (not in this fix):** if desktop `Registry.fill_tools()` ever needs shared session wiring, extract an Android-only `apply_tool_tls(Manager)` helper — not needed for POC while only `fill_tools()` registers HTTP tools on device.

---

**Old proposed directions (superseded):**

~~Apply TLS inside `Request` with `#if OLLM_ANDROID`~~ — rejected; keeps TLS logic in Android registration layer.

~~Central session factory helper in `liboctools`~~ — not needed; `Connection` pattern uses a public field on the tool object.


---

## Changelog

| Date | Change |
|------|--------|
| 2026-07-09 | Opened from user device report; TLS hypothesis from code review vs working connection path |
| 2026-07-09 | Problem 2 — proposed fix documented (Tool.soup + Android `fill_tools` TLS); awaiting approval |
| 2026-07-09 | Problem 2 — **implemented** T1–T5 per approved proposal; device verify pending |
| 2026-07-09 | Problem 2 — **✅ user verified** on device (`google_search` working); HTTP 400 was config not TLS |
| 2026-07-09 | Problem 3 — screen timeout interrupts SSE stream → Network error; options documented |
| 2026-07-18 | Problem 1 — ✅ history save+load FileUtils fixes verified by user |
| 2026-07-18 | Problem 4 — default model stuck on llama3.1; Config2.save FileUtils mkdir pattern; **✅ user verified** |
| 2026-07-18 | Archive FIXED — POC 9.0 closed; Problem 3 deferred |
