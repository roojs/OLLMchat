/*
 * Windows fallback for ollmfilesd boot over a Unix socket.
 *
 * The real implementation probes and spawns the daemon against a filesystem
 * socket. On Windows, daemon RPC is not available yet.
 */

namespace OLLMrpc
{
	public class ClientBoot : GLib.Object
	{
		public string socket { get; construct; }
		public string pid { get; construct; }

		public string binary { get; set; default = "ollmfilesd"; }

		public uint max_attempts { get; set; default = 3; }

		public uint poll { get; set; default = 100; }

		public uint startup_wait { get; set; default = 5; }

		public uint grace { get; set; default = 500; }

		public uint probe { get; set; default = 2; }

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

		public async void ensure_daemon() throws GLib.IOError
		{
			throw new GLib.IOError.NOT_SUPPORTED(
				"ClientBoot: Unix socket RPC to ollmfilesd is not available on Windows"
			);
		}

		public bool connectable()
		{
			return false;
		}
	}
}
