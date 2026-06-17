# Android chat POC — device issues (active debug loop)

**Status:** OPEN  
**Opened:** 2026-06-17  
**Package:** `org.roojs.ollmchat.androidpoc`  
**Build:** `scripts/android/build-chat-poc-apk.sh` → `scripts/android/adb-install-chat-poc.sh`  
**Index:** [`docs/android-port-status.md`](../android-port-status.md) (short summary + commands)

---

## How we work

### Golden rules

1. **Android-only code changes** — fixes live under `ollmapp/android/`, Android meson branches, `android/icons/`, GTK fork / pixiewood wraps as needed.  
2. **Do not edit shared / desktop code** (`ConnectionAdd`, `ChatWidget`, `Initialize`, `Window`, `libollmchatgtk/`, etc.) unless you have **explicit permission**.  
3. **If a fix seems to require shared code** — **stop**, do not implement. Propose the change in the doc (or to the user): what file, what change, and why Android-only is not enough. Wait for approval.  
4. **Copy patterns, don’t refactor** — mirror desktop behaviour in new Android files (see plan 9.1).

### Debug loop (one round)

Each round is **agent-driven** end-to-end. Do **not** stop at “proposed fix” — **apply** the fix, update this doc, build, and install (or ask for wireless debugging).

1. **You** — Test the last installed APK on device; report pass/fail per § (or initial symptoms on first round).
2. **Agent** — **Record results of the previous change**: update **Device timeline**, each § **Status** / **What we tried**, and the checklist. If your feedback contradicts an earlier “pass”, mark it **Fail** and note why.
3. **Agent** — **Apply** Android-only fixes for **every open §** this round — do not pick just one when several remain. (If only one § is still open, fix that one.) Update this doc: what changed per §, expected effect. If shared code is required for any § → **stop** here and ask (golden rule §3).
4. **Agent** — **Build + install** on your phone: `scripts/android/build-chat-poc-apk.sh` then `scripts/android/adb-install-chat-poc.sh`. Optionally capture logcat (commands below).
   - If `adb` has **no device** (offline / unauthorized / empty `adb devices`): **stop here**. Do not guess. Reply: **“Can you enable wireless debugging?”** and wait. Do not continue until install succeeded.
5. **You** — Cold-start test on device; go back to step 1.

**Repeat** until Phase 3 pass criteria below are met.

**Agent must not:** land a fix without updating the doc; update “Next loop fixes” without building; ask you to install manually when `adb` works; address only one § when multiple are still open (unless blocked on shared-code approval).

**Logcat after repro:**

```bash
adb shell am force-stop org.roojs.ollmchat.androidpoc
adb logcat -c
adb shell am start -n org.roojs.ollmchat.androidpoc/org.gtk.android.ToplevelActivity
sleep 15
adb logcat -d | grep -iE 'AndroidApplication|AndroidStartup|saved config|load_config|connections|bootstrap|initialize_client|GTlsBackend|default_model|critical|warning.*Android'
```

**Config on device:**

```bash
adb shell cat /storage/emulated/0/Android/data/org.roojs.ollmchat.androidpoc/files/etc/ollmchat/config.2.json
```

---

## Device timeline

| When | APK / tree | Result | Notes |
|------|------------|--------|-------|
| 2026-06-17 | Chat POC (pre-fix batch) | **Fail** — multiple § open | `config.2.json` on disk with connection + api-key; user still sees bootstrap and blank UI |
| — | *Awaiting round 2* | — | User feedback recorded above; agent applies **all open §** (see **Next loop fixes**), builds, installs, then user re-tests |

---

## Checklist (section status)

- [x] **§1 Config write** — file on disk verified via adb  
- [ ] **§2 Config load / skip bootstrap** — user reports bootstrap every restart  
- [ ] **§3 Startup → chat shell** — blank main area after save/restart  
- [ ] **§4 Agent dropdown** — shows “None”  
- [ ] **§5 Chat input / send bar** — missing when shell appears  
- [ ] **§6 About icon** — broken in header  
- [ ] **§7 Default model in saved JSON** — `model` still empty after save  

---

## §1 Config write (persist to disk)

**Status:** **PASS** (device-verified 2026-06-17)

### Desired result

After bootstrap or settings save, connection URL and API key survive app restart and APK asset re-extraction. File lives outside GTK `share/` tree.

### Actual (device)

File exists:

```
/storage/emulated/0/Android/data/org.roojs.ollmchat.androidpoc/files/etc/ollmchat/config.2.json
```

Example (connection + api-key present):

