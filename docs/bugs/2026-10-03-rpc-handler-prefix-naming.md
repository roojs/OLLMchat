# RPC handler prefix naming

**Status:** ✔️ renamed — non-RPC handlers drop `RPC-`; `RPC-Daemon` and `RPC-Live-*` stay

- ℹ️ Found while writing [`RPC-8.2.8.10`](../plans/RPC-8.2.8.10-URGENT-android-remote-bash.md). `Sandbox.Bubble` needed a prefix and there was no correct name to copy.

## Problem

- 🔷 `RPC-` is reserved for RPC plumbing classes. Example: `RPC-Daemon`.
- 🔷 It is not a marker for every class that exports a method.
- 🔷 A sub-namespace is hyphenated in the handler name.
  - `OLLMfilesd.Sandbox.Bubble` → `Sandbox-Bubble`
  - not `RPC-Sandbox-Bubble`
  - not `RPC-Bubble`
- ℹ️ Every handler in the tree is prefixed `RPC-`. No other prefix exists to copy.
- ℹ️ The written rule says the opposite of the reservation above.
- ℹ️ No runtime failure. The wrong name was copied three times while writing `RPC-8.2.8.10`.

### Reproduction

- ℹ️ `rg 'Request\.register(_live)?\("' --type vala` — every hit starts `"RPC-`.
- ℹ️ `rg 'Request\.add_class' -A2 --type vala` — same.

## Evidence

### Handler prefixes

| Prefix | Class | Where | Proposed |
| --- | --- | --- | --- |
| `RPC-Live-Remote` | `OLLMrpc.Live.Remote` | `libocrpc` | `RPC-Live-Remote` |
| `RPC-Live-Subscribe` | `OLLMrpc.Live.Subscribe` | `libocrpc` | `RPC-Live-Subscribe` |
| `RPC-Live-Callback` | `OLLMrpc.Live.Callback` | `libocrpc` | `RPC-Live-Callback` |
| `RPC-Daemon` | `OLLMfilesd.Daemon` | `ollmfilesd` | `RPC-Daemon` |
| `RPC-ClientCert` | `OLLMfilesd.ClientCert` | `ollmfilesd` | `ClientCert` |
| `RPC-ProjectManager` | `OLLMfilesd.ProjectManager` | `ollmfilesd` | `ProjectManager` |
| `RPC-File` | `OLLMfilesd.File` | `ollmfilesd` | `File` |
| `RPC-Folder` | `OLLMfilesd.Folder` | `ollmfilesd` | `Folder` |
| `RPC-FileHistory` | `OLLMfilesd.FileHistory` | `ollmfilesd` | `FileHistory` |
| `RPC-Codebase` | `OLLMfilesd.Codebase` | `ollmfilesd` | `Codebase` |

- ℹ️ `libocrpc` boots in `libocrpc/namespace.vala` and `libocrpc/android/namespace.vala`. `RPC-Live-Remote` is `libocrpc/Live/Remote.vala`.
- ℹ️ `ollmfilesd` boots in `ollmfilesd/Application.vala` lines 297–305.
- 🔷 Proposed name for a non-RPC handler is the current prefix with `RPC-` removed.
- ℹ️ Tests under `tests/rpc/` follow the same strip: `Hello`, `Probe`, `Strv`, `Value`, `Alarm`. `RPC-Daemon` stays.
- ✔️ `RPC-Live-*` and `RPC-Daemon` stay. They are the plumbing classes.
- ℹ️ `RPC-Daemon` is `OLLMfilesd.Daemon` (`hello` / `shutdown` only). `OLLMrpc.Daemon` registers the type alias `"Daemon"` at `libocrpc/Daemon.vala:25`.

### Type aliases — `Bin.register`

Separate from handler prefixes. A handler rename does not touch these. `docs/bin-rpc-protocol.md` owns this list. `docs/rpc-registration.md` owns handlers.

| Alias | Form |
| --- | --- |
| `Daemon` `Request` `Response` `Notification` `Invoke` | bare class name |
| `Folder` `FileAlias` `FileWithHistory` `VectorMetadata` `ClientCert` | bare class name |
| `Model` `ModelArray` `ModelConfig` `ModelCardData` `ModelGguf` | bare class name |
| `Gio-Menu` `Gio-File` `Test-Actor` | hyphenated namespace (`tests/rpc/gi-test.vala`) |

