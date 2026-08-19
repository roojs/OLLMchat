/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * SCM_RIGHTS notification smoke — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	class TestRpcScmNotification : RpcTestAppBase
	{
		public TestRpcScmNotification()
		{
			base("com.roojs.ollmchat.test-rpc-scm-notification");
		}

		protected override string get_app_name()
		{
			return "test-rpc-scm-notification";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Notification.rpc_register();

			int[] main_sv = new int[2];
			int[] fd_sv = new int[2];
			if (Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, main_sv) != 0
			 || Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, fd_sv) != 0) {
				this.fail(command_line, "socketpair failed");
			}

			int[] pipe_fds = new int[2];
			if (Posix.pipe(pipe_fds) != 0) {
				this.fail(command_line, "pipe failed");
			}
			uint8 payload = 0xAB;
			if (Posix.write(pipe_fds[1], &payload, 1) != 1) {
				this.fail(command_line, "pipe write failed");
			}

		GLib.Socket? main_server_sock = null;
		GLib.Socket? main_client_sock = null;
		GLib.Socket? fd_server_sock = null;
		GLib.Socket? fd_client_sock = null;
		try {
			main_server_sock = new GLib.Socket.from_fd(main_sv[0]);
			main_client_sock = new GLib.Socket.from_fd(main_sv[1]);
			fd_server_sock = new GLib.Socket.from_fd(fd_sv[0]);
			fd_client_sock = new GLib.Socket.from_fd(fd_sv[1]);
		} catch (GLib.Error e) {
			this.fail(command_line, "socket from_fd failed: %s".printf(e.message));
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
				this.fail(command_line, "parse failed: %s".printf(e.message));
			}
			this.check(command_line, notif != null, "expected Notification");
			try {
				client_buffer_stream.receive_one();
			} catch (GLib.Error e) {
				this.fail(command_line, "receive fd failed: %s".printf(e.message));
			}
			client_buffer_stream.attach(notif);
			this.check(
				command_line,
				notif.buffer != null && notif.buffer.fd >= 0,
				"missing buffer fd"
			);
			uint8 read_byte = 0;
			if (Posix.read(notif.buffer.fd, &read_byte, 1) != 1) {
				this.fail(command_line, "read fd failed");
			}
			this.check(command_line, read_byte == payload, "fd payload mismatch");
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcScmNotification().run(args);
}
