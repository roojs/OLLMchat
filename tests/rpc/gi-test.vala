/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Typelib remote new smoke — Gio types are not shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class Hello : GLib.Object
	{
		public signal void call_hello(OLLMrpc.Request request);

		construct
		{
			this.call_hello.connect((request) => {
				request.reply(new OLLMrpc.Response());
			});
		}
	}

	class TestRpcGi : RpcTestAppBase
	{
		public TestRpcGi()
		{
			base("com.roojs.ollmchat.test-rpc-gi");
		}

		protected override string get_app_name()
		{
			return "test-rpc-gi";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Gi.register("Gio", "2.0");
			OLLMrpc.Bin.register("CallParam", typeof(OLLMrpc.CallParam));
			OLLMrpc.Request.register(
				"RPC-Daemon",
				new Hello(),
				typeof(OLLMrpc.CallParam)
			);
			var dir = GLib.DirUtils.make_tmp("ocrpc-gi-XXXXXX");
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
				method = "Gio-Menu.new"
			}, (obj, res) => {
				response = rpc.call.end(res);
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "new returned error");
			this.check(command_line, response.result.size == 1, "new returned no object");
			this.check(command_line, rpc.proxies.size == 1, "proxy not bound");
			var lease_id = (uint64) 0;
			foreach (var id in rpc.proxies.keys) {
				this.check(command_line, id != 0, "handle is 0");
				this.check(
					command_line,
					rpc.proxies.get(id) == response.result.get(0),
					"proxy is not result"
				);
				lease_id = (uint64) id;
			}
			response = null;
			var items_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Gio-Menu.get_n_items",
				lease_id = lease_id
			}, (obj, res) => {
				response = rpc.call.end(res);
				items_loop.quit();
			});
			items_loop.run();
			this.check(command_line, response.error == null, "get_n_items returned error");
			this.check(command_line, response.values.size == 1, "get_n_items returned no value");
			this.check(command_line, response.values.get(0).get_int() == 0, "empty menu is not 0");
			rpc.disconnect();
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcGi().run(args);
}
