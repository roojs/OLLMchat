/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * SCM_RIGHTS Response smoke — types here are NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class Paint : GLib.Object
	{
		public int send_fd = -1;

		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Paint),
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
	class TestRpcScmResponse : RpcTestAppBase
	{
		public TestRpcScmResponse()
		{
			base("com.roojs.ollmchat.test-rpc-scm-response");
		}

		protected override string get_app_name()
		{
			return "test-rpc-scm-response";
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

			var dummy = new RpcDummy.Paint();
			dummy.send_fd = pipe_fds[0];
			RpcDummy.Paint.rpc_register();
			OLLMrpc.Request.register("RPC-Daemon", dummy);

			var dir = GLib.DirUtils.make_tmp("ocrpc-scm-response-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock) {
				live_handles = true
			};
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock) {
				live_handles = true
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
			var call_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.paint"
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "paint returned error");
			this.check(
				command_line,
				response.buffer != null && response.buffer.fd >= 0,
				"missing buffer fd"
			);
			uint8 read_byte = 0;
			if (Posix.read(response.buffer.fd, &read_byte, 1) != 1) {
				this.fail(command_line, "read fd failed");
			}
			this.check(command_line, read_byte == payload, "fd payload mismatch");
			rpc.disconnect();
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcScmResponse().run(args);
}
