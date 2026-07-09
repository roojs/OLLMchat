# Android chat POC — history + tool HTTPS (TLS)

**Status:** OPEN — Problem 2 fix **proposed** (awaiting approval); Problem 1 still needs device debug

**Started:** 2026-07-09

**Package:** `org.roojs.ollmchat.androidpoc`

**Process:** `docs/bug-fix-process.md`

**Related:**

- [`docs/plans/9.0-android-poc-summary.md`](../plans/9.0-android-poc-summary.md) — active POC summary
- [`docs/android-tls.md`](../android-tls.md) — TLS backend + bundled CA (connection API calls work)
- [`docs/bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md`](done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md) — prior TLS investigation
- [`docs/bugs/2026-06-18-android-popover-touch-grab.md`](2026-06-18-android-popover-touch-grab.md) — separate UI annoyance (left open)

**Still open elsewhere:** popover touch-grab near chat-bar controls — minor; not blocking this log.

---

## Problem 1 — Chat history not recorded / not loading

**Expected:** After sending messages on device, sessions appear in the history overlay and survive `force-stop` / cold start. Selecting a past session loads its messages.

**Actual (user report, 2026-07-09):** History is either **not being saved** or **not loading** on device — unclear which without log capture. Cold boot may open a fresh `EmptySession` even when prior chats existed.

**Reproduce (suspected):**

1. Install chat POC APK; complete bootstrap (connection + model).
2. Send at least one chat turn; open history overlay — note whether the session appears.
3. `adb shell am force-stop org.roojs.ollmchat.androidpoc`; relaunch.
4. Check history overlay again; inspect `files/history/` under app data dir.

**Code pointers:**

- History dir: `AndroidApplication` ensures `data_dir/history` exists.
- Manager: `AndroidStartup` creates `OLLMchat.History.Manager`; `OllmchatWindow.initialize_client` wires `HistoryBrowser`.
- Saves: `OLLMchat.History.Session.save_async` writes JSON under `manager.history_dir`.
- Boot session: cold start may always create `EmptySession` — see 9.0 backlog **Session lifecycle**.

**Next (debug):**

- Log `save_async` path + errors on device (`--debug` if routed).
- `adb shell run-as … ls -la files/history/` after send + after force-stop.
- Confirm whether sidebar lists DB rows but `switch_to_session` / `load()` fails vs no rows at all.

---

## Problem 2 — `google_search` / `web_fetch` fail with unacceptable TLS certificate

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

---

### Proposed fix — Problem 2 (TLS on tool HTTP sessions)

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
