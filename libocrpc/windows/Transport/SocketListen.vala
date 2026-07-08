/*
 * Windows/Android fallback for Unix-domain socket RPC listener.
 *
 * The real implementation binds a stream socket at a filesystem path via
 * gio-unix. On Windows and Android, callers should use TCP transport instead.
 */

namespace OLLMrpc.Transport
{
	public class SocketListen : Listen
	{
		public string socket_path { get; construct; }

		public SocketListen(string socket_path)
		{
			GLib.Object(socket_path: socket_path);
		}

		public override bool start()
		{
			GLib.warning(
				"Unix socket RPC listener is not available on Windows (%s)",
				this.socket_path
			);
			return false;
		}

		public override void stop()
		{
		}
	}
}
