/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * SCM_RIGHTS Request via Client.call_poll — arrow reversed from
 * scm-response-call-poll-test.vala. Client sends the fd; server
 * handler reads request.buffer.fd. Types here are NOT shipped in libocrpc.
 *
 * Server runs as a separate process (argv "server"), not fork-after-
 * GApplication and not a shared MainContext with the client. Matches
 * gnome-shell-rpc Helper vs Runtime: server can reply while the client
 * blocks in call_poll without iterating the default MainContext.
 */

namespace RpcDummy
{
	public class EatPoll : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(EatPoll),
				"hello", "",
				"eat_fd", ""
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void eat_fd(OLLMrpc.Request request)
		{
			var got = request.buffer != null ? request.buffer.fd : -1;
			uint8 b = 0;
			var ok = got >= 0 && Posix.read(got, &b, 1) == 1 && b == 0xAB;
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				args = OLLMrpc.args("b", ok),
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcScmRequestCallPoll : RpcTestAppBase
	{
		public TestRpcScmRequestCallPoll()
		{
			base("com.roojs.ollmchat.test-rpc-scm-request-call-poll");
		}

		protected override string get_app_name()
		{
			return "test-rpc-scm-request-call-poll";
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

			var dir = GLib.DirUtils.make_tmp("ocrpc-scm-request-call-poll-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var ready_path = GLib.Path.build_filename(dir, "ready");

			var self_bin = GLib.FileUtils.read_link("/proc/self/exe");
			string[] spawn_args = {
				self_bin,
				"server",
				sock,
				ready_path
			};
			string[] spawn_env = GLib.Environ.get();
			Pid child_pid = 0;
			try {
				GLib.Process.spawn_async(
					null,
					spawn_args,
					spawn_env,
					GLib.SpawnFlags.DO_NOT_REAP_CHILD,
					null,
					out child_pid
				);
			} catch (GLib.Error e) {
				this.fail(command_line, "spawn server: %s".printf(e.message));
			}

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
						method = "RPC-Daemon.eat_fd",
						buffer = new OLLMrpc.Live.Buffer(pipe_fds[0])
					});
				} catch (GLib.Error e) {
					this.fail(command_line, "call_poll eat_fd: %s".printf(e.message));
				}
				this.check(command_line, response.error == null, "eat_fd returned error");
				this.check(command_line, response.args.size > 0, "eat_fd no args");
				this.check(command_line, response.args.get(0).get_boolean(), "fd payload mismatch");
			} finally {
				if (rpc != null) {
					rpc.disconnect();
				}
				Posix.close(pipe_fds[0]);
				Posix.close(pipe_fds[1]);
				Posix.kill(child_pid, Posix.Signal.TERM);
				Posix.waitpid(child_pid, null, 0);
			}
		}
	}
}

int main(string[] args)
{
	if (args.length >= 4 && args[1] == "server") {
		var sock = args[2];
		var ready_path = args[3];
		OLLMrpc.rpc_register(true);
		RpcDummy.EatPoll.rpc_register();
		OLLMrpc.Request.register("RPC-Daemon", new RpcDummy.EatPoll());
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
	return new OLLMrpcTests.TestRpcScmRequestCallPoll().run(args);
}
