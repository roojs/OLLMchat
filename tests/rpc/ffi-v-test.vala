/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Ffi ''V'' GLib.Value pin — types NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class ValueEcho : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Value", typeof(ValueEcho),
				"hello", "",
				"set_relay_value", "bV"
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void set_relay_value(OLLMrpc.Request request, bool is_to, GLib.Value value)
		{
			if (!is_to) {
				request.reply(new OLLMrpc.Response() {
					msg = "want is_to"
				});
				return;
			}
			if (value.type() != typeof(float)) {
				request.reply(new OLLMrpc.Response() {
					msg = "want float"
				});
				return;
			}
			if (value.get_float() != (float) 1.25) {
				request.reply(new OLLMrpc.Response() {
					msg = "want 1.25"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcFfiV : RpcTestAppBase
	{
		public TestRpcFfiV()
		{
			base("com.roojs.ollmchat.test-rpc-ffi-v");
		}

		protected override string get_app_name()
		{
			return "test-rpc-ffi-v";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			RpcDummy.ValueEcho.rpc_register();
			OLLMrpc.Request.register("RPC-Value", new RpcDummy.ValueEcho());
			var dir = GLib.DirUtils.make_tmp("ocrpc-ffi-v-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock);
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock);
			var connected = false;
			var loop = new GLib.MainLoop();
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Value.hello"
			}, null, (obj, res) => {
				connected = rpc.connect.end(res);
				loop.quit();
			});
			loop.run();
			this.check(command_line, connected, "client connect failed");
			var held = GLib.Value(typeof(float));
			held.set_float((float) 1.25);
			var req = new OLLMrpc.Request() {
				method = "RPC-Value.set_relay_value",
				args = OLLMrpc.args("bV", true, held)
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
			this.check(command_line, response.error == null, "set_relay_value returned error");
			this.check(command_line, response.msg == "ok",
				"set_relay_value want ok got %s".printf(response.msg));
			listen.stop();
			GLib.FileUtils.unlink(sock);
			GLib.DirUtils.remove(dir);
		}
	}
}

int main(string[] args)
{
	var app = new OLLMrpcTests.TestRpcFfiV();
	return app.run(args);
}
