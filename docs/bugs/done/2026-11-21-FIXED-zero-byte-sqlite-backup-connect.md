# Zero-byte SQLite backup files handled outside database connect

**Status:** ✅ Fixed 2026-11-21 — zero-byte backing file discarded in `SQ.Database.load_from_file()` only.

**Pointer:** `docs/bug-fix-process.md`

## Problem

- 🔷 Zero-byte `history.db` / `files.sqlite` should be removed only when `SQ.Database` connects (`load_from_file`), not via copy-pasted checks at each library call site.
- 🚫 New public helpers or application-layer reconcile — rejected.

## Root cause

- ✔️ Connect logic already lived in private `load_from_file()`; callers must rely on `new SQ.Database(path)` only.

## Applied

- `libocsqlite/Database.vala`: constructor docblock (callers do not pre-delete / size-check); `GLib.debug` when discarding zero-byte backing file in `load_from_file()`. No new types or methods.

## Attempts / changelog

- ✔️ 2026-11-21 — Mis-apply: history reconcile + `openable_backing_file` — reverted per user.

## Next

- ⏳ Remove any remaining duplicate zero-byte **SQLite** checks in libs that should only use `new SQ.Database` (if found on audit).