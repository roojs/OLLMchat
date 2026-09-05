# GiMock: pointer object returns skip mint; ctors crash on `val("o", null)`

**Status:** ✔️ FIXED — apply verified in tree; await consumer ✅

**Started:** 2026-09-05

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `GiMock.vala` (`mint_object_lease`, `mock_new`, `mock_empty_interface`)

**Related:**

- ℹ️ Design: [`docs/plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md`](../plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md)
- ℹ️ Prior: [`done/2026-09-03-FIXED-gimock-untyped-object-returns.md`](done/2026-09-03-FIXED-gimock-untyped-object-returns.md)
- ℹ️ Prior follow-up note: [`done/2026-09-03-FIXED-gimock-fake-gtype-register-static-simple-glib-284.md`](done/2026-09-03-FIXED-gimock-fake-gtype-register-static-simple-glib-284.md) (pointer object returns still open)
- ℹ️ Consumer: gnome-shell-rpc `gi-rpc-mock` / `Clutter-Actor.new` (workaround in `HelperMock`)

---

## Problem

🔷 **Symptom:** `Clutter-Actor.new` via GiMock segfaults (or method object returns stay unset) because `mint_object_lease` never mints.

🔷 **Design:** For OBJECT / INTERFACE returns whose GType is in our registered library set (`Bin.gtype_to_alias` from `Gi.register`), GiMock should mint a leased fake of that alias — **whether or not** GIR marks the type as a pointer. Returning null is a **MockDispatch override** job when a consumer deliberately wants null.

**Actual:** `mint_object_lease` did:

```vala
if (type.is_pointer()) {
    return true;  // token stays null — no mint
}
```

GIR OBJECT / INTERFACE returns are almost always pointers (`ClutterActor*`, `MetaContext*`, …), so GiMock never reached the OBJECT/INTERFACE + `gtype_to_alias` path.

Then `mock_new` always packed `OLLMrpc.val("o", token)` → `val("o", null)` → **segfault**.

---

## Root cause

✔️ `is_pointer()` is the wrong gate. Pointer ≠ “not an object”:

| Return shape | Correct GiMock default |
| --- | --- |
| OBJECT / INTERFACE in `Bin.gtype_to_alias` | **mint** lease for that alias |
| OBJECT / INTERFACE **not** in library set | `reply_error` |
| Not OBJECT or INTERFACE (struct, opaque, …) | leave `token` null |
| Deliberate null | consumer `MockDispatch` override |

✔️ Crash: `mock_new` packed `val("o", token)` even when mint skipped.

---

## Fix (applied)

✔️ `mint_object_lease`: gate on `TypeTag.INTERFACE` + OBJECT/INTERFACE kind; mint when GType is registered; non-object kinds leave `token` null (no error).

✔️ `mock_new`: `reply_error` if `token == null`; never `val("o", null)`.

`mock_empty_interface` unchanged (already packs only when `token != null`).

---

## Consumer workaround (temporary)

gnome-shell-rpc `HelperMock`: hand-mint `Clutter-Actor.new` via `GiMock.mint("Clutter-Actor")`. Drop when consumer verifies against rebuilt `libocrpc`.

---

## Attempts / changelog

- ✔️ 2026-09-05 — Hit from gnome-shell-rpc LayoutManager boot (`Clutter-Actor.new` via GiMock).
- ✔️ 2026-09-05 — Root cause: `is_pointer()` skip + `val("o", null)` in `mock_new`.
- ✔️ 2026-09-05 — Refined: mint only OBJECT/INTERFACE in library set; keep skip for non-object pointers (user review).
- ✔️ 2026-09-05 — Applied approved hunks in `libocrpc/GiMock.vala`.

## Next

- ⏳ Rebuild consumer against fixed `libocrpc.so`; drop `HelperMock` `Clutter-Actor.new` arm; verify `gi-rpc-smoke`.
- ⏳ User ✅ → rename/move to `docs/bugs/done/2026-09-05-FIXED-gimock-pointer-return-skips-mint.md`.
