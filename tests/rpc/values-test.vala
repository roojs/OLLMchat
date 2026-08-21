/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Positional Request.values smoke — types here are NOT shipped in libocrpc.
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

	public class Probe : GLib.Object
	{
		public signal void call_echo(OLLMrpc.Request request);

		construct
		{
			this.call_echo.connect((request) => {
				request.reply(new OLLMrpc.Response() {
					msg = request.values.get(0).get_string()
						+ request.values.get(1).get_int().to_string()
				});
			});
		}
	}

	class TestRpcValues : RpcTestAppBase
	{
		public TestRpcValues()
		{
			base("com.roojs.ollmchat.test-rpc-values");
		}

		protected override string get_app_name()
		{
			return "test-rpc-values";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Bin.register("CallParam", typeof(OLLMrpc.CallParam));
			OLLMrpc.Request.register(
				"RPC-Daemon",
				new Hello(),
				typeof(OLLMrpc.CallParam)
			);
			OLLMrpc.Request.register(
				"RPC-Probe",
				new Probe(),
				typeof(OLLMrpc.CallParam)
			);
			var dir = GLib.DirUtils.make_tmp("ocrpc-values-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock);
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock);
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
			var text = GLib.Value(typeof(string));
			text.set_string("n");
			var number = GLib.Value(typeof(int));
			number.set_int(3);
			var req = new OLLMrpc.Request() {
				method = "RPC-Probe.echo"
			};
			req.values.add(text);
			req.values.add(number);
			OLLMrpc.Response? response = null;
			var call_loop = new GLib.MainLoop();
			rpc.call.begin(req, (obj, res) => {
				response = rpc.call.end(res);
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "echo returned error");
			this.check(command_line, response.msg == "n3", "echo values not applied");
			rpc.disconnect();
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcValues().run(args);
}
