/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd.Sandbox
{
	/**
	 * Server ''Sandbox-Bubble.*'' handlers.
	 *
	 * {@link OLLMbwrap.Bubble} owns the spawn, overlay, and job table.
	 * This class is RPC glue: it builds a bubble, leases it so the
	 * caller can subscribe, then looks later calls up by pid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMfilesd.Sandbox.Bubble.rpc_register();
	 * OLLMrpc.Request.register("Sandbox-Bubble",
	 *     new OLLMfilesd.Sandbox.Bubble(project_manager));
	 * //   Sandbox-Bubble.rpc_create -> lease
	 * //   RPC-Live-Subscribe.rpc_signal lease "output"
	 * //   RPC-Live-Subscribe.rpc_signal lease "finished"
	 * //   Sandbox-Bubble.rpc_run lease -> pid
	 * //   Sandbox-Bubble.wait pid 60 session_id
	 * //   Sandbox-Bubble.send pid "yes\n" session_id
	 * //   Sandbox-Bubble.kill pid session_id
	 * }}}
	 */
	public class Bubble : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Sandbox-Bubble", typeof(Bubble),
				"can_wrap", "",
				"rpc_create", "sssbSbx",
				"rpc_run", "t",
				"kill", "ix",
				"tail", "ix",
				"wait", "iix",
				"send", "isx"
			);
		}

		public ProjectManager manager { get; construct; }

		public Bubble(ProjectManager manager)
		{
			GLib.Object(manager: manager);
		}

		/**
		 * ''Sandbox-Bubble.can_wrap'' — whether bubblewrap is usable
		 * on this host.
		 *
		 * Reply ''msg'' is ''1'' when it can run. Otherwise ''windows'',
		 * ''flatpak'', or ''0''.
		 *
		 * @param request inbound RPC
		 */
		public void can_wrap(OLLMrpc.Request request)
		{
			var msg = "1";
			if (!OLLMbwrap.Bubble.can_wrap()) {
				msg = "0";
#if G_OS_WIN32
				msg = "windows";
#else
				if (GLib.Environment.get_variable("FLATPAK_ID") != null) {
					msg = "flatpak";
				}
#endif
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = msg
			});
		}

		/**
		 * ''Sandbox-Bubble.rpc_create'' — lease a sandbox. Does not
		 * start it.
		 *
		 * @param request inbound RPC
		 * @param project_path project root, or empty for no-project
		 * @param command ''sh -c'' shell string
		 * @param working_dir absolute path, or empty
		 * @param network true leaves the network namespace shared
		 * @param allow_write ''no'' / ''project'' / absolute roots
		 * @param keep_stdin true holds a stdin pipe for {@link send}
		 * @param session_id chat that started this command
		 */
		public void rpc_create(
			OLLMrpc.Request request,
			string project_path, string command, string working_dir,
			bool network, string[] allow_write, bool keep_stdin,
			int64 session_id
		) {
			if (command == "") {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"Command cannot be empty"
					)
				});
				return;
			}
			if (!OLLMbwrap.Bubble.can_wrap()) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"sandbox unavailable"
					)
				});
				return;
			}
			var project = this.manager.project_root(project_path);
			if (project_path != "" && project == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "project not found"
				});
				return;
			}
			var bubble = new OLLMbwrap.Bubble(
				new FileVerification(project, this.manager)) {
				project_path = project_path,
				allow_network = network,
				write_tokens = allow_write,
				command = command,
				working_dir = working_dir,
				keep_stdin = keep_stdin,
				session_id = session_id
			};
			if (project != null) {
				bubble.write_roots.set(project.path, project.path);
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("t", request.connection.export(bubble))
			});
		}

		/**
		 * ''Sandbox-Bubble.rpc_run'' — start the leased command.
		 *
		 * Replies with the bwrap pid once spawn has set it.
		 *
		 * @param request inbound RPC
		 * @param handle lease from {@link rpc_create}
		 */
		public void rpc_run(OLLMrpc.Request request, uint64 handle)
		{
			this.run.begin(request, (obj, res) => {
				this.run.end(res);
			});
		}

		/**
		 * Start {@link OLLMbwrap.Bubble.exec} and reply with the pid.
		 *
		 * @param request inbound RPC
		 */
		private async void run(OLLMrpc.Request request)
		{
			var bubble = request.connection.leases.get(
				(int) request.args.get(0).get_uint64()) as OLLMbwrap.Bubble;
			if (bubble == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"unknown sandbox handle"
					)
				});
				return;
			}
			var spill_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(),
				"ollmchat", "bash-spill");
			try {
				GLib.File.new_for_path(spill_dir).make_directory_with_parents(null);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			var spill_file = GLib.Path.build_filename(spill_dir,
				"run_command-" + bubble.session_id.to_string() + "-" +
				GLib.get_real_time().to_string() + ".log");
			try {
				bubble.spill_stream = GLib.File.new_for_path(spill_file).replace(
					null, false, GLib.FileCreateFlags.PRIVATE, null);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			bubble.spill_path = spill_file;
			bubble.spill_open = true;
			bubble.output.connect((line) => {
				if (!bubble.spill_open) {
					return;
				}
				try {
					bubble.spill_stream.write_all((line + "\n").data, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					bubble.spill_open = false;
					try {
						bubble.spill_stream.close(null);
					} catch (GLib.Error close_error) {
						GLib.warning("%s", close_error.message);
					}
					try {
						GLib.File.new_for_path(bubble.spill_path).delete(null);
					} catch (GLib.Error delete_error) {
						GLib.warning("%s", delete_error.message);
					}
					bubble.spill_path = "";
				}
			});
			var ended = "";
			bubble.finished.connect((output) => {
				ended = output;
				if (!bubble.spill_open) {
					return;
				}
				try {
					bubble.spill_stream.close(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					bubble.spill_open = false;
					bubble.spill_path = "";
					return;
				}
				bubble.spill_open = false;
				if (bubble.output_lines > 50) {
					return;
				}
				try {
					GLib.File.new_for_path(bubble.spill_path).delete(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return;
				}
				bubble.spill_path = "";
			});
			bubble.exec.begin(bubble.command, bubble.working_dir, (obj, res) => {
				try {
					bubble.exec.end(res);
				} catch (GLib.Error e) {
					if (ended == "") {
						ended = "ERROR: " + e.message;
					}
				}
			});
			while (bubble.pid == 0 && ended == "") {
				GLib.Timeout.add(50, () => {
					this.run.callback();
					return false;
				});
				yield;
			}
			if (bubble.pid == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						ended
					)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", bubble.pid)
			});
		}

		/**
		 * ''Sandbox-Bubble.kill'' — stop a job we started.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param session_id chat that started this command
		 */
		public void kill(OLLMrpc.Request request, int pid, int64 session_id)
		{
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)
				|| OLLMbwrap.Bubble.jobs.get(pid).session_id != session_id) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			OLLMbwrap.Bubble.jobs.get(pid).stop();
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = "ok"
			});
		}

		/**
		 * ''Sandbox-Bubble.tail'' — last 50 lines of a job we started.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param session_id chat that started this command
		 */
		public void tail(OLLMrpc.Request request, int pid, int64 session_id)
		{
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)
				|| OLLMbwrap.Bubble.jobs.get(pid).session_id != session_id) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			var bubble = OLLMbwrap.Bubble.jobs.get(pid);
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", bubble.output_lines),
				msg = string.joinv("\n", bubble.tail)
			});
		}

		/**
		 * ''Sandbox-Bubble.wait'' — wait on a job we started.
		 *
		 * Seconds below 1 means 60. Retval is the exit code once the
		 * job has ended, or the negative pid while it is still running.
		 * args[0] is the spill path, empty unless the run has more
		 * than 50 lines. args[1] is the line count.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param seconds how long to wait
		 * @param session_id chat that started this command
		 */
		public void wait(OLLMrpc.Request request, int pid, int seconds, int64 session_id)
		{
			this.wait_run.begin(request, (obj, res) => {
				this.wait_run.end(res);
			});
		}

		/**
		 * Poll the job every 5 seconds until it ends or the wait expires.
		 *
		 * A finished job replies with its exit code. A live job replies
		 * with the negative pid, including when it is waiting on stdin.
		 * Every success reply puts the spill path in args[0] (empty
		 * unless the run has more than 50 lines) and the line count
		 * in args[1].
		 *
		 * @param request inbound RPC
		 */
		private async void wait_run(OLLMrpc.Request request)
		{
			var pid = (int) request.args.get(0).get_int();
			var seconds = (int) request.args.get(1).get_int();
			var session_id = request.args.get(2).get_int64();
			var left = seconds < 1 ? 60 : seconds;
			while (left > 0) {
				if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
					break;
				}
				var bubble = OLLMbwrap.Bubble.jobs.get(pid);
				if (bubble.session_id != session_id) {
					break;
				}
				if (bubble.waiting_stdin()) {
					break;
				}
				var step = left < 5 ? left : 5;
				GLib.Timeout.add_seconds(step, () => {
					this.wait_run.callback();
					return false;
				});
				yield;
				left -= step;
			}
			if (OLLMbwrap.Bubble.jobs != null && OLLMbwrap.Bubble.jobs.has_key(pid)) {
				var bubble = OLLMbwrap.Bubble.jobs.get(pid);
				if (bubble.session_id != session_id) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 0),
						msg = "command has ended",
						args = OLLMrpc.args("si", "", 0)
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", -pid),
					msg = string.joinv("\n", bubble.tail),
					args = OLLMrpc.args(
						"si",
						bubble.output_lines > 50 ? bubble.spill_path : "",
						bubble.output_lines
					)
				});
				return;
			}
			if (!OLLMbwrap.Bubble.ended.has_key(pid)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended",
					args = OLLMrpc.args("si", "", 0)
				});
				return;
			}
			var done = OLLMbwrap.Bubble.ended.get(pid);
			if (done.session_id != session_id) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended",
					args = OLLMrpc.args("si", "", 0)
				});
				return;
			}
			var msg = string.joinv("\n", done.tail);
			if (msg != "") {
				msg += "\n";
			}
			msg += "Exit code: " + done.exit_status.to_string();
			OLLMbwrap.Bubble.ended.unset(pid);
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", done.exit_status),
				msg = msg,
				args = OLLMrpc.args(
					"si",
					done.output_lines > 50 ? done.spill_path : "",
					done.output_lines
				)
			});
		}

		/**
		 * ''Sandbox-Bubble.send'' — write to a job we started.
		 *
		 * Nothing is appended. The caller sends its own newline.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param text bytes to write, verbatim
		 * @param session_id chat that started this command
		 */
		public void send(OLLMrpc.Request request, int pid, string text, int64 session_id)
		{
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)
				|| OLLMbwrap.Bubble.jobs.get(pid).session_id != session_id) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			try {
				OLLMbwrap.Bubble.jobs.get(pid).send(text);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = "ok"
			});
		}
	}
}
