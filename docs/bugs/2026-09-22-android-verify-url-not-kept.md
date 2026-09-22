# Android Verify drops https and /api on edit

**Status:** ⏳ root cause from code; fix applied — await device ✅

**Pointer:** `docs/bug-fix-process.md`

## Problem

- 🔷 After Verify pads `https://` and appends `/api`, opening the
  connection to edit shows the original host (no scheme, no `/api`).
- 🔷 Later Verify / chat then fails.
- 🔷 Expected: the URL field and saved config keep the canonical URL.

## Evidence

- ℹ️ Follows `docs/bugs/2026-09-22-android-verify-connection-crash.md`
  (pad after `apply_config` so Soup gets a host).
- ✔️ `verify_connection` stores `test_connection.url` (padded + `/api`)
  and sets `row.urlEntry.text`, then `config.save()`.
- ✔️ Android `MainDialog.on_closed` (and desktop) calls
  `connections_page.apply_config()` then persist/save.
- ✔️ `ConnectionRow.apply_config` copies `urlEntry.text` onto
  `connection.url` with no scheme pad and no `/api`.
- ✔️ JSON keeps HashMap **key** and nested `url` separately; the editor
  loads `connection.url` into the field.
- ✔️ `ConnectionRow.url` is construct-only, so after remap the row
  identity stays the pre-verify key.

## Root cause

- ✔️ Dialog close treats the URL **entry** as source of truth and
  overwrites the canonical URL Verify already stored. The entry still
  has what was typed (`ollama.roojs.com` or `https://host/` without
  `/api`) — setting `.text` after Verify does not survive focus/IME /
  close.
- ✔️ Persist then writes that stale `url`; the next edit shows it.

## Proposed fix

- 🔷 `apply_config` pads `https://` the same way Verify does, and keeps
  the existing `connection.url` when it is that host plus `/api`.
- 🔷 After Verify, move focus off the URL field, write the canonical
  text, and set `row.url` so later Verify uses the remapped key.

### `ollmapp/SettingsDialog/ConnectionRow.vala`

#### Remove

```vala
		public string url { get; construct; }
```

#### Replace with

```vala
		public string url { get; construct set; }
```

#### Remove

```vala
			connection.name = this.nameEntry.text.strip();
			connection.url = this.urlEntry.text.strip();
			connection.api_key = this.apiKeyEntry.text.strip();
```

#### Replace with

```vala
			connection.name = this.nameEntry.text.strip();
			var url = this.urlEntry.text.strip();
			if (!url.has_prefix("http://") && !url.has_prefix("https://")) {
				url = "https://" + url;
			}
			var prefix = url;
			if (prefix.has_suffix("/")) {
				prefix = prefix.substring(0, prefix.length - 1);
			}
			if (connection.url == prefix + "/api" || connection.url == prefix + "/api/") {
				url = connection.url;
			}
			connection.url = url;
			connection.api_key = this.apiKeyEntry.text.strip();
```

### `ollmapp/SettingsDialog/ConnectionsPage.vala` — end of `verify_connection`

#### Remove

```vala
			test_connection.timeout = original_timeout;
			newUrl = test_connection.url;
			row.urlEntry.text = newUrl;
```

#### Replace with

```vala
			test_connection.timeout = original_timeout;
			newUrl = test_connection.url;
			row.nameEntry.grab_focus();
			row.urlEntry.text = newUrl;
			row.url = newUrl;
```

## Attempts / changelog

- ✔️ 2026-09-22 — diagnosed close-path clobber; apply pad+keep `/api`
  in `apply_config`; update `row.url` after Verify.
- ✔️ APK built and installed (`app-arm64-v8a-debug.apk`).

## Next

- 🔷 ⏳ Verify a host without scheme; close settings; reopen — field
  must still show `https://…/api`.
