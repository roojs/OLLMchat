# Tablet bash tells the model to read a file bash cannot open

**Status:** ⏳ root cause confirmed; fix proposed — not applied

Agent Pi on the tablet ran a long string of `bash` calls. Every one exited 0. When the output was longer than 50 lines, the tool returned the tail and told the model to `grep`, `head`, or `tail` a log file. That log is on the tablet. Bash runs on the desktop, so the follow-up cannot work. The model then treated the tail as the file.

## Problem

- 🔷 A long command still returns the last 50 lines. That cap stays.
- 🔷 The follow-up path in the tool result must be a path the next `bash` call can open.
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
- 🚫 Raising the 50-line cap. The cap is the finished design in `docs/plans/done/TOOLS-2.6.5-DONE-run-command-timeout-live-spill.md` and `docs/plans/done/TOOLS-2.31.3-DONE-bash-tool.md`.
- 🚫 Editing `liboctools/Bash/Request.vala` the same way. On the desktop the spill path is on the machine where bash runs.

## Proposed fix

- 💩 `ollmapp/android/tools/Bash/Request.vala` `bash_finished_text`. The tablet already has every line in the spill file. Put the first 50 of those lines in front of the daemon tail. The footer must not name `spill_path`.

**Why:** The model is told to recover the missing lines by reading a path bash cannot open. The process that wrote the file can quote the start of it. `head -60`, `sed -n '1,120p'`, and `cat` then show the start of that command's output as well as the end.

**Where:** `bash_finished_text`.

**Depends on:** none.

#### Remove

```vala
		/**
		 * Command result, plus the spill footer when more than 50 lines arrived.
		 *
		 * @param msg last lines, or ''command has ended''
		 * @return text the agent reads
		 */
		private string bash_finished_text(string msg)
		{
			if (this.output_lines <= 50) {
				return msg;
			}
			return msg + @"

**Below are the last 50 of $(this.output_lines) lines.**
Full output: $(this.spill_path)
Do not read this file whole — it is $(this.output_lines) lines. Use grep, head, or tail on it with this tool to find the part you need.
";
		}
```

#### Replace with

Flush the spill stream, then read the first 50 lines from the tablet file. Those lines go in front of `msg`. The footer does not include the path.

```vala
		/**
		 * Command result. Over 50 lines, the first 50 from the local
		 * spill file, then the daemon tail. The footer does not name
		 * that file: bash runs on the desktop and cannot open it.
		 *
		 * @param msg last lines, or ''command has ended''
		 * @return text the agent reads
		 */
		private string bash_finished_text(string msg)
		{
			if (this.output_lines <= 50) {
				return msg;
			}
			if (this.spill_active) {
				try {
					this.spill_stream.flush(null);
				} catch (GLib.Error e) {
				}
			}
			string[] head_lines = {};
			try {
				var dis = new GLib.DataInputStream(
					GLib.File.new_for_path(this.spill_path).read());
				while (head_lines.length < 50) {
					var line = dis.read_line(null);
					if (line == null) {
						break;
					}
					head_lines += line;
				}
			} catch (GLib.Error e) {
				head_lines = {};
			}
			var head = string.joinv("\n", head_lines);
			if (head != "") {
				head = head + "\n\n";
			}
			return head + msg + @"

**First 50 lines, then the last 50 of $(this.output_lines) lines.**
The rest is not in this result. Bash runs on the desktop and cannot open the copy kept on this device.
For a source file, use read with start_line and end_line.
For more of this command, run one whose output stays within 50 lines.
";
		}
```

## Attempts / changelog

- ✔️ 2026-11-03 — read the tablet session json and logcat for pid 20434. No product change.

## Next

- ⏳ Apply the `bash_finished_text` replacement above, then rebuild the tablet app and repeat a `cat` of `examples/oc-test-source-diff.vala`. The tool result should start at the top of the file and must not mention `/storage/emulated/0`.
