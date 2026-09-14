/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Ffi ''S'' string[] length + element pin — types NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class Strv : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Strv", typeof(Strv),
				"hello", "",
				"echo", "S"
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void echo(OLLMrpc.Request request, string[] items)
		{
			var wire = (string[]) request.args.get(0);
			if (items.length != wire.length) {
				request.reply(new OLLMrpc.Response() {
					msg = "len:%d want:%d".printf(items.length, wire.length)
				});
				return;
			}
			for (var i = 0; i < items.length; i++) {
				if (items[i] != wire[i]) {
					request.reply(new OLLMrpc.Response() {
						msg = "mismatch:%d".printf(i)
					});
					return;
				}
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok:%d".printf(items.length)
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcFfiAs : RpcTestAppBase
	{
		public TestRpcFfiAs()
		{
			base("com.roojs.ollmchat.test-rpc-ffi-as");
		}

		protected override string get_app_name()
		{
			return "test-rpc-ffi-as";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			RpcDummy.Strv.rpc_register();
			OLLMrpc.Request.register("RPC-Strv", new RpcDummy.Strv());
			var dir = GLib.DirUtils.make_tmp("ocrpc-ffi-as-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock);
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock);
			var connected = false;
			var loop = new GLib.MainLoop();
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Strv.hello"
			}, null, (obj, res) => {
				connected = rpc.connect.end(res);
				loop.quit();
			});
			loop.run();
			this.check(command_line, connected, "client connect failed");
			string[] payload = { "meta", "wayland-client", "--nested", "prove" };
			var req = new OLLMrpc.Request() {
				method = "RPC-Strv.echo",
				args = OLLMrpc.args("S", payload)
			};
			OLLMrpc.Response? response = null;
			var call_loop = new GLib.MainLoop();
			rpc.call.begin(req, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "echo returned error");
			this.check(command_line, response.msg == "ok:4",
				"echo S want ok:4 got %s".printf(response.msg));
			listen.stop();
			GLib.FileUtils.unlink(sock);
			GLib.DirUtils.remove(dir);
		}
	}
}

int main(string[] args)
{
	var app = new OLLMrpcTests.TestRpcFfiAs();
	return app.run(args);
}
