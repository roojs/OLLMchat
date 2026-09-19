# Config2 save drops `filesd` (File Server expander / systemd / HTTPS)

**Status:** OPEN  
**Hit:** 2026-09-19 — desktop File Server expander: systemd on + telnet to listen port  
**Component:** `libollmchat/Settings/Config2.vala` `serialize_property`  
**Related:** [`RPC-8.2.8.3-filesd-file-server-tls.md`](../plans/RPC-8.2.8.3-filesd-file-server-tls.md)

---

## Problem

🔷 Closing Connections after File Server edits bounces `ollmfilesd`, but **systemd does not enable** and **HTTPS does not listen**. Telnet to the chosen port gets nothing.

**Expected:** `config.2.json` contains `filesd` (`https`, `proxy`, `systemd`). New daemon `install()`s the user unit when systemd is on, and `Https.listen` when `https` is non-empty.

**Actual:** save writes JSON **without** a `filesd` key. Daemon loads defaults (`https = ""`, `systemd = false`).

---

## Evidence (2026-09-19 ~21:14)

- `~/.config/ollmchat/config.2.json` mtime 21:14:10 — top-level keys: `agents`, `connections`, `model-options`, `tools`, `usage`, `windows`. **No `filesd`.**
- `systemctl --user status ollmfilesd.service` → unit **not-found**. No `~/.config/systemd/user/ollmfilesd.service`.
- `ollmfilesd --debug` running; Unix socket only. **No TCP listen**, **no `~/.local/share/ollmchat/tls/`.**
- `~/.cache/ollmchat/ollmfilesd.stderr.log` after bounce:

```
listening on /home/alan/.local/share/ollmchat/ollmfilesd.sock
Failed to disable unit: Unit ollmfilesd.service does not exist
```

That line is `Filesd.install()` `disable --now` when `systemd` is false.

---

## Root cause

`Config2.serialize_property` handles maps (`connections`, `windows`, …) then:

```vala
default:
    // Return null for any unhandled properties to avoid Gee collection warnings
    return null;
```

`filesd` and `filesd-client` fall through to **null**, so `Json.gobject_serialize` omits them. Deserialize already uses `default_deserialize_property` (load would work if the keys were in the file).

Same hole as `filesd_client` persistence.

---

## Proposed fix

In `serialize_property`, same pattern as other nested GObjects:

```vala
				case "filesd":
					return Json.gobject_serialize(this.filesd);

				case "filesd-client":
					return Json.gobject_serialize(this.filesd_client);
```

Then rebuild, close Connections again, confirm `filesd` in JSON, unit enabled, port listening.