### Notification method names

Third namespace. Dotted lowercase. No prefix.

| Method |
| --- |
| `Banner.show` |
| `client.run_tool.output` |
| `client.run_tool.end` |
| `event.project.invalidate_cache` |
| `event.filesystem.scan_start` |

- 💩 Confirm the reservation does not cover these before anyone renames them.

## Root cause

- ✔️ [`RPC-8.2 §48`](../plans/RPC-8.2-full-rpc-system.md) wrote the wrong rule, then it was copied.
  - Written rule: handler names use an `RPC-` prefix; nested namespaces use hyphens (`RPC-Live-Remote.ref`).
  - That takes the three `libocrpc` `Live` classes and applies them to every handler.
  - That is how `RPC-File`, `RPC-Folder`, and `RPC-Codebase` were named.
- ✔️ `docs/rpc-registration.md` uses `RPC-Folder` as the worked example and states no rule.
- ✔️ Nothing checks the prefix.
  - `Request.add_class` stores the string as given.
  - `Ffi` builds the C symbol from GType plus method suffix, not from the prefix (`docs/rpc-registration.md` §`add_class`).
  - A wrong prefix has no runtime cost.

## Blast radius

- ℹ️ The prefix is a wire string. Both ends must match. A rename is a protocol break.
- ℹ️ `rg '"RPC-[A-Za-z-]+\.' --type vala` — about 150 call sites in about 50 files.
- 🚫 Do not rename `RPC-Live-*`. `gnome-shell-rpc` calls `RPC-Live-Callback.reply`. See [`2026-09-10`](done/2026-09-10-FIXED-call-sync-nested-io-watch-reentrancy-hang.md). Those names are also correct.

| Callers | Files |
| --- | --- |
| `libocfiles/` | `File.vala`, `Folder.vala`, `ProjectManager.vala`, `FileHistory.vala`, `ReviewFiles.vala` |
| `ollmapp/SettingsDialog/` | settings dialog |
| `liboctools/ReadFile/` | read-file |
| `liboccoder/` | `SourceView.vala` |
| `examples/` | examples |
| `libocrpc/Http/` | `Route.vala` — `Http.add(prefix, …)` maps the same prefix onto HTTP routes |

Test fixtures carry the strings as literal JSON (13 files):

- ℹ️ `tests/rpc/t0.script`, `tests/rpc/t1*.script.in`, `tests/rpc/t2*.script.in`, `tests/test-rpc.sh`, `tests/test-rpc-t2.sh`.

- 💩 ⏳ Not checked: Android assets, saved config, or an on-disk cache that stores a handler prefix. The audit covered source and test fixtures only.

## Open

- 🔷 Non-RPC handlers drop `RPC-`. `RPC-Live-*` and `RPC-Daemon` stay. `Sandbox.Bubble` → `Sandbox-Bubble`.
- ℹ️ `Folder` then matches the `Bin.register` alias `Folder`. The tables are separate in code. The wire strings would be the same.
- ✔️ The six shipped `ollmfilesd` prefixes are renamed. Both ends in this tree use the new wire strings.
- 💩 ⏳ After the rule is stated, correct `RPC-8.2 §48` and `docs/rpc-registration.md`. Worth doing even if the six names stay.
- 💩 ⏳ Reject a bad prefix inside `Request.add_class`. That is new API behaviour. Not without approval.

## Attempts / changelog

- 2026-10-03 — ✔️ Audit only. No code changed. Listed every `Request.register`, `register_live`, `add_class`, and `Bin.register`. Split handler prefix, type alias, and notification method. Sized the rename. Traced the wrong rule to `RPC-8.2 §48`.
- 2026-10-03 — ℹ️ `RPC-8.2.8.10` Phase 1 proposes `RPC-Sandbox-Bubble`. That becomes `Sandbox-Bubble`.
- 2026-10-03 — 🔷 Proposed column: strip `RPC-` on the six data / manager handlers. Plumbing prefixes stay.

## Next

- ✔️ Docs that state the rule now match the rename. `RPC-8.2.8.10` uses `Sandbox-Bubble`.
