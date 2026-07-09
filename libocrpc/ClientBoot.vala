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
	 * Ensure {{{ollmfilesd}}} is running before {@link Client.connect} on Unix.
	 *
	 * The caller supplies every path; there is no default
	 * {{{~/.local/share/ollmchat}}} in this class. Constructor args {@link pid}
	 * and {@link socket_name} are basenames within {@link data_dir}; the {@link pid}
	 * and {@link socket_path} properties hold the full paths used for probe, spawn,
	 * and kill-and-respawn.
	 *
	 * Parameter order after the three required strings: {@link debug}, then
	 * {@link pass_data_dir}. {@link debug} defaults to true because in-tree
	 * callers almost always want {{{ollmfilesd --debug}}}. {@link pass_data_dir}
	 * defaults to false; only out-of-band vector test CLIs set it true because
	 * standard and custom dirs share the same basename layout and spawn cannot
	 * infer {{{--data-dir=DIR}}} from paths alone.
	 *
	 * Spawn argv: {@link debug} adds {{{--debug}}}; {@link pass_data_dir} adds
	 * {{{--data-dir=data_dir}}}. Executable: {{{OLLM_OLLMFILESD}}} env when set
	 * (build wrapper scripts), else {{{ollmfilesd}}} on {{{PATH}}}; env selects
	 * the binary only and does not set debug or data-dir flags (see §5.5.4).
	 *
	 * Production code constructs this only from {@link Client.connect}.
	 * Callers set paths on {@link Client} — see §5.5.6 and §5.5.7.
	 */
	public class ClientBoot : GLib.Object
	{
		public string data_dir { get; construct; }

		public bool debug { get; construct; default = true; }

		public bool pass_data_dir { get; construct; default = false; }

		public string socket_path { get; construct; }

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

		/**
		 * @param data_dir Directory root for daemon DB, socket, and pid file.
		 *   When empty, {@code pid} and {@code socket_name} are stored verbatim
		 * @param pid Basename of the pid file within {@link data_dir}, or the full
		 *   pid path when {@code data_dir} is empty
		 * @param socket_name Basename of the Unix socket within {@link data_dir},
		 *   or the full connect path when {@code data_dir} is empty
		 * @param debug When true (default), spawn passes {{{--debug}}} to
		 *   {{{ollmfilesd}}}; listed before {@link pass_data_dir} because most
		 *   callers rely on the default
		 * @param pass_data_dir When true, spawn passes {{{--data-dir=data_dir}}};
		 *   default false — out-of-band vector testing only
		 */
		public ClientBoot(
			string data_dir,
			string pid,
			string socket_name,
			bool debug = true,
			bool pass_data_dir = false
		)
		{
			var full_pid = pid;
			var full_socket = socket_name;
			if (data_dir != "") {
				full_pid = GLib.Path.build_filename(data_dir, pid);
				full_socket = GLib.Path.build_filename(data_dir, socket_name);
			}
			GLib.Object(
				data_dir: data_dir,
				pid: full_pid,
				socket_path: full_socket,
				debug: debug,
				pass_data_dir: pass_data_dir
			);
		}

		public async GLib.SocketConnection connect() throws GLib.Error
		{
			var client = new GLib.SocketClient();
			if (this.socket_path.has_prefix("tcp://")) {
				var endpoint = this.socket_path.substring(6);
				var host = endpoint;
				var port = 4141;
				var colon = endpoint.last_index_of(":");
				if (colon > 0) {
					host = endpoint[0:colon];
					int.try_parse(endpoint.substring(colon + 1), out port);
				}
				return yield client.connect_to_host_async(
					host,
					port,
					null
				);
			}
			return yield client.connect_async(
				new GLib.UnixSocketAddress(this.socket_path),
				null
			);
		}

		/**
		 * Block until {@link socket_path} accepts a connection, spawning or
		 * kill-and-respawning {{{ollmfilesd}}} when needed.
		 */
		public async void ensure_daemon() throws GLib.IOError
		{
			var daemon_pid = this.read_pid();
			GLib.debug(
				"ensure_daemon socket_path=%s pid_file=%s pid=%d pid_running=%s "
					+ "socket_exists=%s connectable=%s",
				this.socket_path,
				this.pid,
				daemon_pid,
				this.pid_running(daemon_pid) ? "true" : "false",
				GLib.FileUtils.test(this.socket_path, GLib.FileTest.EXISTS)
					? "true"
					: "false",
				this.connectable() ? "true" : "false"
			);

			if (this.connectable()) {
				GLib.debug(
					"ensure_daemon ready socket_path=%s pid=%d",
					this.socket_path,
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
				GLib.FileUtils.test(this.socket_path, GLib.FileTest.EXISTS)
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
		 * @return true when a stream connection to {@link socket_path} succeeds
		 */
		public bool connectable()
		{
			if (!GLib.FileUtils.test(this.socket_path, GLib.FileTest.EXISTS)) {
				return false;
			}
			var client = new GLib.SocketClient();
			client.timeout = (uint) this.probe;
			try {
				var conn = client.connect(
					new GLib.UnixSocketAddress(this.socket_path),
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
			if (this.debug) {
				argv += "--debug";
			}
			if (this.pass_data_dir) {
				argv += "--data-dir=%s".printf(this.data_dir);
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
				"startup timed out socket_path=%s wait=%us",
				this.socket_path,
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
			if (!GLib.FileUtils.test(this.socket_path, GLib.FileTest.EXISTS)) {
				return;
			}
			GLib.FileUtils.unlink(this.socket_path);
		}
	}
}
