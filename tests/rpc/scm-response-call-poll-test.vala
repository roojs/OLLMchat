/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * SCM_RIGHTS Response via Client.call_poll — types here are NOT shipped
 * in libocrpc.
 *
 * Server runs as a separate process (argv "server"), not fork-after-
 * GApplication and not a shared MainContext with the client. Matches
 * gnome-shell-rpc Helper vs Runtime: server can reply while the client
 * blocks in call_poll without iterating the default MainContext.
 */

namespace RpcDummy
{
	public class PaintPoll : GLib.Object
	{
		public int send_fd = -1;

		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(PaintPoll),
				"hello", "",
				"paint", ""
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void paint(OLLMrpc.Request request)
		{
			request.reply(
				new OLLMrpc.Response(),
				new OLLMrpc.Live.Buffer(this.send_fd)
			);
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcScmResponseCallPoll : RpcTestAppBase
	{
		public TestRpcScmResponseCallPoll()
		{
			base("com.roojs.ollmchat.test-rpc-scm-response-call-poll");
		}

		protected override string get_app_name()
		{
			return "test-rpc-scm-response-call-poll";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			int[] pipe_fds = new int[2];
			if (Posix.pipe(pipe_fds) != 0) {
				this.fail(command_line, "pipe failed");
			}
			uint8 payload = 0xAB;
			if (Posix.write(pipe_fds[1], &payload, 1) != 1) {
				this.fail(command_line, "pipe write failed");
			}

			var dir = GLib.DirUtils.make_tmp("ocrpc-scm-response-call-poll-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var ready_path = GLib.Path.build_filename(dir, "ready");

			var self_bin = GLib.FileUtils.read_link("/proc/self/exe");
			string[] spawn_args = {
				self_bin,
				"server",
				sock,
				ready_path,
				"%d".printf(pipe_fds[0])
			};
			string[] spawn_env = GLib.Environ.get();
			Pid child_pid = 0;
			try {
				GLib.Process.spawn_async(
					null,
					spawn_args,
					spawn_env,
					GLib.SpawnFlags.DO_NOT_REAP_CHILD,
					() => {
						Posix.close(pipe_fds[1]);
					},
					out child_pid
				);
			} catch (GLib.Error e) {
				this.fail(command_line, "spawn server: %s".printf(e.message));
			}
			Posix.close(pipe_fds[0]);

			var waited = 0;
			while (!GLib.FileUtils.test(ready_path, GLib.FileTest.EXISTS)) {
				if (waited > 50) {
					Posix.kill(child_pid, Posix.Signal.TERM);
					Posix.waitpid(child_pid, null, 0);
					this.fail(command_line, "server ready timeout");
				}
				GLib.Thread.usleep(100000);
				waited++;
			}

			OLLMrpc.Client? rpc = null;
			try {
				rpc = new OLLMrpc.Client("", "", sock) {
					live_handles = true,
					call_timeout_seconds = 5
				};
				var connected = false;
				var loop = new GLib.MainLoop();
				rpc.connect.begin(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello"
				}, null, (obj, res) => {
					connected = rpc.connect.end(res);
					loop.quit();
				});
				loop.run();
				this.check(command_line, connected, "client connect failed");

				OLLMrpc.Response? response = null;
				try {
					response = rpc.call_poll(new OLLMrpc.Request() {
						method = "RPC-Daemon.paint"
					});
				} catch (GLib.Error e) {
					this.fail(command_line, "call_poll paint: %s".printf(e.message));
				}
				this.check(command_line, response.error == null, "paint returned error");
				var got_fd = response.buffer != null ? response.buffer.fd : -1;
				if (got_fd < 0) {
					command_line.printerr(
						"call_poll paint got_fd=%d buffer=%s\n",
						got_fd,
						response.buffer == null ? "null" : "set"
					);
					rpc.disconnect();
					rpc = null;
					Posix.kill(child_pid, Posix.Signal.TERM);
					Posix.waitpid(child_pid, null, 0);
					Posix.exit(1);
				}
				uint8 read_byte = 0;
				if (Posix.read(got_fd, &read_byte, 1) != 1) {
					this.fail(command_line, "read fd failed");
				}
				this.check(command_line, read_byte == payload, "fd payload mismatch");
			} finally {
				if (rpc != null) {
					rpc.disconnect();
				}
				Posix.kill(child_pid, Posix.Signal.TERM);
				Posix.waitpid(child_pid, null, 0);
			}
		}
	}
}

int main(string[] args)
{
	if (args.length >= 5 && args[1] == "server") {
		var sock = args[2];
		var ready_path = args[3];
		var send_fd = int.parse(args[4]);
		OLLMrpc.rpc_register(true);
		var dummy = new RpcDummy.PaintPoll();
		dummy.send_fd = send_fd;
		RpcDummy.PaintPoll.rpc_register();
		OLLMrpc.Request.register("RPC-Daemon", dummy);
		var listen = new OLLMrpc.Transport.SocketListen(sock) {
			live_handles = true
		};
		if (!listen.start()) {
			return 2;
		}
		try {
			GLib.FileUtils.set_contents(ready_path, "1");
		} catch (GLib.Error e) {
			return 3;
		}
		new GLib.MainLoop().run();
		return 0;
	}
	return new OLLMrpcTests.TestRpcScmResponseCallPoll().run(args);
}
