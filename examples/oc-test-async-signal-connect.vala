/*
 * POC: Vala async RPC-style signal handlers (valac 0.56)
 *
 *   valac -o /tmp/oc-test-async-signal-connect --pkg=gio-2.0 \
 *     examples/oc-test-async-signal-connect.vala && /tmp/oc-test-async-signal-connect
 */

class Worker : GLib.Object
{
	public signal void rpc_do(GLib.Object request);

	public async void load_slow()
	{
		var f = GLib.File.new_for_path("/etc/hostname");
		yield f.read_async(Priority.DEFAULT, null);
		stdout.printf("load_slow ran\n");
	}

	construct
	{
		this.rpc_do.connect((request) => {
			this.on_rpc_do.begin(request);
		});
	}

	private async void on_rpc_do(GLib.Object request)
	{
		yield this.load_slow();
		stdout.printf("done request=%s\n", request.get_type().name());
	}

	public void emit_rpc()
	{
		this.rpc_do(this);
	}
}

void main()
{
	var w = new Worker();
	w.emit_rpc();
	var loop = new GLib.MainLoop(null, false);
	GLib.Timeout.add(200, () => {
		loop.quit();
		return false;
	});
	loop.run();
}
