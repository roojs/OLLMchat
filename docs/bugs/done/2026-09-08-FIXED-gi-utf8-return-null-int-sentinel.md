# Gi UTF8 return still malformed after null coalesce / int-null

**Status:** ✅ closed for OPC — null sentinel done; non-null dangle is consumer stub  
**Hit:** 2026-09-08  
**Package / area:** `libocrpc` — `Gi.scalar` UTF8/FILENAME return  

---

## Outcome

✔️ **Null:** C `NULL` → int `0` on `retval` (`Gi.scalar`). Consumer unpacks. Unset Icon OK.  
✔️ **OPC non-null smoke:** `tests/rpc/gi-test.vala` `Gio-File.get_basename` → STRING `"missing"` passes.  
✔️ **Non-null live St-Icon:** Server/`IconDiag` valid UTF-8; **consumer** generated getter returns unowned `get_string()` then unrefs `Response` → dangling → GJS malformed UTF-8. Fix = stub copy before `Response` dies (`gnome-shell-rpc/docs/bugs/2026-09-08-st-icon-get-icon-name-utf8-nonnull.md`).

🚫 Not an OPC Gi.scalar invent-garbage bug for non-null names.

---

## Related (done)

- IN pin: `done/2026-09-08-FIXED-gi-convert-utf8-dangling-before-invoke.md`
- Early null→`""` ticket: `done/2026-09-08-FIXED-gi-scalar-utf8-return-malformed.md` (superseded by int `0`)
