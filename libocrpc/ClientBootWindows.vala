namespace OLLMrpc
{
	/**
	 * Ensure the Windows TCP {@code ollmfilesd} endpoint is reachable.
	 *
	 * The process is started in foreground TCP mode. Readiness is detected by
	 * probing the loopback endpoint instead of a pid file.
	 */
	public class ClientBoot : GLib.Object
	{
		public string socket { get; construct; }
		public string pid { get; construct; }

		public uint max_attempts { get; set; default = 3; }

		public uint poll { get; set; default = 100; }

		public uint startup_wait { get; set; default = 5; }

		public uint grace { get; set; default = 500; }

		public uint probe { get; set; default = 2; }

		private int detached_pid = -1;

		public ClientBoot(string? socket = null, string? pid = null)
		{
			var endpoint = socket != null ? socket : "127.0.0.1:4141";
			if (endpoint.has_prefix("tcp://")) {
				endpoint = endpoint.substring(6);
			}
			GLib.Object(
				socket: endpoint,
				pid: pid != null ? pid : ""
			);
		}

		public async void ensure_daemon() throws GLib.IOError
		{
			if (this.connectable()) {
				return;
			}

			try {
				this.spawn();
			} catch (GLib.IOError e) {
				throw e;
			}

			yield this.startup();
			if (this.connectable()) {
				return;
			}

			throw new GLib.IOError.FAILED(
				"ClientBoot: could not start or reach the filesystem daemon"
			);
		}

		public bool connectable()
		{
			var client = new GLib.SocketClient();
			client.timeout = this.probe;
			try {
				var conn = client.connect_to_host(
					this.socket,
					4141,
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
			var host = this.socket;
			var port = 4141;
			var colon = this.socket.last_index_of(":");
			if (colon > 0) {
				host = this.socket[0:colon];
				int.try_parse(this.socket.substring(colon + 1), out port);
			}
			unowned string? from_env = GLib.Environment.get_variable("OLLM_OLLMFILESD");
			var executable = (from_env != null && from_env != "")
				? from_env
				: "ollmfilesd";
			string[] argv = {
				executable,
				"--tcp",
				"--tcp-host=" + host,
				"--tcp-port=" + port.to_string()
			};
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
					"ClientBoot: spawn "
						+ executable
						+ ": "
						+ e.message
				);
			}
			this.detached_pid = child_pid;
			GLib.ChildWatch.add(child_pid, (w_pid, status) => {
				if (w_pid == this.detached_pid) {
					this.detached_pid = -1;
				}
				GLib.Process.close_pid(w_pid);
			});
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
			var source_id = GLib.Timeout.add(ms, pause.callback);
			yield;
			GLib.Source.remove(source_id);
		}
	}
}
