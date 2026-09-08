# Gi.scalar UTF8 OUT: non-UTF8 / garbage string reaches GJS

**Status:** ✅ fixed — `Gi.scalar` UTF8/FILENAME maps null `v_string` to `""`  
**Hit:** 2026-09-08  
**Package / area:** `libocrpc` — `Gi.vala` `scalar` (`GI.TypeTag.UTF8` / `FILENAME` **return** / OUT)  
**Consumer:** gnome-shell-rpc T-030 soft gap — `St-Icon.get_icon_name` → GJS  
`TypeError: malformed UTF-8 character sequence at offset 0` (also offset 2)  
**Related (IN side, fixed):** `docs/bugs/done/2026-09-08-FIXED-gi-convert-utf8-dangling-before-invoke.md`

---

## Problem

🔷 **Expected:** Gi typelib invoke of `st_icon_get_icon_name` (transfer none) returns a valid UTF-8 string (or empty / null mapped to `""`) that GJS can read.

**Actual:** After a successful RPC `St-Icon.get_icon_name` reply, GJS throws `malformed UTF-8` when the value is used (quick-settings `bind_property('icon-name', … SYNC_CREATE)` right after the get).

Affects **UTF8/FILENAME returns** on the Gi path, not only St.Icon — any string getter that goes through `Gi.scalar` → wire → client.

Live evidence (gnome-shell-rpc nested):

```
method=St-Icon.get_icon_name
JS ERROR: TypeError: malformed UTF-8 character sequence at offset 0
_init@…/quickSettings.js:83:20   # bind_property('icon-name', …)
```

Log: `~/.cache/gnome-shell-rpc/org.gnome.ShellRpc.debug.log` (2026-09-08 ~18:55).  
Earlier: `/tmp/mutter-rpc-l7-stock.log` (~09:49, same stack).

---

## Root cause

✔️ Same as `done/2026-09-05-FIXED-gimock-utf8-empty-set-string-null.md`:

- C getters often return `NULL` (unset `icon-name`, empty label, …).
- `Gi.scalar` does `s.set_string(arg.v_string)` → `set_string(null)`.
- A STRING-typed `GValue` with NULL content is not a usable empty string; GJS throws `malformed UTF-8`.

ℹ️ `StreamValue.write` already coalesces null → `""` on the BIN write path; GiMock still broke GJS until `set_string("")`. Live scalar must do the same at pack time.

🚫 Not the IN dangling-pin bug (already fixed). 🚫 Not a consumer Helper / local `icon-name` paper.

---

## Fix (libocrpc only)

🔷 In `Gi.scalar` UTF8/FILENAME: map null `arg.v_string` to `""` — same as GiMock `mock_empty`.

### `libocrpc/Gi.vala` — `scalar` UTF8/FILENAME

#### Remove

```vala
				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					var s = GLib.Value(typeof(string));
					s.set_string(arg.v_string);
					dest.add(s);
					return true;
```

#### Replace with

```vala
				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					var s = GLib.Value(typeof(string));
					s.set_string(arg.v_string != null ? arg.v_string : "");
					dest.add(s);
					return true;
```

🚫 Consumer Helper bypasses or client-local `icon-name` in gnome-shell-rpc.

---

## Attempts / changelog

- ✔️ `libocrpc/Gi.vala` `scalar` UTF8/FILENAME: `set_string(arg.v_string != null ? arg.v_string : "")` (GiMock pattern).

---

## Related

- ℹ️ IN UTF8 pin (fixed): `done/2026-09-08-FIXED-gi-convert-utf8-dangling-before-invoke.md`
- ℹ️ GiMock null string (fixed): `done/2026-09-05-FIXED-gimock-utf8-empty-set-string-null.md`
- ℹ️ Consumer scoreboard: `gnome-shell-rpc/docs/plans/0.7.7-thin-shell-bootstrap.md` (soft gap: quick-settings UTF-8)
- ℹ️ Desktop icons (`ding`) failing `theme is null` is a **separate** ThemeContext bug in gnome-shell-rpc — not this ticket
