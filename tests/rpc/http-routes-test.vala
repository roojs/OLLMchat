/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTP path-route smoke — Alarm types here are NOT shipped in libocrpc.
 */

namespace RpcDummy.Alarm
{
	public class Alarm : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string id { get; set; default = ""; }
		public string name { get; set; default = ""; }

		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Alarm", typeof(Alarm));
		}
	}

	public class AlarmCreate : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string name { get; set; default = ""; }

		public static void rpc_register()
		{
			OLLMrpc.Bin.register("AlarmCreate", typeof(AlarmCreate));
		}
	}

	public class AlarmListQuery : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("AlarmListQuery", typeof(AlarmListQuery));
		}
	}

	public class AlarmList : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public Gee.ArrayList<Alarm> items {
			get; set; default = new Gee.ArrayList<Alarm>();
		}

		public static void rpc_register()
		{
			OLLMrpc.Bin.register("AlarmList", typeof(AlarmList));
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error {
			switch (prop.name) {
				case "items":
					this.bin_write_prop_array(ctx, prop.name, typeof(Alarm));
					return;
				default:
					this.bin_default_write_prop(ctx, prop);
					return;
			}
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error {
			switch (prop.name) {
				case "items":
					this.items = (Gee.ArrayList<Alarm>) this.read_anon_array(
						ctx, prop.name, type_byte, typeof(Alarm)
					);
					return;
				default:
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}

	public class Service : GLib.Object
	{
		private Gee.ArrayList<Alarm> stored = new Gee.ArrayList<Alarm>();
		private int next_id = 1;

		public static void rpc_register()
		{
			Alarm.rpc_register();
			AlarmList.rpc_register();
			AlarmCreate.rpc_register();
			AlarmListQuery.rpc_register();

			OLLMrpc.Http.routes("RPC-Alarm", typeof(Service),
				"/v1/alarms", "GET", "list", "", typeof(AlarmListQuery), typeof(AlarmList),
				"/v1/alarms", "POST", "create", "o", typeof(AlarmCreate), typeof(Alarm)
			);
		}

		public void list(OLLMrpc.Request request)
		{
			var out_list = new AlarmList();
			foreach (var row in this.stored) {
				out_list.items.add(row);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", out_list)
			});
		}

		public void create(OLLMrpc.Request request, AlarmCreate body)
		{
			var row = new Alarm() {
				id = "%d".printf(this.next_id),
				name = body.name
			};
			this.next_id++;
			this.stored.add(row);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", row)
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcHttpRoutes : RpcTestAppBase
	{
		public TestRpcHttpRoutes()
		{
			base("com.roojs.ollmchat.test-rpc-http-routes");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-routes";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			RpcDummy.Alarm.Service.rpc_register();
			OLLMrpc.Request.register("RPC-Alarm", new RpcDummy.Alarm.Service());

			var http = new OLLMrpc.Transport.HttpServer(0);
			this.check(command_line, http.start(), "http server start");

			var session = new Soup.Session();
			var create_msg = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/v1/alarms".printf(http.port)
			);
			create_msg.set_request_body_from_bytes(
				"application/json",
				new GLib.Bytes("{\"name\":\"wake\"}".data)
			);
			var status = 0u;
			var text = "";
			var loop = new GLib.MainLoop();
			session.send_and_read_async.begin(
				create_msg, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						var bytes = session.send_and_read_async.end(res);
						status = create_msg.status_code;
						text = (string) bytes.get_data();
					} catch (GLib.Error e) {
						text = e.message;
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(
				command_line,
				status == 200,
				"create status %u body=%s".printf(status, text)
			);
			this.check(
				command_line,
				text.contains("wake") && text.contains("\"id\""),
				"create missing alarm: %s".printf(text)
			);

			var list_msg = new Soup.Message(
				"GET",
				"http://127.0.0.1:%u/v1/alarms".printf(http.port)
			);
			status = 0u;
			text = "";
			loop = new GLib.MainLoop();
			session.send_and_read_async.begin(
				list_msg, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						var bytes = session.send_and_read_async.end(res);
						status = list_msg.status_code;
						text = (string) bytes.get_data();
					} catch (GLib.Error e) {
						text = e.message;
					}
					loop.quit();
				}
			);
			loop.run();
			this.check(
				command_line,
				status == 200,
				"list status %u body=%s".printf(status, text)
			);
			this.check(
				command_line,
				text.contains("wake") && text.contains("items"),
				"list missing alarms: %s".printf(text)
			);

			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpRoutes().run(args);
}