```json
{
    "connections": {
        "https://ollama.roojs.com/api": {
            "name": "Default",
            "url": "https://ollama.roojs.com/api",
            "api-key": "…",
            "is-default": true,
            "ollama-native": 1
        }
    },
    "usage": {
        "default_model": { "connection": "…", "model": "", "options": {} }
    }
}
```

Logcat string in APK: `AndroidApplication: saved config to …`

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | `persist_config()` → `files/etc/ollmchat/` via `XDG_CONFIG_HOME` | **Pass** — file written |
| 2 | Direct `Json.Generator` + `set_contents` (not only `config.save()`) | **Pass** — confirmed on device |

### Code

`ollmapp/android/AndroidApplication.vala` — `persist_config()`, `config_storage_dir()`

### Not the problem

“Config not saved” — **incorrect**. The file is there. Downstream load/startup is broken (§2–§3).

---

## §2 Config load / skip bootstrap on restart

**Status:** **OPEN** — user reports app **always asks to fill in connection again** despite §1 file on disk

### Desired result

Cold start with existing `config.2.json` → **no** bootstrap dialog; app goes straight to `AndroidStartup.run()`.

Gate in code: `if (this.app.config.connections.size == 0)` → bootstrap, else startup.

### Actual (user report)

Bootstrap connection dialog appears on every launch even after successful save.

### Hypotheses (unverified)

1. `load_config()` returns empty `connections` — wrong `XDG_CONFIG_HOME` at load time, deserialize failure, or read error (check logcat for `Failed to load config`).  
2. **Early load in `AndroidApplication()` constructor** (before GDK sets Android XDG dirs) leaves stale empty `app.config`; secondary bug if something reads config before `load_config_and_initialize()`.  
3. User testing an **older APK** without `etc/ollmchat` path (file exists from newer build, app binary is old).  
4. Bootstrap shown for a **different reason** (e.g. startup failure then re-enter bootstrap — needs logcat).

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Gate on `connections.size == 0` instead of `config.loaded` | **Unknown** — not confirmed on device after install |
| 2 | Migration from legacy `share/ollmchat/config/` paths | **Unknown** |
| — | *No log lines yet for connection count at load* | — |

### Next step (this batch)

- Add `GLib.message` in `load_config()`: path, file exists, `connections.size` after load.  
- Remove or defer constructor `load_config()` if XDG not ready (Android-only).  
- Cold-start logcat + user confirms bootstrap yes/no.

### Code

`ollmapp/android/AndroidApplication.vala` — `load_config()`  
`ollmapp/android/AndroidMainWindow.vala` — `load_config_and_initialize()`

---

## §3 Startup → chat shell (blank main UI)

**Status:** **OPEN**

### Desired result

After config load (or bootstrap), `AndroidStartup.run()` succeeds → `initialize_client()` mounts `HistoryBrowser` + `ChatWidget` in `split_view.content`.

### Actual

Header bar visible; **main area empty** (no history, no chat). Sometimes after bootstrap save in same session; also on restart.

### Hypotheses

1. `AndroidStartup.run()` returns **false** (connection check or model pick fails).  
2. `initialize_after_bootstrap()` has **no error UI** when startup fails — silent empty pane (reload path shows error label; post-bootstrap path does not).  
3. `default_model.model` empty in file (§7) → `initialize_model()` should auto-pick; if that fails, startup aborts.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Wire `ChatWidget` + `HistoryBrowser` in `initialize_client()` | **Not reached** on device if startup fails |
| 2 | Error label on reload path when `startup.run()` fails | **Partial** — only on reload, not post-bootstrap |
| — | Startup failure logging | **Not implemented** |

### Next step (this batch)

- `persist_config()` immediately after bootstrap verify (mirror desktop `config.save()`).  
- Same error label in `initialize_after_bootstrap()` when startup fails.  
- Log at each `AndroidStartup.run()` exit: working connection, model name, return reason.

### Code

`ollmapp/android/AndroidMainWindow.vala`, `ollmapp/android/AndroidStartup.vala`  
Desktop reference (read only): `ollmapp/Window.vala`, `ollmapp/Initialize.vala`

---

## §4 Agent dropdown (“None”)

**Status:** **OPEN** (likely **downstream of §3**)

### Desired result

Header dropdown lists **Just Ask** and **Chatter** (minimum); selection matches active session agent.

### Actual

Dropdown shows **“None”** or empty.

### Cause (code)

`setup_agent_dropdown()` only runs inside `initialize_client()`. If §3 fails, dropdown never populated. Uses `Gtk.StringList` + `agent_picker_names[]` (replaced broken `ListStore` + `PropertyExpression`).

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Register `OLLMchat.Chatter.Factory` in `initialize_client()` | **Not verified** — init not reached |
| 2 | `Gtk.StringList` for dropdown labels | **Not verified** on device |

