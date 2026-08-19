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

		int[] main_sv = new int[2];
		int[] fd_sv = new int[2];
		if (Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, main_sv) != 0
		 || Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, fd_sv) != 0) {
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

		GLib.Socket main_server_sock;
		GLib.Socket main_client_sock;
		GLib.Socket fd_server_sock;
		GLib.Socket fd_client_sock;
		try {
			main_server_sock = new GLib.Socket.from_fd(main_sv[0]);
			main_client_sock = new GLib.Socket.from_fd(main_sv[1]);
			fd_server_sock = new GLib.Socket.from_fd(fd_sv[0]);
			fd_client_sock = new GLib.Socket.from_fd(fd_sv[1]);
		} catch (GLib.Error e) {
			GLib.printerr("socket from_fd failed: %s\n", e.message);
			return 1;
		}

		var server_stream = (GLib.SocketConnection) GLib.Object.new(
			typeof(GLib.SocketConnection),
			"socket", main_server_sock,
			null
		);
		var client_stream = (GLib.SocketConnection) GLib.Object.new(
			typeof(GLib.SocketConnection),
			"socket", main_client_sock,
			null
		);

		var server = new OLLMrpc.Transport.Connection(server_stream) {
			buffer_stream = new OLLMrpc.Live.BufferStream() {
				socket = fd_server_sock
			}
		};
		server.start();

		var client_buffer_stream = new OLLMrpc.Live.BufferStream() {
			socket = fd_client_sock
		};

		server.write(
			new OLLMrpc.Notification() {
				method = "Window.thumbnail",
				object_type = "Window",
				id = 42
			},
			new OLLMrpc.Live.Buffer(pipe_fds[0])
		);

		var client_in = new GLib.DataInputStream(client_stream.get_input_stream());
		var client_bin = new OLLMrpc.Bin.Stream(client_in, null, false);

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
		try {
			client_buffer_stream.receive_one();
		} catch (GLib.Error e) {
			GLib.printerr("receive fd failed: %s\n", e.message);
			return 1;
		}
		client_buffer_stream.attach(notif);
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
