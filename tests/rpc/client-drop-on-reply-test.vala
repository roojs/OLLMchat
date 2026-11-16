/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Reply waiter drops the last external Client ref before complete_pending
 * returns. That used to finalize the client and crash in send_head.
 */

namespace RpcDrop
{
	public class Ping : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Ping),
				"hello", ""
			);
			OLLMrpc.Request.add_class(
				"Ping", typeof(Ping),
				"once", ""
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void once(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcClientDropOnReply : RpcTestAppBase
	{
		private OLLMrpc.Client? rpc;

		public TestRpcClientDropOnReply()
		{
			base("com.roojs.ollmchat.test-rpc-client-drop-on-reply");
		}

		protected override string get_app_name()
		{
			return "test-rpc-client-drop-on-reply";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			RpcDrop.Ping.rpc_register();
			OLLMrpc.Request.register("RPC-Daemon", new RpcDrop.Ping());
			OLLMrpc.Request.register("Ping", new RpcDrop.Ping());
			var dir = GLib.DirUtils.make_tmp("ocrpc-drop-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock);
			this.check(command_line, listen.start(), "listen start failed");
			this.rpc = new OLLMrpc.Client("", "", sock);
			var connected = false;
			var loop = new GLib.MainLoop();
			this.rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello"
			}, null, (obj, res) => {
				connected = this.rpc.connect.end(res);
				loop.quit();
			});
			loop.run();
			this.check(command_line, connected, "client connect failed");

			var saw = false;
			var drop_loop = new GLib.MainLoop();
			string? drop_error = null;
			this.drop.begin((obj, res) => {
				try {
					saw = this.drop.end(res);
				} catch (GLib.Error e) {
					drop_error = e.message;
				}
				drop_loop.quit();
			});
			drop_loop.run();
			this.check(command_line, drop_error == null, drop_error ?? "");
			this.check(command_line, saw, "reply waiter did not run");
			this.check(command_line, this.rpc == null, "client ref was not dropped");
			listen.stop();
		}

		/**
		 * Yield the call, then drop the only external ref from that waiter.
		 * {@link OLLMrpc.Client.complete_pending} is still on the stack.
		 */
		private async bool drop() throws GLib.Error
		{
			var response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "Ping.once"
			});
			if (response.error != null) {
				return false;
			}
			var dying = this.rpc;
			this.rpc = null;
			dying.disconnect();
			dying = null;
			return true;
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcClientDropOnReply().run(args);
}
