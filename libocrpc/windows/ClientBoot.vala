namespace OLLMrpc
{
	/**
	 * Ensure the Windows TCP {{{ollmfilesd}}} endpoint is reachable.
	 *
	 * The process is started in foreground TCP mode. Readiness is detected by
	 * probing the loopback endpoint instead of a pid file.
	 *
	 * {@link socket_name} is a TCP URL ({{{tcp:}}} prefix plus
	 * {{{127.0.0.1:4141}}}); {@link socket_path} stores that value.
	 */
	public class ClientBoot : GLib.Object
	{
		public string data_dir { get; construct; }

		public bool debug { get; construct; default = true; }

		public bool pass_data_dir { get; construct; default = false; }

		public string socket_path { get; construct; }

		public string pid { get; construct; }

		public uint poll { get; set; default = 100; }

		public uint startup_wait { get; set; default = 5; }

		public uint grace { get; set; default = 500; }

		public uint probe { get; set; default = 2; }

		private int detached_pid = -1;

		public ClientBoot(
			string data_dir,
			string pid,
			string socket_name,
			bool debug = true,
			bool pass_data_dir = false
		)
		{
			GLib.Object(
				data_dir: data_dir,
				pid: pid,
				socket_path: socket_name,
				debug: debug,
				pass_data_dir: pass_data_dir
			);
		}

		public async GLib.SocketConnection connect() throws GLib.Error
		{
			if (!this.socket_path.has_prefix("tcp://")) {
				throw new GLib.IOError.NOT_SUPPORTED(
					"Unix socket RPC to ollmfilesd is not available on this platform"
				);
			}
			var endpoint = this.socket_path.substring(6);
			var host = endpoint;
			var port = 4141;
			var colon = endpoint.last_index_of(":");
			if (colon > 0) {
				host = endpoint[0:colon];
				int.try_parse(endpoint.substring(colon + 1), out port);
			}
			var client = new GLib.SocketClient();
			return yield client.connect_to_host_async(
				host,
				port,
				null
			);
		}

		public async void ensure_daemon() throws GLib.IOError
		{
			GLib.debug("ensure_daemon socket_path=%s", this.socket_path);
			if (this.connectable()) {
				return;
			}

			this.spawn();

			yield this.startup();
			if (this.connectable()) {
				return;
			}

			throw new GLib.IOError.FAILED(
				"could not start or reach the filesystem daemon"
			);
		}

		public bool connectable()
		{
			var host = this.socket_path;
			var port = 4141;
			if (this.socket_path.has_prefix("tcp://")) {
				var endpoint = this.socket_path.substring(6);
				host = endpoint;
				var colon = endpoint.last_index_of(":");
				if (colon > 0) {
					host = endpoint[0:colon];
					int.try_parse(endpoint.substring(colon + 1), out port);
				}
			}
			var client = new GLib.SocketClient();
			client.timeout = this.probe;
			try {
				var conn = client.connect_to_host(host, port, null);
				conn.close();
				return true;
			} catch (GLib.Error e) {
				return false;
			}
		}

		private void spawn() throws GLib.IOError
		{
			var host = this.socket_path;
			var port = 4141;
			if (this.socket_path.has_prefix("tcp://")) {
				var endpoint = this.socket_path.substring(6);
				host = endpoint;
				var colon = endpoint.last_index_of(":");
				if (colon > 0) {
					host = endpoint[0:colon];
					int.try_parse(endpoint.substring(colon + 1), out port);
				}
			} else {
				var colon = this.socket_path.last_index_of(":");
				if (colon > 0) {
					host = this.socket_path[0:colon];
					int.try_parse(this.socket_path.substring(colon + 1), out port);
				}
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
					"spawn "
						+ executable
						+ ": "
						+ e.message
				);
			}
			GLib.debug("spawned pid=%d executable=%s", child_pid, executable);
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
	}
}
