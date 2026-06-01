# run_command: seccomp fs appendix lists bubblewrap namespace proc opens

**Status:** FIXED (2026-05-14)

**Started:** 2026-05-14

**Process:** Follow **`docs/bug-fix-process.md`**. Diagnosis below is from code inspection and syscall behavior, not from a new repro log.

**Related plan (fix):**

- **`../plans/2.22.1.5-seccomp-fs-appendix-bwrap-namespace-setup.md`**

---

## Problem

After a **`run_command`** run under bubblewrap, the tool output can append a **sandbox fs** block that lists paths such as **`uid_map`**, **`gid_map`**, and **`setgroups`** (often as bare names, not full `/proc/...` paths).

**Intent of the appendix:** coach the model that it may need **`allow_write`** (or other parameters) if the **command it asked to run** hit paths outside the sandbox write policy.

**What goes wrong:** those entries are typically **bubblewrap setting up user namespaces** (write-style **`openat`** on the kernel’s proc interfaces), **not** the wrapped shell or binary (e.g. `date`) asking for extra host write roots. The model gets **misleading permission hints**.

**Expected:** the fs appendix should reflect **wrapped workload** activity relevant to **`allow_write`**, and should **omit** (or clearly separate) **bubblewrap’s own** namespace-setup opens.

**Actual:** NOTIFY records any qualifying **`openat`** from any process in the subtree that inherits the filter, including the outer **`bwrap`** process; pathname decoding often yields **relative final components** only (see plan).

---

## Reproduction

1. Use **`run_command`** with bubblewrap available (**`Bubble.can_wrap()`** true).
2. Run a trivial command that does not write outside the sandbox, e.g. **`date`**.
3. Inspect combined tool output: if seccomp user-notify is active, the fs appendix may list **`uid_map`**, **`gid_map`**, **`setgroups`**.

**Environment:** Linux with **`bwrap`** on **`PATH`**; NOTIFY setup succeeding (no “Seccomp user-notify was not set up” skip message).

---

## Root cause (code-backed)

- **`liboctools/RunCommand/RunSeccomp.vala`** installs NOTIFY on **`openat`** for the process that **`exec`s into `bwrap`**, and the filter is inherited by **`bwrap` and descendants**.
- **`bwrap`** legitimately performs write-mode **`openat`** on **`/proc/.../uid_map`**, **`gid_map`**, **`setgroups`** during namespace setup.
- The notifier reads the **pathname argument** from the tracee; with **`openat(dirfd, "uid_map", ...)`** the stored string is often **just the basename**, not a full path.
- There is **no attribution** today: **`file_writes`** keys every disallowed write-style open that fails **`bubble.can_write(p)`**, without distinguishing **issuer** (outer `bwrap` vs inner command).

---

## Attempts / changelog

| Date | Change | Purpose | Result |
|------|--------|---------|--------|
| — | — | — | — |

---

## Conclusions

- **Root cause:** seccomp fs evidence treats **all** qualifying **`openat`** events the same; **bubblewrap namespace setup** is included in the same bucket as **wrapped command** file activity.
- **Ruled out:** `date` itself needing those paths for normal operation; the interesting syscalls are from **`bwrap`** (see plan for PID / **`exe`** attribution).
- **Fix:** implemented per **`../plans/2.22.1.5-seccomp-fs-appendix-bwrap-namespace-setup.md`**; archived under **`docs/bugs/done/`**.

---

## After a verified fix (later)

Verified and archived 2026-05-14.
