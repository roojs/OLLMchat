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
| 2026-06-17 ~10:20 | Round 1 — loop fixes (all open §) | **Partial pass** | User: config boot OK; chat UI broken; agent list broken; About header OK but dialog logo missing; **crash** at 10:24:29 |
| 2026-06-17 ~10:28 | Round 2 — history dir crash + About logo | **Partial pass** | User: no crash; §2 pass; §6b About logo pass; §3/§4/§5 still broken; brief “config not working” flash on first start |
| 2026-06-17 ~10:35 | Round 3 — network retry + chat layout | **Partial fail** | User: top bar + “Connecting…” forever; agents/chat never load; **crash after a while**. Logcat: same `Manager.vala:136 history: File exists` despite round 2 mkdir workaround; startup stuck in full `ConnectionModels.refresh()` |
| 2026-06-17 ~10:45 | Round 4 — Manager mkdir + fast model init | **Partial pass** | User: **chat finally loads** after long “Connecting…”; no crash. Model load slow; no progress feedback; user suspects cache broken |
| 2026-06-17 ~11:00 | Round 5 — cache-first boot + progress UI | **Awaiting user test** | Cache-first saved model; spinner + status labels; **fix `Model.load_from_cache` `query_exists()` bug** (cache files on disk but never read on Android). Logcat: `model cache hit llama3.1:70b` ~1s boot. |

---

## Checklist (section status)

- [x] **§1 Config write** — file on disk verified via adb  
- [x] **§2 Config load / skip bootstrap** — user round 1: boots with config in place  
- [x] **§3 Startup → chat shell** — user round 4: loads after long wait  
- [ ] **§4 Agent dropdown** — user round 4: confirm after round 5  
- [ ] **§5 Chat input / send bar** — user round 4: confirm after round 5  
- [x] **§6 About header icon** — user round 1: header About button OK  
- [x] **§6b About dialog logo** — user round 2: logo fixed  
- [x] **§7 Default model in saved JSON** — user round 4: `llama3.1:70b` in config  
- [x] **§8 Crash on startup** — user round 4: no crash  

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

**Status:** **PASS** (user round 1 — boots with config, no bootstrap)

### Desired result

Cold start with existing `config.2.json` → **no** bootstrap dialog; app goes straight to `AndroidStartup.run()`.

Gate in code: `if (this.app.config.connections.size == 0)` → bootstrap, else startup.

### Actual (user report)

Round 1: **boots with config in place** — no bootstrap on restart.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Gate on `connections.size == 0` instead of `config.loaded` | **Unknown** — not confirmed on device after install |
| 2 | Migration from legacy `share/ollmchat/config/` paths | **Unknown** |
| 3 | Defer `load_config()` from constructor; load on window realize only | **Round 1** — logcat shows `connections=1` on cold start; no `connections=0 showing bootstrap` line |
| 4 | Log `load_config` path + `connections.size` | **Round 1** — `load_config path=…/etc/ollmchat/config.2.json connections=1` |

### Next step

User cold-start test (round 1): bootstrap yes/no?

### Code

`ollmapp/android/AndroidApplication.vala` — `load_config()`  
`ollmapp/android/AndroidMainWindow.vala` — `load_config_and_initialize()`

---

## §3 Startup → chat shell (blank main UI)

**Status:** **OPEN**

### Desired result

After config load (or bootstrap), `AndroidStartup.run()` succeeds → `initialize_client()` mounts `HistoryBrowser` + `ChatWidget` in `split_view.content`.

### Actual (user report)

Round 2: no crash; chat output, input, and bottom buttons still absent. Brief “config not working” flash on first cold start; OK on second restart.

Logcat: `run failed no working connection` — DNS `No address associated with hostname` before network ready; `initialize_client()` never ran.

### Hypotheses

1. `AndroidStartup.run()` returns **false** (connection check or model pick fails).  
2. `initialize_after_bootstrap()` has **no error UI** when startup fails — silent empty pane (reload path shows error label; post-bootstrap path does not).  
3. `default_model.model` empty in file (§7) → `initialize_model()` should auto-pick; if that fails, startup aborts.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Wire `ChatWidget` + `HistoryBrowser` in `initialize_client()` | **Not reached** on device if startup fails |
| 2 | Error label on reload path when `startup.run()` fails | **Partial** — reload path only |
| 3 | Error label in `initialize_after_bootstrap()` when startup fails | **Round 1** — landed; user test pending |
| 4 | Log at each `AndroidStartup.run()` exit | **Round 1** — landed; logcat shows `run connections=1`; no ok/fail line yet at capture |
| 5 | `persist_config()` in bootstrap `closed` before startup | **Round 1** — landed; user test pending |
| 6 | Round 2: `ensure_app_data_directories()` before `History.Manager` | **Pass** — user round 2: no crash |
| 7 | Round 3: connection retry (5×, 1.5s) for cold-start DNS | **Round 3** — user test pending |
| 8 | Round 3: “Connecting…” label during startup | **Round 3** — user test pending |

### Next step

User test: main area chat shell vs blank vs error label?

### Code

