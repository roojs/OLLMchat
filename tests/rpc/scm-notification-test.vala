/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * SCM_RIGHTS notification smoke — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public static int main(string[] args)
	{
		OLLMrpc.Notification.rpc_register();

		int[] sv = new int[2];
		if (Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
			GLib.printerr("socketpair failed\n");
			return 1;
		}

		int[] pipe_fds = new int[2];
		if (Posix.pipe(pipe_fds) != 0) {
			GLib.printerr("pipe failed\n");
			return 1;
		}
		uint8 payload = 0xAB;
		if (Posix.write(pipe_fds[1], &payload, 1) != 1) {
			GLib.printerr("pipe write failed\n");
			return 1;
		}

		GLib.Socket server_sock;
		GLib.Socket client_sock;
		try {
			server_sock = new GLib.Socket.from_fd(sv[0]);
			client_sock = new GLib.Socket.from_fd(sv[1]);
		} catch (GLib.Error e) {
			GLib.printerr("socket from_fd failed: %s\n", e.message);
			return 1;
		}
		var server_stream = (GLib.SocketConnection) GLib.Object.new(
			typeof(GLib.SocketConnection),
			"socket", server_sock,
			null
		);
		var client_stream = (GLib.SocketConnection) GLib.Object.new(
			typeof(GLib.SocketConnection),
			"socket", client_sock,
			null
		);
		var server_out = new GLib.DataOutputStream(
			server_stream.get_output_stream()
		);
		var server_bin = new OLLMrpc.Bin.Stream(null, server_out, true) {
			socket = server_sock
		};

		server_bin.write(
			new OLLMrpc.Notification() {
				method = "Window.thumbnail",
				object_type = "Window",
				id = 42
			},
			new OLLMrpc.Live.Buffer(pipe_fds[0])
		);
		server_bin.out_stream.flush();

		var client_in = new GLib.DataInputStream(
			new GLib.BufferedInputStream(client_stream.get_input_stream())
		);
		var client_bin = new OLLMrpc.Bin.Stream(client_in, null, false) {
			socket = client_sock
		};

		OLLMrpc.Notification? notif = null;
		try {
			notif = client_bin.parse() as OLLMrpc.Notification;
		} catch (GLib.Error e) {
			GLib.printerr("parse failed: %s\n", e.message);
			return 1;
		}
		if (notif == null) {
			GLib.printerr("expected Notification\n");
			return 1;
		}
		if (notif.method != "Window.thumbnail") {
			GLib.printerr("method mismatch\n");
			return 1;
		}
		if (notif.buffer == null || notif.buffer.fd < 0) {
			GLib.printerr("missing buffer fd\n");
			return 1;
		}
		uint8 read_byte = 0;
		if (Posix.read(notif.buffer.fd, &read_byte, 1) != 1) {
			GLib.printerr("read fd failed\n");
			return 1;
		}
		if (read_byte != payload) {
			GLib.printerr("fd payload mismatch\n");
			return 1;
		}

		return 0;
	}
}
