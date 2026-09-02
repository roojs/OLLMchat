# Android Add Model search: ollama.com TLS reject

**Status:** ✅ FIXED — user closed 2026-09-02 (Add Model search returns rows)

**Started:** 2026-08-31

**Package:** `org.roojs.ollmchat.androidpoc` pid **9210**

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ TLS design: [`docs/android-tls.md`](../android-tls.md) — CA is set **per** `Soup.Session`, not as the GIO default
- ℹ️ Connections / tools already call `AndroidConnectionTls.apply_to_session`
- ℹ️ Add Model uses `OLLMchat.Settings.SearchResults` → `OllamaWeb.Search.Client` soup (now public)
- ℹ️ Parser-empty search (different bug, already ✅): [`done/2026-07-19-FIXED-libollamaweb-model-search-broken.md`](done/2026-07-19-FIXED-libollamaweb-model-search-broken.md)

---

## Problem

🔷 Settings → Add Model → type in the model search pulldown: **no results**. User suspected `SearchablePulldown`.

---

## Evidence

Device SM_S9380, 2026-08-31, pid 9210 (fresh launch 09:09:32).

- ✔️ 09:09:47.531 — `Gdk Android.Popup: present` (`GdkAndroidPopup`). Pulldown **did** map (225×255 px → 60×68 CSS).
- ✔️ 09:09:49.058 — DNS + TCP to **ollama.com** succeeded
- ✔️ 09:09:49.120 — `SearchResults.vala:171: ollama.com search failed: Unacceptable TLS certificate`
- 🚫 Not “popover never opens.” Search ran; HTTPS was rejected.
- 💩 Popup is tiny (60×68). May look empty even after TLS works. Separate from this log line.

`OllamaWeb.Search.Client` owned a private `new Soup.Session()` with no bundled CA. Chat HTTPS works because `AndroidConnectionTls` is applied to **connection** soup and tool soup.

---

## Root cause

✔️ Android has no system CA path for native code. TLS backend is loaded, but **trust store is per session**. Add Model’s soup never gets `GTlsFileDatabase` → `Unacceptable TLS certificate`.

---

## Proposed fix

🔷 Follow existing CA wiring: public `soup` (same as `WebFetch.Tool.soup`), then `AndroidConnectionTls.apply_to_session` from Add Model under `#if ANDROID` (same as `ConnectionAdd.vala`).

🚫 Do not set the GIO TLS backend default database. 🚫 Do not revert C5. 🚫 Do not special-case the pulldown widget for this log line.

### 1. `libollamaweb/Search/Client.vala` — public `soup`

**Why:** Tools expose `soup` so Android can apply the bundled CA. **Where:** field that was private `session`. **Depends on:** none.

#### Remove

```vala
		private Soup.Session session { get; set; default = new Soup.Session(); }
```

#### Replace with

```vala
		/**
		 * HTTP session for ollama.com catalog requests.
		 *
		 * On Android, the app applies bundled CA trust to this session when
		 * Add Model is constructed.
		 */
		public Soup.Session soup { get; set; default = new Soup.Session(); }
```

#### Remove

```vala
				var bytes = yield this.session.send_and_read_async(
```

#### Replace with

```vala
				var bytes = yield this.soup.send_and_read_async(
```

### 2. `libollamaweb/Search/Service.vala` — `soup` forwards to client

**Why:** `Client` stays private; Add Model reaches soup via `Session`. **Where:** after `client` / `parser` fields. **Depends on:** 1.

#### Add — after `private Parser parser …`

```vala
		/**
		 * HTTP session for ollama.com catalog requests.
		 *
		 * Same instance as {@link Client.soup}.
		 */
		public Soup.Session soup {
			get {
				return this.client.soup;
			}
		}
```

### 3. `libollamaweb/Search/Session.vala` — `soup` forwards to service

**Why:** `SearchResults.session` is already public. **Where:** after `service` field. **Depends on:** 2.

#### Add — after `private Service service …`

```vala
		/**
		 * HTTP session for ollama.com catalog requests.
		 *
		 * Same instance as {@link Client.soup}. On Android, the app applies
		 * bundled CA trust to this session when Add Model is constructed.
		 */
		public Soup.Session soup {
			get {
				return this.service.soup;
			}
		}
```

### 4. `ollmapp/SettingsDialog/AddModelDialog.vala` — apply CA after SearchResults

**Why:** Same call site pattern as `AndroidToolsRegistration.fill_tools` and `ConnectionAdd` `#if ANDROID`. **Where:** immediately after `new SearchResults`. **Depends on:** 3.

#### Remove

```vala
			this.search_results = new OLLMchat.Settings.SearchResults(this.dialog.app.data_dir);
			this.closed.connect(() => {
```

#### Replace with

```vala
			this.search_results = new OLLMchat.Settings.SearchResults(this.dialog.app.data_dir);
#if ANDROID
			AndroidConnectionTls.apply_to_session(this.search_results.session.soup);
#endif
			this.closed.connect(() => {
```

---

## Attempts / changelog

- ✔️ 2026-08-31 — logcat: popup present; `Unacceptable TLS certificate` on ollama.com.
- ✔️ 2026-08-31 — applied per-session `apply_to_session` (not GIO default database).

## Next

- ✅ User closed 2026-09-02. Popover width/height layout tracked separately in [`2026-09-02-android-add-model-search-popover-layout.md`](../2026-09-02-android-add-model-search-popover-layout.md).
