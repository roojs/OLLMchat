/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Live-handle smoke — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public static int main(string[] args)
	{
		var off = new OLLMrpc.Transport.Connection();
		if (off.live_handles) {
			GLib.printerr("live_handles default is not false\n");
			return 1;
		}
		if (off.leases.size != 0) {
			GLib.printerr("leases not empty with flag off\n");
			return 1;
		}

		var conn = new OLLMrpc.Transport.Connection() {
			live_handles = true
		};
		OLLMrpc.Live.RemoteParams.rpc_register();
		OLLMrpc.Request.register(
			"Remote",
			new OLLMrpc.Live.Remote(),
			typeof(OLLMrpc.Live.RemoteParams)
		);
		var obj = new GLib.Object();
		var floor = obj.ref_count;
		var id = conn.export(obj);
		if (id == 0) {
			GLib.printerr("export returned 0\n");
			return 1;
		}
		if (obj.ref_count != floor + 1) {
			GLib.printerr("export did not take a table ref\n");
			return 1;
		}
		if (conn.export(obj) != id) {
			GLib.printerr("re-export changed id\n");
			return 1;
		}

		var ref_req = new OLLMrpc.Request() {
			method = "Remote.ref",
			param = new OLLMrpc.Live.RemoteParams() {
				object_id = id
			},
			connection = conn
		};
		if (!ref_req.dispatch()) {
			GLib.printerr("Remote.ref dispatch failed\n");
			return 1;
		}
		if (obj.ref_count != floor + 2) {
			GLib.printerr("Remote.ref did not increment\n");
			return 1;
		}

		var unref_req = new OLLMrpc.Request() {
			method = "Remote.unref",
			param = new OLLMrpc.Live.RemoteParams() {
				object_id = id
			},
			connection = conn
		};
		if (!unref_req.dispatch()) {
			GLib.printerr("Remote.unref extra dispatch failed\n");
			return 1;
		}
		if (obj.ref_count != floor + 1) {
			GLib.printerr("Remote.unref dropped below extra\n");
			return 1;
		}
		if (!unref_req.dispatch()) {
			GLib.printerr("Remote.unref export-hold dispatch failed\n");
			return 1;
		}
		if (obj.ref_count != floor) {
			GLib.printerr("Remote.unref did not return to floor\n");
			return 1;
		}
		if (conn.leases.has_key((int) id)) {
			GLib.printerr("export hold still in table\n");
			return 1;
		}

		var pinned = new GLib.Object();
		var pinned_floor = pinned.ref_count;
		var pinned_id = conn.export(pinned);
		var extra_req = new OLLMrpc.Request() {
			method = "Remote.ref",
			param = new OLLMrpc.Live.RemoteParams() {
				object_id = pinned_id
			},
			connection = conn
		};
		if (!extra_req.dispatch()) {
			GLib.printerr("stop-path Remote.ref dispatch failed\n");
			return 1;
		}
		conn.stop();
		if (pinned.ref_count != pinned_floor) {
			GLib.printerr("stop did not return to floor\n");
			return 1;
		}
		if (conn.leases.size != 0) {
			GLib.printerr("stop left leases\n");
			return 1;
		}
		return 0;
	}
}
