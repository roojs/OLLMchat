/*
 * Windows fallback for the ollmfilesd Unix-socket RPC client.
 *
 * The real implementation connects to a filesystem socket via gio-unix.
 * On Windows, daemon RPC is not available yet; connect() fails cleanly.
 */

namespace OLLMrpc
{
	public class Client : GLib.Object
	{
		public string socket { get; construct; }

		public uint call_timeout_seconds { get; set; default = 120; }

		public bool connected { get; private set; default = false; }

		public string connect_error { get; private set; default = ""; }

		public signal void notification(Notification notif);

		public signal void failed(Request request, Error error);

		static construct
		{
			Error.rpc_register();
			Notification.rpc_register();
		}

		public Client(string socket = "")
		{
			string path = socket;
			if (path == "") {
				path = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat",
					"ollmfilesd.sock"
				);
			}
			GLib.Object(socket: path);
		}

		public async bool connect(Request hello_request)
		{
			this.connect_error =
				"Unix socket RPC to ollmfilesd is not available on Windows";
			GLib.warning("Client: %s", this.connect_error);
			return false;
		}

		public void disconnect()
		{
			this.connected = false;
			this.connect_error = "";
		}

		public async Response call(Request request)
		{
			var error = new Error(
				RpcErrorCode.INTERNAL_ERROR,
				"Unix socket RPC to ollmfilesd is not available on Windows",
				request.method,
				request.id
			);
			this.failed(request, error);
			return new Response() { id = request.id, error = error };
		}
	}
}
