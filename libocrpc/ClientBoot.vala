/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc
{
	/**
	 * Ensure {{{ollmfilesd}}} is running before {@link Client.connect}.
	 *
	 * Uses {@link pid} and {@link socket} paths: probe the socket, spawn or
	 * kill-and-respawn when needed. Set {{{OLLM_OLLMFILESD}}} to an absolute
	 * path for dev/testing when the build-tree daemon should be used; otherwise
	 * {{{ollmfilesd}}} is resolved on {{{PATH}}}.
	 */
	public class ClientBoot : GLib.Object
	{
		public string socket { get; construct; }
		public string pid { get; construct; }

		/** Poll interval after spawn (milliseconds). */
		public uint poll { get; set; default = 100; }

		/** Max wait after each spawn (seconds). */
		public uint startup_wait { get; set; default = 5; }

		/** Pause after SIGTERM before respawn (milliseconds). */
		public uint grace { get; set; default = 500; }

		/** Connect probe timeout (seconds). */
		public uint probe { get; set; default = 2; }

		private int detached_pid = -1;

		public ClientBoot(string? socket = null, string? pid = null)
		{
			GLib.Object(
				socket: socket != null ? socket : GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat",
					"ollmfilesd.sock"
				),
				pid: pid != null ? pid : GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat",
					"ollmfilesd.pid"
				)
			);
		}

		/**
		 * Block until {@link socket} accepts a connection, spawning or
		 * kill-and-respawning {{{ollmfilesd}}} when needed.
		 */
		public async void ensure_daemon() throws GLib.IOError
		{
			var daemon_pid = this.read_pid();
			GLib.debug(
				"ensure_daemon socket=%s pid_file=%s pid=%d pid_running=%s "
					+ "socket_exists=%s connectable=%s",
				this.socket,
				this.pid,
				daemon_pid,
				this.pid_running(daemon_pid) ? "true" : "false",
				GLib.FileUtils.test(this.socket, GLib.FileTest.EXISTS)
					? "true"
					: "false",
				this.connectable() ? "true" : "false"
			);

			if (this.connectable()) {
				GLib.debug(
					"ensure_daemon ready socket=%s pid=%d",
					this.socket,
					daemon_pid
				);
				return;
			}

			if (this.pid_running(daemon_pid)) {
				GLib.debug(
					"ensure_daemon terminating pid=%d (socket not connectable)",
					daemon_pid
				);
				this.terminate_daemon(daemon_pid);
				yield this.pause(this.grace);
			}

			this.unlink_socket();
			if (GLib.FileUtils.test(this.pid, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.unlink(this.pid);
			}

			this.spawn();

			yield this.startup();
			daemon_pid = this.read_pid();
			GLib.debug(
				"ensure_daemon after startup pid=%d pid_running=%s "
					+ "socket_exists=%s connectable=%s",
				daemon_pid,
				this.pid_running(daemon_pid) ? "true" : "false",
				GLib.FileUtils.test(this.socket, GLib.FileTest.EXISTS)
					? "true"
					: "false",
				this.connectable() ? "true" : "false"
			);
			if (this.connectable()) {
				return;
			}

			throw new GLib.IOError.FAILED(
				"could not start or reach the filesystem daemon"
			);
		}

		/**
		 * @return true when a stream connection to {@link socket} succeeds
		 */
		public bool connectable()
		{
			if (!GLib.FileUtils.test(this.socket, GLib.FileTest.EXISTS)) {
				return false;
			}
			var client = new GLib.SocketClient();
			client.timeout = (uint) this.probe;
			try {
				var conn = client.connect(
					new GLib.UnixSocketAddress(this.socket),
					null
				);
				conn.close();
				return true;
			} catch (GLib.Error e) {
				return false;
			}
		}

		private void spawn() throws GLib.IOError
		{
			unowned string? from_env = GLib.Environment.get_variable("OLLM_OLLMFILESD");
			var executable = (from_env != null && from_env != "")
				? from_env
				: "ollmfilesd";
			// Build-tree daemon (OLLM_OLLMFILESD from meson wrapper): capture stdio on
			// crash via daemonize --debug → ~/.cache/ollmchat/ollmfilesd.stderr.log
			string[] argv = { executable };
			if (from_env != null && from_env != "") {
				argv += "--debug";
			}
			var child_pid = 0;
			try {
				GLib.Process.spawn_async(
					null,
					argv,
					null,
					GLib.SpawnFlags.DO_NOT_REAP_CHILD
						| GLib.SpawnFlags.STDOUT_TO_DEV_NULL
						| GLib.SpawnFlags.STDERR_TO_DEV_NULL
						| (!GLib.Path.is_absolute(executable)
							? GLib.SpawnFlags.SEARCH_PATH
							: 0),
					null,
					out child_pid
				);
			} catch (GLib.SpawnError e) {
				throw new GLib.IOError.FAILED(
					"spawn "
						+ executable
						+ ": "
						+ e.message
				);
			}
			if (from_env != null && from_env != "") {
				GLib.debug(
					"spawned pid=%d executable=%s stderr log=%s",
					child_pid,
					executable,
					GLib.Path.build_filename(
						GLib.Environment.get_home_dir(),
						".cache",
						"ollmchat",
						"ollmfilesd.stderr.log"
					)
				);
			} else {
				GLib.debug("spawned pid=%d executable=%s", child_pid, executable);
			}
			this.detached_pid = child_pid;
			GLib.ChildWatch.add(child_pid, (w_pid, status) => {
				if (w_pid == this.detached_pid) {
					this.detached_pid = -1;
				}
				GLib.Process.close_pid(w_pid);
			});
		}

		private void terminate_daemon(int daemon_pid)
		{
			Posix.kill(daemon_pid, Posix.Signal.TERM);
		}

		private async void startup()
		{
			var deadline = GLib.get_monotonic_time()
				+ (int64) this.startup_wait * 1000000;
			while (GLib.get_monotonic_time() < deadline) {
				if (this.connectable()) {
					return;
				}
				yield this.pause(this.poll);
			}
			GLib.debug(
				"startup timed out socket=%s wait=%us",
				this.socket,
				this.startup_wait
			);
		}

		private async void pause(uint ms)
		{
			var source_id = GLib.Timeout.add(ms, pause.callback);
			yield;
			GLib.Source.remove(source_id);
		}

		private int read_pid()
		{
			if (!GLib.FileUtils.test(this.pid, GLib.FileTest.EXISTS)) {
				return -1;
			}
			var text = "";
			try {
				GLib.FileUtils.get_contents(this.pid, out text);
			} catch (GLib.FileError e) {
				return -1;
			}
			text = text.strip();
			if (text == "") {
				return -1;
			}
			var daemon_pid = 0;
			if (!int.try_parse(text, out daemon_pid)) {
				return -1;
			}
			return daemon_pid;
		}

		private bool pid_running(int daemon_pid)
		{
			if (daemon_pid <= 0) {
				return false;
			}
			return Posix.kill(daemon_pid, 0) == 0;
		}

		private void unlink_socket()
		{
			if (!GLib.FileUtils.test(this.socket, GLib.FileTest.EXISTS)) {
				return;
			}
			GLib.FileUtils.unlink(this.socket);
		}
	}
}
