/*
 * POC B: connect(signal_handler) direct method ref — no lambda
 */

class Worker : GLib.Object
{
	public signal void rpc_do(GLib.Object request);

	public async void load_slow()
	{
		var f = GLib.File.new_for_path("/etc/hostname");
		yield f.read_async(Priority.DEFAULT, null);
	}

	construct
	{
		this.rpc_do.connect(this.on_rpc_do);
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
