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

		public signal void call_blob(OLLMrpc.Request request);

		construct
		{
			this.call_echo.connect((request) => {
				request.reply(new OLLMrpc.Response() {
					msg = request.values.get(0).get_string()
						+ request.values.get(1).get_int().to_string()
				});
			});
			this.call_blob.connect((request) => {
				var response = new OLLMrpc.Response();
				response.values.add(request.values.get(0));
				request.reply(response);
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
			var payload = new uint8[16];
			payload[4] = 10;
			payload[8] = 20;
			payload[12] = 30;
			var blob = GLib.Value(typeof(GLib.Bytes));
			blob.set_boxed(new GLib.Bytes(payload));
			var blob_req = new OLLMrpc.Request() {
				method = "RPC-Probe.blob"
			};
			blob_req.values.add(blob);
			response = null;
			var blob_loop = new GLib.MainLoop();
			rpc.call.begin(blob_req, (obj, res) => {
				response = rpc.call.end(res);
				blob_loop.quit();
			});
			blob_loop.run();
			this.check(command_line, response.error == null, "blob returned error");
			this.check(command_line, response.values.size == 1, "blob returned no value");
			var got = (GLib.Bytes) response.values.get(0).get_boxed();
			this.check(command_line, got.get_size() == 16, "blob size");
			this.check(command_line, got.get(0) == 0, "blob [0]");
			this.check(command_line, got.get(4) == 10, "blob [4]");
			var f_val = GLib.Value(typeof(float));
			f_val.set_float((float) 1.5);
			var f_req = new OLLMrpc.Request() {
				method = "RPC-Probe.blob"
			};
			f_req.values.add(f_val);
			response = null;
			var f_loop = new GLib.MainLoop();
			rpc.call.begin(f_req, (obj, res) => {
				response = rpc.call.end(res);
				f_loop.quit();
			});
			f_loop.run();
			this.check(command_line, response.error == null, "float returned error");
			this.check(command_line, response.values.get(0).get_float() == (float) 1.5, "float value");
			var d_val = GLib.Value(typeof(double));
			d_val.set_double(2.5);
			var d_req = new OLLMrpc.Request() {
				method = "RPC-Probe.blob"
			};
			d_req.values.add(d_val);
			response = null;
			var d_loop = new GLib.MainLoop();
			rpc.call.begin(d_req, (obj, res) => {
				response = rpc.call.end(res);
				d_loop.quit();
			});
			d_loop.run();
			this.check(command_line, response.error == null, "double returned error");
			this.check(command_line, response.values.get(0).get_double() == 2.5, "double value");
			var ints = new int[] { 1, 2, 3 };
			var i_req = new OLLMrpc.Request() {
				method = "RPC-Probe.blob"
			};
			i_req.values.add(GLib.Variant.new_fixed_array(
				new GLib.VariantType("i"), ints, sizeof(int)));
			response = null;
			var i_loop = new GLib.MainLoop();
			rpc.call.begin(i_req, (obj, res) => {
				response = rpc.call.end(res);
				i_loop.quit();
			});
			i_loop.run();
			this.check(command_line, response.error == null, "int[] returned error");
			unowned GLib.Variant got_var = response.values.get(0).get_variant();
			this.check(command_line, got_var.n_children() == 3, "int[] length");
			this.check(command_line, got_var.get_child_value(1).get_int32() == 2, "int[] [1]");
			rpc.disconnect();
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcValues().run(args);
}
