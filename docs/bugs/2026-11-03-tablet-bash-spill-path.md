# Tablet bash tells the model to read a file bash cannot open

**Status:** ⏳ root cause confirmed; fix direction corrected — replacement proposal pending

Agent Pi on the tablet ran a long string of `bash` calls. Every one exited 0. When the output was longer than 50 lines, the tool returned the tail and told the model to `grep`, `head`, or `tail` a log file. That log is on the tablet. Bash runs on the desktop, so the follow-up cannot work. The model then treated the tail as the file.

## Problem

- 🔷 A long command still returns the last 50 lines. That cap stays.
- 🔷 The follow-up path in the tool result must be a path the next `bash` call can open.
- 🔷 The full-output spill file and its path stay in the result.
- 🔷 The spill file must live on the server, where the command runs. The app
  must fetch server file content through the file daemon, not read a local
  tablet copy.
- 🔷 On the tablet the result names `/storage/emulated/0/Android/data/.../run_command-N.log` and says to open it with this tool.
- 🔷 `head`, `sed -n '1,Np'`, and `cat` whose stdout exceeds 50 lines come back as the tail. The model read that tail as the start of the file.

## Evidence

- ℹ️ Tablet emulator `emulator-5556`, package `org.roojs.ollmchat.androidpoc`, pid 20434. Session `history/2026/11/03/01-44-12` (09:44–09:50). Agent Pi, `ornith-1.5:35b`, project `/home/alan/gitlive/OLLMchat`.
- ℹ️ User text: merge `FileConnectionAdd` into `examples/oc-test-source-diff.vala`.
- ✔️ Spill logs still on the device, mode `600`, under that session directory: `run_command-3.log`, `4`, `5`, `6`, `15`, `20`.
- ✔️ Commands and what the model was given. All of these ended `Exit code: 0`.
  - `cat` `examples/oc-test-source-diff.vala` — last 50 of 1242 lines (the end of the file).
  - `wc -l` then `head -60` on that file — last 50 of 62 lines. The line count and the start of `head` were dropped. The text opened in the license.
  - `cat -A … | head -5` then a full `cat` of `FileConnectionAdd.vala` — last 50 of 257 lines. The `head -5` never appeared.
  - `cat` of that file — last 50 of 251 lines.
  - `sed -n '1,120p'` of that file — last 50 of 120 lines, so lines 71–120.
  - `head -25` of that file — full output. It stayed under the cap.
- ✔️ The model's own notes after those tails: the file was a fragment, it started partway through, and `can_close` was used without being declared. The declaration is above the window it was shown.
- ✔️ It then called `read` on the same paths. `read` returned the file, including the top.
- ℹ️ A 20th `bash` (a diff, result 2042 characters, spill kept) finished at 09:50:03. The next completion started. At 09:50:04 the session logged `Stopping running` (`cancel_current_request`). That diff is not in the session json. The save at 09:50:03 flushed the previous turn. That stop is separate from the spill path.
- ℹ️ Desktop spill paths are on the host. The sandbox is started with `--ro-bind / /` (`libocbwrap/Bubble.vala`), so a desktop `bash` can open `~/.local/share/ollmchat/history/.../run_command-N.log`. The same sentence is true there.

## Root cause

- ✔️ `ollmapp/android/tools/Bash/Request.vala` `bash_finished_text` appends the footer when `output_lines > 50`. The path is `this.spill_path`, built from `session.task_dir()` on the tablet.
- ✔️ The command itself runs on the desktop daemon (`Sandbox-Bubble.rpc_create` / `rpc_run` / `wait`). `ollmfilesd/Sandbox/Bubble.vala` `wait_run` replies with `string.joinv` of `tail` (the rolling last 50 lines) plus `Exit code:`. The daemon does not keep the earlier lines (`libocbwrap/Bubble.vala` `read_from_channel` drops past 50).
- ✔️ The only full copy is the spill file the tablet writes while `output` notifications arrive. The footer tells the model to open that copy with `bash`.
- ✔️ The existing thin-client file path already fetches content from the
  daemon: `libocfiles/File.vala` `read()` calls `File.read`, and
  `ollmfilesd/File.vala` reads the path on the server.
- 🚫 Raising the 50-line cap. The cap is the finished design in `docs/plans/done/TOOLS-2.6.5-DONE-run-command-timeout-live-spill.md` and `docs/plans/done/TOOLS-2.31.3-DONE-bash-tool.md`.
- 🚫 Applying an Android-only result-formatting fix. Server-owned spill
  output is shared infrastructure, so both Bash clients must use the daemon
  contract consistently.
- 🚫 Removing the spill path or replacing recovery with first-and-last output.
- 🚫 Making the app dereference the spill path with `GLib.File`; on a thin
  client that resolves against the tablet filesystem.

## Proposed fix

- 🔷 Move spill ownership to the server-side command execution path. The
  daemon must write every output line to a server spill file while retaining
  the rolling 50-line tail.
- 🔷 Return the server absolute spill path with the finished command result.
  Keep the existing `Full output:` footer and grep/head/tail guidance.
- 🔷 The app must treat that path as a daemon path. `read` fetches it through
  the existing `File.exists` / `File.read` RPC path; a follow-up `bash` also
  runs on the daemon and can open it directly.
- 💩 Remove the duplicate local spill stream from both Bash request clients
  after the daemon owns the complete copy. Keep client-side live-output
  notifications and line counting only where still needed by the UI/result
  formatting.
- ⏳ Write the replacement verbatim Vala proposal after fixing the daemon
  spill path, lifetime, and RPC response contract. The superseded
  first-50/last-50 proposal must not be applied.

## Attempts / changelog

- ✔️ 2026-11-03 — read the tablet session json and logcat for pid 20434. No product change.
- 🔷 2026-11-03 — corrected direction: retain the spill path, store the file
  on the server, and fetch it through the file daemon rather than tablet disk.

## Next

- ⏳ Specify the server spill location and lifecycle, then add exact
  Remove/Replace/Add fences for the daemon and Bash clients.
- ⏳ After implementation, rebuild the daemon and tablet app and repeat a
  long `cat`. The footer must name a server path, and `head`/`sed` through
  `bash` plus `read` must both retrieve that server file.
