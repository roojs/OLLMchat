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

	public class TestParent : OLLMrpc.Bin.Object
	{
		public string label { get; set; default = ""; }
		public TestPair? child { get; set; }
	}

	/**
	 * Transient props are omitted by overriding {@code bin_write_prop}.
	 */
	public class TestSkipDefault : OLLMrpc.Bin.Object
	{
		public string keep { get; set; default = ""; }
		public GLib.Object? extra { get; set; }

		public override void bin_write_prop (
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			if (prop.name == "extra") {
				return;
			}
			base.bin_write_prop (ctx, prop);
		}
	}

	public static int main (string[] args)
	{
		var mem = new GLib.MemoryOutputStream.resizable ();
		var out_stream = new GLib.DataOutputStream (mem);

		var write_bin = new OLLMrpc.Bin.Stream (null, out_stream);
		write_bin.register ("TestPair", typeof (TestPair));
		write_bin.register ("TestSkipDefault", typeof (TestSkipDefault));
		write_bin.register ("TestParent", typeof (TestParent));

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
			read_bin.register ("TestSkipDefault", typeof (TestSkipDefault));
			read_bin.register ("TestPair", typeof (TestPair));

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
			write_bin.register ("TestPair", typeof (TestPair));
			write_bin.register ("TestParent", typeof (TestParent));

			var nested_src = new TestParent () {
				label = "parent",
				child = new TestPair () {
					name = "nested",
					count = 7,
				},
			};
			write_bin.write (nested_src);
			out_stream.close ();

			bytes = mem.steal_as_bytes ();
			in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			in_stream = new GLib.DataInputStream (in_base);
			read_bin = new OLLMrpc.Bin.Stream (in_stream, null);
			read_bin.register ("TestParent", typeof (TestParent));
			read_bin.register ("TestPair", typeof (TestPair));

			var nested_dst = read_bin.parse () as TestParent;
			if (nested_dst == null) {
				GLib.printerr ("nested parse returned null\n");
				return 1;
			}
			if (nested_dst.label != "parent") {
				GLib.printerr ("nested label mismatch\n");
				return 1;
			}
			if (nested_dst.child == null) {
				GLib.printerr ("nested child is null\n");
				return 1;
			}
			if (
				nested_dst.child.name != "nested"
				|| nested_dst.child.count != 7
			) {
				GLib.printerr ("nested child mismatch\n");
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
