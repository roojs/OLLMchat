# Android Verify connection SIGSEGV

**Status:** ✅ FIXED — user archived 2026-09-23 (Verify no longer SIGSEGV)

**Pointer:** `docs/bug-fix-process.md`

## Problem

- 🔷 Verify on an edited connection crashes the Android chat POC.
- 🔷 Expected: Verify pads a missing scheme / `/api` and saves.
- 🔷 Actual: SIGSEGV on tap.

## Evidence

- ℹ️ Tombstone `2026-09-22 16:01:08`, pid 9930, tid GTK Thread.
- ✔️ `signal 11 SEGV_MAPERR` at addr 0, `g_hostname_is_ip_address` → `Connection.soup_message`.
- ✔️ Stack: Verify `clicked` → `exec_models` → `send_request` → `soup_message`.
- ✔️ Config still `https://ollama.roojs.com/` (no `/api`); user was told a host without scheme is OK.

## Root cause

- ✔️ `verify_connection` pads `newUrl`, then `row.apply_config` copies `urlEntry.text` back onto the connection and drops the scheme.
- ✔️ `Soup.Message` for `ollama.roojs.com` has a null host; `Hostname.is_ip_address(null)` dereferences.

## Proposed fix

- 🔷 Pad `test_connection.url` **after** `apply_config`, then use that as `newUrl`.
- 🚫 Null-check `get_host()` in `soup_message` — that only hides bad URLs.

### `ollmapp/SettingsDialog/ConnectionsPage.vala` — `verify_connection`

#### Remove

```vala
			if (!newUrl.has_prefix("http://") && !newUrl.has_prefix("https://")) {
				newUrl = "https://" + newUrl;
			}

			var newName = row.nameEntry.text.strip();
			var test_connection = new OLLMchat.Settings.Connection() {
				name = newName != "" ? newName : newUrl,
				url = newUrl
			};
			row.apply_config(test_connection);
```

#### Replace with

```vala
			var newName = row.nameEntry.text.strip();
			var test_connection = new OLLMchat.Settings.Connection() {
				name = newName != "" ? newName : newUrl,
				url = newUrl
			};
			row.apply_config(test_connection);
			if (!test_connection.url.has_prefix("http://") && !test_connection.url.has_prefix("https://")) {
				test_connection.url = "https://" + test_connection.url;
			}
			newUrl = test_connection.url;
```

## Attempts / changelog

- ✔️ 2026-09-22 — logcat tombstone; apply pad after `apply_config`.

## Next

- ✅ 2026-09-23 — user closed this bug (Verify on a host without `https://`).
- ℹ️ Construct-key follow-up landed in [`2026-09-22-FIXED-android-verify-url-not-kept.md`](2026-09-22-FIXED-android-verify-url-not-kept.md).
