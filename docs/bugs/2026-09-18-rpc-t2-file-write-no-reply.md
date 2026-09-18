# test-rpc-t2 does not pass (`meson test` SIGTRAP)

**Status:** ⏳ gate **FAIL**  
**Gate:** `meson test -C build test-rpc-t2`  
**Hit:** 2026-09-18

---

## Does the test pass?

🔷 **No.** `meson test -C build test-rpc-t2` → **FAIL**, exit 133, **SIGTRAP**. `ollmfilesd` dies while running an `--rpc-script`.

---

## What the original write complaint was

🔷 Id 6 `RPC-File.rpc_write` had no `Response` (stdout 1–5, 7, 99).

That part **does pass** if you run the script **without** Meson’s malloc fill:

```bash
# 19 passed, 0 failed (includes T2A.1 File.write id 6)
bash tests/test-rpc-t2.sh build
```

JSON `0` is boxed as `INT`; FFI `"u"` is `UINT`. `Ffi.pack("u")` now `transform`s before `get_uint()`. Script drain waits until that request’s reply exists. Those two are in the tree.

---

## Why `meson test` still fails

Meson always sets `MALLOC_PERTURB_` (glibc fills freed heap with a pattern). Under that, `ollmfilesd` **SIGTRAPs**. Same `test-rpc-t2.sh`:

- no `MALLOC_PERTURB_` → **19/19 pass**
- `MALLOC_PERTURB_=1` / `112` / `186` / `255` → **SIGTRAP** (exit 133)

Which script dies is not stable: sometimes `t2-scan.script` (first case, during/after `rpc_write`), sometimes later persist/delete after the dirty check. Coredump command line names the script; no usable core (`Storage: none`).

That is **not** “id 6 never replied”. It is the daemon aborting on **used-after-free / uninitialized heap** that Meson’s perturb exposes.

---

## Applied (write path only)

- ✔️ `libocrpc/Ffi.vala` `pack("u")` — transform to `uint` then `get_uint()`. User accepted.
- ✔️ `ollmfilesd/StdioConnection.vala` `drain_script_request` — wait until the matching `Response` is written. 💩 not in the original hunk; needed so id 6’s async write can reply.

---

## Next

- ⏳ 🔷 Diagnose the **SIGTRAP under `MALLOC_PERTURB_`** (which free, which later use). That is why the meson gate is red.
- 🚫 Do not treat “run t2.sh without perturb” as the gate passing.