### Next step

Fix §3 first; re-test. If dropdown still wrong with chat visible, debug `History.Manager.agent_factories` and `session.agent_name`.

### Code

`ollmapp/android/AndroidMainWindow.vala` — `setup_agent_dropdown()`, `initialize_client()`

---

## §5 Chat input / send bar missing

**Status:** **OPEN** (likely **downstream of §3**, possible secondary bug)

### Desired result

Chat area shows message history (or empty state) plus input field and send/stop button.

### Actual

No input, no send control — blank chat region.

### Hypotheses

1. **Primary:** `ChatWidget` never created (§3).  
2. **Secondary:** `ChatWidget.switch_to_session()` calls `streaming_state(true)` and hides input until `agent_status_change`; if signal never fires or paned height is 0 at first layout, input stays hidden.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | `switch_to_session` + `active_factory.activate` in `initialize_client()` | **Not verified** |
| 2 | Shared `ChatWidget` idle fix for `streaming_state` | **Reverted** — do not change shared code without approval |

### Next step

Fix §3; if input still missing with chat visible, Android-only post-layout callback after `switch_to_session` (in `AndroidMainWindow`, not `ChatWidget`).

### Code

`ollmapp/android/AndroidMainWindow.vala`, `libollmchatgtk/ChatWidget.vala` (read only unless approved)

---

## §6 About icon (header)

**Status:** **OPEN**

### Desired result

About button in header shows Adwaita `help-about-symbolic` icon; tap opens About window.

### Actual

Broken / missing icon (user report).

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Added `help-about-symbolic.svg` to `android/icons/manifest` | **Unknown** — may not be in installed APK assets; needs `strings`/asset verify on built APK |

### Next step

After next build: verify icon in APK assets; confirm GTK icon theme loads symbolic from asset tree. Re-extract assets if stale install.

### Code

`android/icons/manifest`, `ollmapp/About.vala` (`icon_name = "help-about-symbolic"`)

---

## §7 Default model empty in saved JSON

**Status:** **OPEN**

### Desired result

After first successful boot, `usage.default_model.model` is a non-empty chat model name in `config.2.json`.

### Actual

Connection saved; **`model`: ""** in file (device 2026-06-17).

### Hypotheses

1. Persist happened before `AndroidStartup.initialize_model()` completed.  
2. Bootstrap path does not call `persist_config()` immediately (desktop saves right after verify).  
3. `initialize_model()` fails silently → startup aborts (§3) before model written.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | `initialize_model()` auto-picks first non-embedding model | **Not confirmed** — empty model still on disk |
| 2 | `persist_config()` at end of `AndroidStartup.run()` | **Partial** — connection in file, model not |

### Next step (this batch)

- Persist right after bootstrap verify.  
- Log model name when `initialize_model()` succeeds.  
- Re-check JSON after successful cold start.

### Code

`ollmapp/android/AndroidStartup.vala` — `initialize_model()`  
`ollmapp/android/AndroidMainWindow.vala` — bootstrap `closed` handler

---

## Next loop fixes (agent: apply all open § → doc → build → install)

Each round should attempt **every open §** below (and any other § still marked OPEN in this doc). After apply: move items into each § **What we tried**, add a **Device timeline** row, then replace this list for the following round.

- **§2** — Log `load_config` path, exists, `connections.size`; defer constructor load if needed  
- **§3, §7** — `persist_config()` in bootstrap `closed` handler (before `initialize_after_bootstrap`)  
- **§3** — Error label when `initialize_after_bootstrap` → startup fails  
- **§3, §7** — Log `AndroidStartup.run()` failure reason (connection / model / verify)  
- **§4, §5** — Android-only fixes if startup path is unblocked; if still purely downstream of §3, note that in the doc after §3 is fixed  
- **§6** — Verify icon in APK assets; fix manifest / asset path if missing  
- **§5 (secondary)** — Post-layout callback in `AndroidMainWindow` if input still hidden after §3 passes  

---

## Pass criteria (Phase 3)

- [ ] §2 Cold start → no bootstrap when config file has connections  
- [ ] §3 Main area shows chat shell (not blank)  
- [ ] §4 Agent dropdown shows agent names  
- [ ] §5 Input + send visible and usable  
- [ ] §6 About icon visible  
- [ ] §7 Saved JSON has non-empty `default_model.model` after first good boot  

---

## Related (closed / reference)

- TLS / IME / paste: [`docs/bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md`](done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md)  
- TLS notes: [`docs/android-tls-solution.md`](../android-tls-solution.md)  
- Plan: [`docs/plans/9.1-android-chat-shell.md`](../plans/9.1-android-chat-shell.md)
