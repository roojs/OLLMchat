/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Live-handle smoke — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	class TestRpcLiveHandles : RpcTestAppBase
	{
		public TestRpcLiveHandles()
		{
			base("com.roojs.ollmchat.test-rpc-live-handles");
		}

		protected override string get_app_name()
		{
			return "test-rpc-live-handles";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			var off = new OLLMrpc.Transport.Connection();
			this.check(command_line, !off.live_handles, "live_handles default is not false");
			this.check(command_line, off.leases.size == 0, "leases not empty with flag off");

			var conn = new OLLMrpc.Transport.Connection() {
				live_handles = true
			};
			OLLMrpc.Request.register(
				"RPC-Live-Remote",
				new OLLMrpc.Live.Remote()
			);
			var obj = new GLib.Object();
			var floor = obj.ref_count;
			var id = conn.export(obj);
			this.check(command_line, id != 0, "export returned 0");
			this.check(command_line, obj.ref_count == floor + 1, "export did not take a table ref");
			this.check(command_line, conn.export(obj) == id, "re-export changed id");

			var ref_req = new OLLMrpc.Request() {
				method = "RPC-Live-Remote.ref",
				lease_id = id,
				connection = conn
			};
			this.check(command_line, ref_req.dispatch(), "Remote.ref dispatch failed");
			this.check(command_line, obj.ref_count == floor + 2, "Remote.ref did not increment");

			var unref_req = new OLLMrpc.Request() {
				method = "RPC-Live-Remote.unref",
				lease_id = id,
				connection = conn
			};
			this.check(command_line, unref_req.dispatch(), "Remote.unref extra dispatch failed");
			this.check(command_line, obj.ref_count == floor + 1, "Remote.unref dropped below extra");
			this.check(command_line, unref_req.dispatch(), "Remote.unref export-hold dispatch failed");
			this.check(command_line, obj.ref_count == floor, "Remote.unref did not return to floor");
			this.check(command_line, !conn.leases.has_key((int) id), "export hold still in table");

			var pinned = new GLib.Object();
			var pinned_floor = pinned.ref_count;
			var pinned_id = conn.export(pinned);
			var extra_req = new OLLMrpc.Request() {
				method = "RPC-Live-Remote.ref",
				lease_id = pinned_id,
				connection = conn
			};
			this.check(command_line, extra_req.dispatch(), "stop-path Remote.ref dispatch failed");
			conn.stop();
			this.check(command_line, pinned.ref_count == pinned_floor, "stop did not return to floor");
			this.check(command_line, conn.leases.size == 0, "stop left leases");
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcLiveHandles().run(args);
}