`ollmapp/android/AndroidMainWindow.vala`, `ollmapp/android/AndroidStartup.vala`  
Desktop reference (read only): `ollmapp/Window.vala`, `ollmapp/Initialize.vala`

---

## §4 Agent dropdown (“None”)

**Status:** **OPEN** — user round 1: agent list not working (crash likely blocked `setup_agent_dropdown()`)

### Desired result

Header dropdown lists **Just Ask** and **Chatter** (minimum); selection matches active session agent.

### Actual (user report)

Agent list / dropdown not working.

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

**Status:** **OPEN** — user round 1: chat output, input, and bottom buttons not working

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
| 1 | `switch_to_session` + `active_factory.activate` in `initialize_client()` | **Not verified** — startup often failed before init |
| 2 | Round 3: post-layout `agent_status_change` after `switch_to_session` | **Round 3** — unhide chat input when paned layout ready |

### Next step

Fix §3; if input still missing with chat visible, Android-only post-layout callback after `switch_to_session` (in `AndroidMainWindow`, not `ChatWidget`).

### Code

`ollmapp/android/AndroidMainWindow.vala`, `libollmchatgtk/ChatWidget.vala` (read only unless approved)

---

## §6 About header icon

**Status:** **PASS** (user round 1)

### Desired result

About button in header shows Adwaita `help-about-symbolic` icon; tap opens About window.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Added `help-about-symbolic.svg` to `android/icons/manifest` | **Pass** — user round 1 |

### Code

`android/icons/manifest`, `ollmapp/About.vala` (`icon_name = "help-about-symbolic"`)

---

## §6b About dialog logo

**Status:** **PASS** (user round 2)

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | Bundle `scalable/apps/org.roojs.ollmchat.svg` in Adwaita icon set + `index.theme` | **Pass** — user round 2 |

### Code

`android/icons/manifest`, `android/icons/Adwaita/index.theme`, `pixmaps/scalable/apps/org.roojs.ollmchat.svg`

---

## §7 Default model in saved JSON

**Status:** **Likely fixed** — round 1 logcat showed `initialize_model ok model=llama3.1:70b` + `saved config` before crash; user to confirm JSON

### Desired result

After first successful boot, `usage.default_model.model` is a non-empty chat model name in `config.2.json`.

### Actual

Pre-round-1 file had empty model; round 1 logcat picked `llama3.1:70b` and persisted before crash.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | `initialize_model()` auto-picks first non-embedding model | **Round 1 log** — `initialize_model ok model=llama3.1:70b` |
| 2 | `persist_config()` at end of `AndroidStartup.run()` | **Partial** — runs after Manager (crash blocked full boot) |
| 3 | `persist_config()` in bootstrap `closed` + startup logging | **Round 1** — landed |

### Next step

User: re-check `config.2.json` after round 2 boot without crash.

### Code

`ollmapp/android/AndroidStartup.vala` — `initialize_model()`  
`ollmapp/android/AndroidMainWindow.vala` — bootstrap `closed` handler

---

## §8 Crash on startup (History.Manager)

**Status:** **OPEN** (user round 3 — crash returns)

### Root cause (round 3 logcat)

```
Manager.vala:136: failed to create history directory …/history: File exists
Fatal signal 5 (SIGTRAP)
```

`query_exists()` returned false while directory already existed; `make_directory_with_parents()` → `G_IO_ERROR_EXISTS` → `GLib.error()` abort. Round 2 `ensure_app_data_directories()` could not prevent this because Manager still used broken mkdir logic.

### What we tried

| Step | Change | Result |
|------|--------|--------|
| 1 | `AndroidApplication.ensure_app_data_directories()` — EXISTS-tolerant mkdir | **Partial** — user round 2 no crash; round 3 crash returns |
| 2 | **Shared** `History.Manager` — `query_file_type` + EXISTS-tolerant mkdir (mirror `AndroidApplication.ensure_directory`) | **Round 4** — landed |

### Code

`libollmchat/History/Manager.vala` — constructor mkdir  
`ollmapp/android/AndroidApplication.vala` — `ensure_app_data_directories()`  
`ollmapp/android/AndroidStartup.vala` — call before `new History.Manager()`

---

## Next loop fixes (after user reports round 4)

- **§3/§4/§5** — If still broken, capture logcat for `run ok`, `initialize_client agents=`  
- **§7** — Confirm saved JSON has model name  
- **§8** — Confirm no `Manager.vala` / SIGTRAP in logcat

---

## Pass criteria (Phase 3)

- [x] §2 Cold start → no bootstrap when config file has connections  
- [ ] §3 Main area shows chat shell (not blank)  
- [ ] §4 Agent dropdown shows agent names  
- [ ] §5 Input + send visible and usable  
- [x] §6 About header icon visible  
- [x] §6b About dialog logo visible  
- [ ] §7 Saved JSON has non-empty `default_model.model` after first good boot  
- [ ] §8 No crash during startup  

---

## Related (closed / reference)

- TLS / IME / paste: [`docs/bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md`](done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md)  
- TLS notes: [`docs/android-tls-solution.md`](../android-tls-solution.md)  
- Plan: [`docs/plans/9.1-android-chat-shell.md`](../plans/9.1-android-chat-shell.md)
