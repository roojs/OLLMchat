/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Client proxy apply smoke — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class Probe : GLib.Object
	{
		public string title { get; set; default = ""; }
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
				null
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}
	}
}

namespace OLLMrpcTests
{

	class TestRpcProxies : RpcTestAppBase
	{
		public TestRpcProxies()
		{
			base("com.roojs.ollmchat.test-rpc-proxies");
		}

		protected override string get_app_name()
		{
			return "test-rpc-proxies";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			RpcDummy.Hello.rpc_register();
			OLLMrpc.Request.register(
				"RPC-Daemon",
				new RpcDummy.Hello()
			);
			var dir = GLib.DirUtils.make_tmp("ocrpc-proxies-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock) {
				live_handles = true
			};
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock) {
				live_handles = true
			};
			var probe = new Probe();
			rpc.proxies.set(7, probe);
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
			var seen = "";
			rpc.notification.connect((notif) => {
				seen = notif.message;
			});
			var apply_loop = new GLib.MainLoop();
			probe.notify["title"].connect(() => {
				apply_loop.quit();
			});
			var timeout_id = GLib.Timeout.add(2000, () => {
				apply_loop.quit();
				return false;
			});
			listen.broadcast(new OLLMrpc.Notification() {
				method = "notify::title",
				id = 7,
				message = "a"
			});
			if (probe.title != "a") {
				apply_loop.run();
			}
			GLib.Source.remove(timeout_id);
			this.check(command_line, probe.title == "a", "proxy title not applied");
			this.check(command_line, seen == "a", "notification signal not emitted");
			rpc.proxies.unset(7);
			var unbound_loop = new GLib.MainLoop();
			var unbound_timeout = GLib.Timeout.add(2000, () => {
				unbound_loop.quit();
				return false;
			});
			listen.broadcast(new OLLMrpc.Notification() {
				method = "notify::title",
				id = 7,
				message = "b"
			});
			if (seen != "b") {
				unbound_loop.run();
			}
			GLib.Source.remove(unbound_timeout);
			this.check(command_line, seen == "b", "unbound notification not emitted");
			this.check(command_line, probe.title == "a", "unbound id still applied");
			rpc.disconnect();
			this.check(command_line, rpc.proxies.size == 0, "disconnect left proxies");
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcProxies().run(args);
}
