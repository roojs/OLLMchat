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
	 * Ensure {@code ollmfilesd} is running before {@link RpcClient.connect}.
	 *
	 * Uses {@link pid} and {@link socket} paths: probe the socket, spawn or
	 * kill-and-respawn when needed. Installing a user systemd unit is out of
	 * scope here (global settings UI, separate from boot).
	 */
	public class RpcClientBoot : GLib.Object
	{
		public string socket { get; construct; }
		public string pid { get; construct; }

		/** Executable name or path; resolved on {@code PATH} when relative. */
		public string binary { get; set; default = "ollmfilesd"; }

		/**
		 * When true, pass {@code --foreground} and keep the child
		 * {@link GLib.Subprocess} (tests, gdb). When false, detached spawn.
		 */
		public bool foreground { get; set; default = false; }

		/**
		 * Recovery cycles (spawn, or kill + spawn) without a working socket
		 * before {@link ensure_daemon} fails.
		 */
		public uint max_attempts { get; set; default = 3; }

		/** Poll interval after spawn (milliseconds). */
		public uint poll { get; set; default = 100; }

		/** Max wait after each spawn (seconds). */
		public uint startup_wait { get; set; default = 5; }

		/** Pause after SIGTERM before respawn (milliseconds). */
		public uint grace { get; set; default = 500; }

		/** Connect probe timeout (seconds). */
		public uint probe { get; set; default = 2; }

		private GLib.Subprocess? foreground_process;
		private int detached_pid = -1;

		public RpcClientBoot(string? socket = null, string? pid = null)
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
		 * kill-and-respawning {@link binary} when needed.
		 */
		public async void ensure_daemon() throws GLib.IOError
		{
			uint recovery = 0;
			while (recovery < this.max_attempts) {
				if (this.connectable()) {
					return;
				}

				int daemon_pid = this.read_pid();
				if (this.pid_running(daemon_pid)) {
					this.terminate_daemon(daemon_pid);
					yield this.pause(this.grace);
				}

				this.unlink_socket();
				if (GLib.FileUtils.test(this.pid, GLib.FileTest.EXISTS)) {
					GLib.FileUtils.unlink(this.pid);
				}

				try {
					this.spawn();
				} catch (GLib.IOError e) {
					recovery++;
					if (recovery >= this.max_attempts) {
						throw e;
					}
					continue;
				}

				yield this.startup();
				if (this.connectable()) {
					return;
				}

				recovery++;
			}

			throw new GLib.IOError.FAILED(
				"RpcClientBoot: could not start or reach the filesystem daemon"
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
			string[] argv;
			if (this.foreground) {
				argv = { this.binary, "--foreground" };
				try {
					this.foreground_process = new GLib.Subprocess.newv(
						argv,
						GLib.SubprocessFlags.STDOUT_PIPE |
						GLib.SubprocessFlags.STDERR_PIPE
					);
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED(
						"RpcClientBoot: spawn "
							+ this.binary
							+ ": "
							+ e.message
					);
				}
				this.write_pid(
					(int) this.foreground_process.get_identifier()
				);
				return;
			}

			argv = { this.binary };
			int child_pid;
			try {
				GLib.Process.spawn_async(
					null,
					argv,
					null,
					GLib.SpawnFlags.SEARCH_PATH |
					GLib.SpawnFlags.DO_NOT_REAP_CHILD |
					GLib.SpawnFlags.STDOUT_TO_DEV_NULL |
					GLib.SpawnFlags.STDERR_TO_DEV_NULL,
					null,
					out child_pid
				);
			} catch (GLib.SpawnError e) {
				throw new GLib.IOError.FAILED(
					"RpcClientBoot: spawn "
						+ this.binary
						+ ": "
						+ e.message
				);
			}
			this.detached_pid = child_pid;
			this.write_pid(child_pid);
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
		}

		private async void pause(uint ms)
		{
			uint source_id = GLib.Timeout.add(ms, pause.callback);
			yield;
			GLib.Source.remove(source_id);
		}

		private int read_pid()
		{
			if (!GLib.FileUtils.test(this.pid, GLib.FileTest.EXISTS)) {
				return -1;
			}
			string text;
			try {
				GLib.FileUtils.get_contents(this.pid, out text);
			} catch (GLib.FileError e) {
				return -1;
			}
			text = text.strip();
			if (text == "") {
				return -1;
			}
			int daemon_pid;
			if (int.try_parse(text, out daemon_pid)) {
				return daemon_pid;
			}
			return -1;
		}

		private void write_pid(int daemon_pid)
		{
			var parent = GLib.File.new_for_path(this.pid).get_parent();
			if (parent != null && !parent.query_exists()) {
				try {
					parent.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning(
						"could not create pid directory: %s",
						e.message
					);
					return;
				}
			}
			try {
				GLib.FileUtils.set_contents(
					this.pid,
					daemon_pid.to_string() + "\n"
				);
			} catch (GLib.FileError e) {
				GLib.warning(
					"could not write pid file: %s",
					e.message
				);
			}
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
