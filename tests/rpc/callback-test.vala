/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Callback smoke — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class Capture : OLLMrpc.Transport.Connection
	{
		public OLLMrpc.Notification last { get; set; default = new OLLMrpc.Notification(); }
		public OLLMrpc.Live.Invoke last_invoke { get; set; default = new OLLMrpc.Live.Invoke(); }
		public int writes { get; set; default = 0; }

		public override void write(
			GLib.Object gobject,
			OLLMrpc.Live.Buffer? buffer = null
		)
		{
			if (gobject is OLLMrpc.Live.Invoke) {
				this.last_invoke = (OLLMrpc.Live.Invoke) gobject;
				this.writes++;
				return;
			}
			if (!(gobject is OLLMrpc.Notification)) {
				return;
			}
			this.last = (OLLMrpc.Notification) gobject;
			this.writes++;
		}
	}

	class TestRpcCallback : RpcTestAppBase
	{
		public TestRpcCallback()
		{
			base("com.roojs.ollmchat.test-rpc-callback");
		}

		protected override string get_app_name()
		{
			return "test-rpc-callback";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			var conn = new Capture() {
				live_handles = true
			};
			OLLMrpc.Live.Callback.rpc_register();
			OLLMrpc.Request.register_live("RPC-Live-Callback", new OLLMrpc.Live.Callback());
			var reg = new OLLMrpc.Request() {
				method = "RPC-Live-Callback.register",
				connection = conn
			};
			this.check(command_line, reg.dispatch(), "Callback.register dispatch failed");
			this.check(command_line, conn.callbacks.size == 1, "register did not store one row");
			var id = conn.next_handle - 1;
			var row = conn.callbacks.get(id);
			var probe = new GLib.Object();
			GLib.Idle.add(() => {
				var ack = new OLLMrpc.Request() {
					method = "RPC-Live-Callback.reply",
					args = OLLMrpc.args("t", (uint64) row.reply_id),
					connection = conn
				};
				ack.dispatch();
				return false;
			});
			row.emit(OLLMrpc.args("tu", conn.export(probe), 7));
			this.check(command_line, conn.writes == 1, "emit did not write one Invoke");
			this.check(command_line, conn.last_invoke.id == id, "invoke id mismatch");
			this.check(command_line, conn.last_invoke.args.size == 2, "invoke args size mismatch");
			var cont = new OLLMrpc.Request() {
				method = "RPC-Live-Callback.register",
				connection = conn
			};
			this.check(command_line, cont.dispatch(), "second Callback.register dispatch failed");
			var walk_id = conn.next_handle - 1;
			var walk_row = conn.callbacks.get(walk_id);
			GLib.Idle.add(() => {
				var yes = GLib.Value(typeof(bool));
				yes.set_boolean(true);
				var ack = new OLLMrpc.Request() {
					method = "RPC-Live-Callback.reply",
					connection = conn
				};
				ack.args = OLLMrpc.args("t", (uint64) walk_row.reply_id);
				ack.args.add(yes);
				ack.dispatch();
				return false;
			});
			walk_row.emit(OLLMrpc.args("t", conn.export(probe)));
			this.check(command_line, walk_row.reply_args.size == 1, "bool reply missing");
			this.check(command_line, walk_row.reply_args.get(0).get_boolean(), "bool reply was not true");
			var drop = new OLLMrpc.Request() {
				method = "RPC-Live-Callback.unregister",
				args = OLLMrpc.args("t", (uint64) id),
				connection = conn
			};
			this.check(command_line, drop.dispatch(), "Callback.unregister dispatch failed");
			this.check(command_line, !conn.callbacks.has_key(id), "unregister did not drop the row");
			OLLMrpc.Live.Hook.drop(walk_row);
			this.check(command_line, !conn.callbacks.has_key(walk_id), "drop did not unset the row");
			this.check(command_line, conn.last.method == "RPC-Live-Callback.unregister", "drop forget method mismatch");
			var held = new OLLMrpc.Request() {
				method = "RPC-Live-Callback.register",
				connection = conn
			};
			this.check(command_line, held.dispatch(), "stop-path Callback.register dispatch failed");
			var held_row = conn.callbacks.get(conn.next_handle - 1);
			GLib.Idle.add(() => {
				conn.stop();
				return false;
			});
			held_row.emit(OLLMrpc.args("u", 1));
			this.check(command_line, conn.callbacks.size == 0, "stop did not clear callbacks");
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcCallback().run(args);
}
