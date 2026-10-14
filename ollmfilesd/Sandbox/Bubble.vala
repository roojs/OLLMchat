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
		 * @param request inbound RPC
		 */
		public void can_wrap(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = OLLMbwrap.Bubble.can_wrap() ? "1" : "0"
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
			var ended = "";
			bubble.finished.connect((output) => {
				ended = output;
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
					if (OLLMbwrap.Bubble.ended.has_key(pid)
						&& OLLMbwrap.Bubble.ended.get(pid).session_id == session_id) {
						var done = OLLMbwrap.Bubble.ended.get(pid);
						var msg = string.joinv("\n", done.tail);
						if (msg != "") {
							msg += "\n";
						}
						msg += "Exit code: " + done.exit_status.to_string();
						OLLMbwrap.Bubble.ended.unset(pid);
						request.reply(new OLLMrpc.Response() {
							id = request.id,
							retval = OLLMrpc.val("i", done.exit_status),
							msg = msg
						});
						return;
					}
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 0),
						msg = "command has ended"
					});
					return;
				}
				var bubble = OLLMbwrap.Bubble.jobs.get(pid);
				if (bubble.session_id != session_id) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 0),
						msg = "command has ended"
					});
					return;
				}
				if (bubble.waiting_stdin()) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", -pid),
						msg = string.joinv("\n", bubble.tail)
					});
					return;
				}
				var step = left < 5 ? left : 5;
				GLib.Timeout.add_seconds(step, () => {
					this.wait_run.callback();
					return false;
				});
				yield;
				left -= step;
			}
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
				if (OLLMbwrap.Bubble.ended.has_key(pid)
					&& OLLMbwrap.Bubble.ended.get(pid).session_id == session_id) {
					var done = OLLMbwrap.Bubble.ended.get(pid);
					var msg = string.joinv("\n", done.tail);
					if (msg != "") {
						msg += "\n";
					}
					msg += "Exit code: " + done.exit_status.to_string();
					OLLMbwrap.Bubble.ended.unset(pid);
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", done.exit_status),
						msg = msg
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended"
				});
				return;
			}
			var still = OLLMbwrap.Bubble.jobs.get(pid);
			if (still.session_id != session_id) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", -pid),
				msg = string.joinv("\n", still.tail)
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
