namespace OLLMrpc
{
	internal string default_client_endpoint()
	{
		return "tcp://127.0.0.1:4141";
	}

	internal bool client_boot_required(bool tcp)
	{
		return tcp;
	}

	internal async GLib.SocketConnection connect_unix_socket(
		string socket
	) throws GLib.Error
	{
		throw new GLib.IOError.NOT_SUPPORTED(
			"Unix socket RPC to ollmfilesd is not available on Windows"
		);
	}
}
