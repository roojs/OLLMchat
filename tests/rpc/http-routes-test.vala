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
				"/v1/alarms/{id}", "GET", "get", "s", typeof(void), typeof(void),
				"/v1/alarms", "POST", "create", "o", typeof(AlarmCreate), typeof(Alarm),
				"/v1/alarms/{id}", "DELETE", "remove", "s", typeof(void), typeof(void)
			);
		}

		public void get(OLLMrpc.Request request, string id)
		{
			if (id == "") {
				var out_list = new AlarmList();
				foreach (var row in this.stored) {
					out_list.items.add(row);
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", out_list)
				});
				return;
			}
			foreach (var row in this.stored) {
				if (row.id != id) {
					continue;
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", row)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				error = OLLMrpc.RpcErrorCode.to_error(
					(int) OLLMrpc.RpcErrorCode.INVALID_PARAMS
				)
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

		public void remove(OLLMrpc.Request request, string id)
		{
			for (var i = 0; i < this.stored.size; i++) {
				if (this.stored.get(i).id != id) {
					continue;
				}
				this.stored.remove_at(i);
				request.reply(new OLLMrpc.Response());
				return;
			}
			request.reply(new OLLMrpc.Response() {
				error = OLLMrpc.RpcErrorCode.to_error(
					(int) OLLMrpc.RpcErrorCode.INVALID_PARAMS
				)
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

			var create_parser = new Json.Parser();
			create_parser.load_from_data(text, -1);
			var alarm_id = create_parser.get_root().get_object()
				.get_object_member("retval").get_string_member("id");

			var get_msg = new Soup.Message(
				"GET",
				"http://127.0.0.1:%u/v1/alarms/%s".printf(http.port, alarm_id)
			);
			status = 0u;
			text = "";
			loop = new GLib.MainLoop();
			session.send_and_read_async.begin(
				get_msg, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						var bytes = session.send_and_read_async.end(res);
						status = get_msg.status_code;
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
				"get status %u body=%s".printf(status, text)
			);
			this.check(
				command_line,
				text.contains("wake") && text.contains(alarm_id),
				"get missing alarm: %s".printf(text)
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

			var del_msg = new Soup.Message(
				"DELETE",
				"http://127.0.0.1:%u/v1/alarms/%s".printf(http.port, alarm_id)
			);
			status = 0u;
			text = "";
			loop = new GLib.MainLoop();
			session.send_and_read_async.begin(
				del_msg, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						var bytes = session.send_and_read_async.end(res);
						status = del_msg.status_code;
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
				"delete status %u body=%s".printf(status, text)
			);

			var get_gone = new Soup.Message(
				"GET",
				"http://127.0.0.1:%u/v1/alarms/%s".printf(http.port, alarm_id)
			);
			status = 0u;
			text = "";
			loop = new GLib.MainLoop();
			session.send_and_read_async.begin(
				get_gone, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						var bytes = session.send_and_read_async.end(res);
						status = get_gone.status_code;
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
				status == 200 && text.contains("error"),
				"get after delete expected error: %u %s".printf(status, text)
			);

			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpRoutes().run(args);
}
