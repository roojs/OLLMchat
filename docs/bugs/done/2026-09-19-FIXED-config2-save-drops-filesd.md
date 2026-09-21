# Config2 save drops `filesd` (File Server expander / systemd / HTTPS)

**Status:** ✅ FIXED — user archived 2026-09-20  
**Hit:** 2026-09-19 — desktop File Server expander: systemd on + telnet to listen port  
**Component:** `libollmchat/Settings/Config2.vala` `serialize_property`  
**Related:** [`RPC-8.2.8.3`](../../plans/done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md)

---

## Problem

🔷 Closing Connections bounced `ollmfilesd`, but systemd did not enable and HTTPS did not listen. `config.2.json` had no `filesd` key.

---

## Root cause

✔️ `Config2.serialize_property` handled maps then `default: return null`. `filesd` and `filesd-client` were omitted from JSON. Deserialize already used `default_deserialize_property`.

---

## Landed

✔️ Same pattern as other nested GObjects:

```vala
				case "filesd":
					return Json.gobject_serialize(this.filesd);

				case "filesd-client":
					return Json.gobject_serialize(this.filesd_client);
```
