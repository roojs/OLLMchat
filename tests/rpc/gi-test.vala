/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Typelib remote new smoke — Gio types are not shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class TestActor : GLib.Object
	{
	}

	public class TestActorX11 : TestActor
	{
	}
}

namespace RpcDummy
{
	public class Hello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Hello),
				"hello", "",
				"actors", ""
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void actors(OLLMrpc.Request request)
		{
			var actor = new OLLMrpcTests.TestActorX11();
			request.connection.export(actor);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", actor)
			});
		}
	}
}

namespace OLLMrpcTests
{

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
			OLLMrpc.Bin.register("Test-Actor", typeof(TestActor));
			OLLMrpc.Bin.register_alias("Test-Actor", typeof(TestActorX11));
			RpcDummy.Hello.rpc_register();
			OLLMrpc.Request.register(
				"RPC-Daemon",
				new RpcDummy.Hello()
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
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "new returned error");
			this.check(command_line, response.retval.type() != GLib.Type.INVALID, "new returned no object");
			this.check(command_line, rpc.proxies.size == 1, "proxy not bound");
			var lease_id = (uint64) 0;
			foreach (var id in rpc.proxies.keys) {
				this.check(command_line, id != 0, "handle is 0");
				this.check(
					command_line,
					rpc.proxies.get(id) == response.retval.get_object(),
					"proxy is not retval"
				);
				lease_id = (uint64) id;
			}
			var live_obj = response.retval.get_object();
			void* stamped = live_obj.get_data("rpc-lid");
			this.check(
				command_line,
				stamped == (void*) lease_id,
				"proxy missing lease qdata"
			);
			response = null;
			var items_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Gio-Menu.get_n_items",
				lease_id = lease_id
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				items_loop.quit();
			});
			items_loop.run();
			this.check(command_line, response.error == null, "get_n_items returned error");
			this.check(command_line, response.retval.type() != GLib.Type.INVALID, "get_n_items returned no value");
			this.check(command_line, response.retval.get_int() == 0, "empty menu is not 0");
			response = null;
			var file_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Gio-File.new_for_path",
				args = OLLMrpc.args("s", GLib.Path.build_filename(dir, "missing"))
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				file_loop.quit();
			});
			file_loop.run();
			this.check(command_line, response.error == null, "new_for_path returned error");
			this.check(command_line, response.retval.type() != GLib.Type.INVALID, "new_for_path returned no object");
			var file_id = (uint64) 0;
			foreach (var id in rpc.proxies.keys) {
				if (id == lease_id) {
					continue;
				}
				file_id = (uint64) id;
			}
			this.check(command_line, file_id != 0, "file handle is 0");
			response = null;
			GLib.Error? read_error = null;
			var read_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Gio-File.read",
				lease_id = file_id
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					read_error = e;
				}
				read_loop.quit();
			});
			read_loop.run();
			this.check(command_line, read_error != null, "read of missing path did not throw");
			try {
				throw read_error;
			} catch (GLib.FileError e) {
				this.check(command_line, e.message != "Internal error", "message is Internal error");
				this.check(
					command_line,
					e.code != (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
					"gerror_code is INTERNAL_ERROR"
				);
			} catch (GLib.IOError e) {
				this.check(command_line, e.message != "Internal error", "message is Internal error");
				this.check(
					command_line,
					e.code != (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
					"gerror_code is INTERNAL_ERROR"
				);
			} catch (GLib.Error e) {
				this.check(command_line, false, "not a file/I/O error: " + e.message);
			}
			response = null;
			GLib.Error? params_error = null;
			var params_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Gio-Menu.get_n_items",
				lease_id = (uint64) 999999
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					params_error = e;
				}
				params_loop.quit();
			});
			params_loop.run();
			this.check(command_line, params_error != null, "bad lease_id did not throw");
			try {
				throw params_error;
			} catch (OLLMrpc.RpcErrorCode e) {
				this.check(
					command_line,
					e.code == (int) OLLMrpc.RpcErrorCode.INVALID_PARAMS,
					"gerror_code is not INVALID_PARAMS"
				);
			} catch (GLib.Error e) {
				this.check(command_line, false, "not RpcErrorCode: " + e.message);
			}
			response = null;
			var actors_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.actors"
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				actors_loop.quit();
			});
			actors_loop.run();
			this.check(command_line, response.error == null, "actors returned error");
			this.check(command_line, response.retval.type() != GLib.Type.INVALID, "actors returned no object");
			this.check(
				command_line,
				response.retval.get_object().get_type() == typeof(TestActor),
				"actors stub is not Test-Actor"
			);
			var actor = response.retval.get_object();
			void* actor_stamp = actor.get_data("rpc-lid");
			this.check(command_line, actor_stamp != null, "actors handle is 0");
			this.check(
				command_line,
				rpc.proxies.has_key((int) (uint64) actor_stamp)
					&& rpc.proxies.get((int) (uint64) actor_stamp) == actor,
				"actors proxy missing lease qdata"
			);
			rpc.disconnect();
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcGi().run(args);
}
