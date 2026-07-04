/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Codec smoke test — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class TestPair : OLLMrpc.Bin.Object
	{
		public string name { get; set; default = ""; }
		public int count { get; set; default = 0; }
	}

	/**
	 * Unsupported GObject props are omitted via default {@code bin_write_prop}
	 * returning false (same idea as JSON skipping a field).
	 */
	public class TestSkipDefault : OLLMrpc.Bin.Object
	{
		public string keep { get; set; default = ""; }
		public GLib.Object? extra { get; set; }
	}

	public static int main (string[] args)
	{
		var mem = new GLib.MemoryOutputStream.resizable ();
		var out_stream = new GLib.DataOutputStream (mem);

		var write_bin = new OLLMrpc.Bin.Stream (null, out_stream);
		write_bin.register ("TestPair", typeof (TestPair));
		write_bin.register ("TestSkipDefault", typeof (TestSkipDefault));

		var original = new TestPair () {
			name = "alpha",
			count = 42,
		};

		try {
			write_bin.write (original);
			out_stream.close ();

			var bytes = mem.steal_as_bytes ();
			var in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			var in_stream = new GLib.DataInputStream (in_base);

			var read_bin = new OLLMrpc.Bin.Stream (in_stream, null);
			read_bin.register ("TestPair", typeof (TestPair));
			read_bin.register ("TestSkipDefault", typeof (TestSkipDefault));

			var parsed = read_bin.parse () as TestPair;
			if (parsed == null) {
				GLib.printerr ("parse returned null\n");
				return 1;
			}
			if (parsed.name != "alpha" || parsed.count != 42) {
				GLib.printerr ("round-trip mismatch\n");
				return 1;
			}

			mem = new GLib.MemoryOutputStream.resizable ();
			out_stream = new GLib.DataOutputStream (mem);
			write_bin = new OLLMrpc.Bin.Stream (null, out_stream);
			write_bin.register ("TestSkipDefault", typeof (TestSkipDefault));

			var skip_src = new TestSkipDefault () {
				keep = "visible",
				extra = new GLib.Object (),
			};
			write_bin.write (skip_src);
			out_stream.close ();

			bytes = mem.steal_as_bytes ();
			in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			in_stream = new GLib.DataInputStream (in_base);
			read_bin = new OLLMrpc.Bin.Stream (in_stream, null);
			read_bin.register ("TestSkipDefault", typeof (TestSkipDefault));

			var skip_dst = read_bin.parse () as TestSkipDefault;
			if (skip_dst == null) {
				GLib.printerr ("skip parse returned null\n");
				return 1;
			}
			if (skip_dst.keep != "visible") {
				GLib.printerr ("skip keep mismatch\n");
				return 1;
			}
			if (skip_dst.extra != null) {
				GLib.printerr (
					"unsupported prop should stay null after round-trip\n"
				);
				return 1;
			}
		} catch (GLib.Error e) {
			GLib.printerr ("bin-test: %s\n", e.message);
			return 1;
		}

		return 0;
	}
}
