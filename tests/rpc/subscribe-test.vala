/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Subscribe smoke — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class Probe : GLib.Object
	{
		public string title { get; set; default = ""; }
		public bool visible { get; set; default = false; }
		public signal void closed();
		public signal void pinged(string payload);
	}

	public class Capture : OLLMrpc.Transport.Connection
	{
		public OLLMrpc.Notification last { get; set; default = new OLLMrpc.Notification(); }
		public int writes { get; set; default = 0; }

		public override void write(
			GLib.Object gobject,
			OLLMrpc.Live.Buffer? buffer = null
		)
		{
			if (!(gobject is OLLMrpc.Notification)) {
				return;
			}
			this.last = (OLLMrpc.Notification) gobject;
			this.writes++;
		}
	}

	class TestRpcSubscribe : RpcTestAppBase
	{
		public TestRpcSubscribe()
		{
			base("com.roojs.ollmchat.test-rpc-subscribe");
		}

		protected override string get_app_name()
		{
			return "test-rpc-subscribe";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			var conn = new Capture() {
				live_handles = true
			};
			OLLMrpc.Live.Remote.rpc_register();
			OLLMrpc.Live.Subscribe.rpc_register();
			OLLMrpc.Request.register_live("RPC-Live-Remote", new OLLMrpc.Live.Remote());
			OLLMrpc.Request.register_live("RPC-Live-Subscribe", new OLLMrpc.Live.Subscribe());
			var probe = new Probe();
			var id = conn.export(probe);
			var sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = id,
				args = OLLMrpc.args("s", "notify::title"),
				connection = conn
			};
			this.check(command_line, sub.dispatch(), "Subscribe.signal notify dispatch failed");
			probe.title = "a";
			this.check(command_line, conn.writes == 1, "notify did not write one Notification");
			this.check(command_line, conn.last.method == "notify::title", "notify method mismatch");
			this.check(command_line, conn.last.id == (int) id, "notify id mismatch");
			this.check(command_line, conn.last.message == "", "notify must not stuff message");
			this.check(command_line, conn.last.args.size == 1, "notify args missing");
			this.check(command_line, conn.last.args.get(0).get_string() == "a", "notify value mismatch");
			var unsub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.unsubscribe",
				lease_id = id,
				args = OLLMrpc.args("s", "notify::title"),
				connection = conn
			};
			this.check(command_line, unsub.dispatch(), "Subscribe.unsubscribe dispatch failed");
			probe.title = "b";
			this.check(command_line, conn.writes == 1, "unsubscribe did not silence notify");
			var closed_sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = id,
				args = OLLMrpc.args("s", "closed"),
				connection = conn
			};
			this.check(command_line, closed_sub.dispatch(), "Subscribe.signal closed dispatch failed");
			probe.closed();
			this.check(command_line, conn.writes == 2, "closed did not write one Notification");
			this.check(command_line, conn.last.method == "closed", "closed method mismatch");
			this.check(command_line, sub.dispatch(), "Subscribe.signal notify re-sub dispatch failed");
			conn.stop();
			probe.title = "c";
			this.check(command_line, conn.writes == 2, "stop did not silence notify");

			var held = new Capture() {
				live_handles = true
			};
			var held_probe = new Probe();
			var held_id = held.export(held_probe);
			var held_sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = held_id,
				args = OLLMrpc.args("s", "notify::title"),
				connection = held
			};
			this.check(command_line, held_sub.dispatch(), "unref-path Subscribe.signal dispatch failed");
			var drop = new OLLMrpc.Request() {
				method = "RPC-Live-Remote.rpc_unref",
				lease_id = held_id,
				connection = held
			};
			this.check(command_line, drop.dispatch(), "Remote.unref export-hold dispatch failed");
			held_probe.title = "d";
			this.check(command_line, held.writes == 0, "Remote.unref did not silence notify");

			var pinged_conn = new Capture() {
				live_handles = true
			};
			var pinged_probe = new Probe();
			var pinged_id = pinged_conn.export(pinged_probe);
			var pinged_sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = pinged_id,
				args = OLLMrpc.args("s", "pinged"),
				connection = pinged_conn
			};
			this.check(command_line, pinged_sub.dispatch(), "Subscribe.signal pinged dispatch failed");
			pinged_probe.pinged("hello");
			this.check(command_line, pinged_conn.writes == 1, "pinged did not write one Notification");
			this.check(command_line, pinged_conn.last.method == "pinged", "pinged method mismatch");
			this.check(command_line, pinged_conn.last.args.size == 1, "pinged args missing");
			this.check(command_line, pinged_conn.last.args.get(0).get_string() == "hello", "pinged payload mismatch");
			this.check(command_line, pinged_conn.last.message == "", "pinged must not stuff message");

			var vis_conn = new Capture() {
				live_handles = true
			};
			var vis_probe = new Probe();
			var vis_id = vis_conn.export(vis_probe);
			var vis_sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = vis_id,
				args = OLLMrpc.args("s", "notify::visible"),
				connection = vis_conn
			};
			this.check(command_line, vis_sub.dispatch(), "Subscribe.signal notify::visible dispatch failed");
			vis_probe.visible = true;
			this.check(command_line, vis_conn.writes == 1, "notify::visible did not write one Notification");
			this.check(command_line, vis_conn.last.method == "notify::visible", "notify::visible method mismatch");
			this.check(command_line, vis_conn.last.message == "", "notify::visible must not stuff message");
			this.check(command_line, vis_conn.last.args.size == 1, "notify::visible args missing");
			this.check(command_line, vis_conn.last.args.get(0).holds(typeof(bool)), "notify::visible arg is not boolean");
			this.check(command_line, vis_conn.last.args.get(0).get_boolean(), "notify::visible value mismatch");
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcSubscribe().run(args);
}
