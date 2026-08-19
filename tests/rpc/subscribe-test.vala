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
		public signal void closed();
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
			OLLMrpc.Live.RemoteParams.rpc_register();
			OLLMrpc.Live.SubscribeParams.rpc_register();
			OLLMrpc.Request.register(
				"RPC-Live-Remote",
				new OLLMrpc.Live.Remote(),
				typeof(OLLMrpc.Live.RemoteParams)
			);
			OLLMrpc.Request.register(
				"RPC-Live-Subscribe",
				new OLLMrpc.Live.Subscribe(),
				typeof(OLLMrpc.Live.SubscribeParams)
			);
			var probe = new Probe();
			var id = conn.export(probe);
			var sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.signal",
				param = new OLLMrpc.Live.SubscribeParams() {
					object_id = id,
					name = "notify::title"
				},
				connection = conn
			};
			this.check(command_line, sub.dispatch(), "Subscribe.signal notify dispatch failed");
			probe.title = "a";
			this.check(command_line, conn.writes == 1, "notify did not write one Notification");
			this.check(command_line, conn.last.method == "notify::title", "notify method mismatch");
			this.check(command_line, conn.last.id == (int) id, "notify id mismatch");
			this.check(command_line, conn.last.message == "a", "notify value mismatch");
			var unsub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.unsubscribe",
				param = new OLLMrpc.Live.SubscribeParams() {
					object_id = id,
					name = "notify::title"
				},
				connection = conn
			};
			this.check(command_line, unsub.dispatch(), "Subscribe.unsubscribe dispatch failed");
			probe.title = "b";
			this.check(command_line, conn.writes == 1, "unsubscribe did not silence notify");
			var closed_sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.signal",
				param = new OLLMrpc.Live.SubscribeParams() {
					object_id = id,
					name = "closed"
				},
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
				method = "RPC-Live-Subscribe.signal",
				param = new OLLMrpc.Live.SubscribeParams() {
					object_id = held_id,
					name = "notify::title"
				},
				connection = held
			};
			this.check(command_line, held_sub.dispatch(), "unref-path Subscribe.signal dispatch failed");
			var drop = new OLLMrpc.Request() {
				method = "RPC-Live-Remote.unref",
				param = new OLLMrpc.Live.RemoteParams() {
					object_id = held_id
				},
				connection = held
			};
			this.check(command_line, drop.dispatch(), "Remote.unref export-hold dispatch failed");
			held_probe.title = "d";
			this.check(command_line, held.writes == 0, "Remote.unref did not silence notify");
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcSubscribe().run(args);
}
