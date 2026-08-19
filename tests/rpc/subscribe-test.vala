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

		public override void write(GLib.Object gobject)
		{
			if (!(gobject is OLLMrpc.Notification)) {
				return;
			}
			this.last = (OLLMrpc.Notification) gobject;
			this.writes++;
		}
	}

	public static int main(string[] args)
	{
		var conn = new Capture() {
			live_handles = true
		};
		OLLMrpc.Live.RemoteParams.rpc_register();
		OLLMrpc.Live.SubscribeParams.rpc_register();
		OLLMrpc.Request.register("RPC-Live-Remote", new OLLMrpc.Live.Remote(), typeof(OLLMrpc.Live.RemoteParams));
		OLLMrpc.Request.register("RPC-Live-Subscribe", new OLLMrpc.Live.Subscribe(), typeof(OLLMrpc.Live.SubscribeParams));
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
		if (!sub.dispatch()) {
			GLib.printerr("Subscribe.signal notify dispatch failed\n");
			return 1;
		}
		probe.title = "a";
		if (conn.writes != 1) {
			GLib.printerr("notify did not write one Notification\n");
			return 1;
		}
		if (conn.last.method != "notify::title") {
			GLib.printerr("notify method mismatch\n");
			return 1;
		}
		if (conn.last.id != (int) id) {
			GLib.printerr("notify id mismatch\n");
			return 1;
		}
		if (conn.last.message != "a") {
			GLib.printerr("notify value mismatch\n");
			return 1;
		}
		var unsub = new OLLMrpc.Request() {
			method = "RPC-Live-Subscribe.unsubscribe",
			param = new OLLMrpc.Live.SubscribeParams() {
				object_id = id,
				name = "notify::title"
			},
			connection = conn
		};
		if (!unsub.dispatch()) {
			GLib.printerr("Subscribe.unsubscribe dispatch failed\n");
			return 1;
		}
		probe.title = "b";
		if (conn.writes != 1) {
			GLib.printerr("unsubscribe did not silence notify\n");
			return 1;
		}
		var closed_sub = new OLLMrpc.Request() {
			method = "RPC-Live-Subscribe.signal",
			param = new OLLMrpc.Live.SubscribeParams() {
				object_id = id,
				name = "closed"
			},
			connection = conn
		};
		if (!closed_sub.dispatch()) {
			GLib.printerr("Subscribe.signal closed dispatch failed\n");
			return 1;
		}
		probe.closed();
		if (conn.writes != 2) {
			GLib.printerr("closed did not write one Notification\n");
			return 1;
		}
		if (conn.last.method != "closed") {
			GLib.printerr("closed method mismatch\n");
			return 1;
		}
		if (!sub.dispatch()) {
			GLib.printerr("Subscribe.signal notify re-sub dispatch failed\n");
			return 1;
		}
		conn.stop();
		probe.title = "c";
		if (conn.writes != 2) {
			GLib.printerr("stop did not silence notify\n");
			return 1;
		}

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
		if (!held_sub.dispatch()) {
			GLib.printerr("unref-path Subscribe.signal dispatch failed\n");
			return 1;
		}
		var drop = new OLLMrpc.Request() {
			method = "RPC-Live-Remote.unref",
			param = new OLLMrpc.Live.RemoteParams() {
				object_id = held_id
			},
			connection = held
		};
		if (!drop.dispatch()) {
			GLib.printerr("Remote.unref export-hold dispatch failed\n");
			return 1;
		}
		held_probe.title = "d";
		if (held.writes != 0) {
			GLib.printerr("Remote.unref did not silence notify\n");
			return 1;
		}

		var off = new OLLMrpc.Transport.Connection();
		var off_req = new OLLMrpc.Request() {
			method = "RPC-Live-Subscribe.signal",
			param = new OLLMrpc.Live.SubscribeParams() {
				object_id = 1,
				name = "notify::title"
			},
			connection = off
		};
		if (!off_req.dispatch()) {
			GLib.printerr("flag-off Subscribe.signal dispatch failed\n");
			return 1;
		}
		if (off.signal_subs.size != 0) {
			GLib.printerr("flag off still stored a sub\n");
			return 1;
		}
		return 0;
	}
}
