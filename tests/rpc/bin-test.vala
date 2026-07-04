/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Codec smoke test — types here are NOT shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class TestPair : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string name { get; set; default = ""; }
		public int count { get; set; default = 0; }
	}

	public class TestParent : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string label { get; set; default = ""; }
		public TestPair? child { get; set; }
	}

	public class TestPaths : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string[] paths { get; set; default = {}; }
	}

	public class TestListBag : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string label { get; set; default = ""; }
		public Gee.ArrayList<TestPair> items {
			get; set; default = new Gee.ArrayList<TestPair> ();
		}

		public override void bin_write_prop (
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "items":
					var val = GLib.Value (prop.value_type);
					this.get_property (prop.name, ref val);
					var list = (Gee.ArrayList<TestPair>) val;
					ctx.write_tag (prop.name);
					ctx.write_gtype (
						typeof (TestPair),
						(uint8) GLib.Type.OBJECT | 0x80
					);
					if (list.size < 128) {
						ctx.out_stream.put_byte ((uint8) list.size);
					} else {
						ctx.out_stream.put_byte (
							(uint8) (0x80 | ((list.size >> 8) & 0x7F))
						);
						ctx.out_stream.put_byte (
							(uint8) (list.size & 0xFF)
						);
					}
					foreach (var child in list) {
						child.bin_write (ctx);
					}
					return;
				default:
					base.bin_write_prop (ctx, prop);
					return;
			}
		}

		public override void bin_read_prop (
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "items":
					if ((type_byte & 0x7F) != GLib.Type.OBJECT
						|| (type_byte & 0x80) == 0) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY (
							"prop '%s' expected object array",
							prop.name
						);
					}
					if (ctx.read_gtype () != typeof (TestPair)) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY (
							"prop '%s' expected TestPair elements",
							prop.name
						);
					}
					var count = (uint) ctx.in_stream.read_byte ();
					if ((count & 0x80) != 0) {
						count = ((count & 0x7F) << 8)
							| ctx.in_stream.read_byte ();
					}
					var list = new Gee.ArrayList<TestPair> ();
					for (var i = 0; i < count; i++) {
						var child = (TestPair) GLib.Object.new (
							typeof (TestPair)
						);
						child.bin_read (ctx);
						list.add (child);
					}
					var val = GLib.Value (prop.value_type);
					val.set_object (list);
					this.set_property (prop.name, val);
					return;
				default:
					base.bin_read_prop (ctx, prop, type_byte);
					return;
			}
		}
	}

	/**
	 * Transient props are omitted by overriding {@code bin_write}.
	 */
	public class TestSkipDefault : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string keep { get; set; default = ""; }
		public GLib.Object? extra { get; set; }

		public override void bin_write (OLLMrpc.Bin.Stream ctx) throws GLib.Error
		{
			unowned GLib.ObjectClass obj_class = this.get_class ();
			GLib.ParamSpec[] properties = obj_class.list_properties ();

			foreach (var prop in properties) {
				if (prop.name == "g-type-instance" || prop.name == "ref-count") {
					continue;
				}
				if (prop.name == "extra") {
					continue;
				}
				this.bin_write_prop (ctx, prop);
			}
			ctx.out_stream.put_uint16 (OLLMrpc.Bin.Stream.TOKEN_END);
		}
	}

	public static int main (string[] args)
	{
		var mem = new GLib.MemoryOutputStream.resizable ();
		var out_stream = new GLib.DataOutputStream (mem);

		var write_bin = new OLLMrpc.Bin.Stream (null, out_stream);

		var original = new TestPair () {
			name = "alpha",
			count = 42,
		};

		try {
			OLLMrpc.Bin.Stream.register ("TestPair", typeof (TestPair));
			OLLMrpc.Bin.Stream.register (
				"TestSkipDefault",
				typeof (TestSkipDefault)
			);
			OLLMrpc.Bin.Stream.register ("TestParent", typeof (TestParent));
			OLLMrpc.Bin.Stream.register ("TestPaths", typeof (TestPaths));
			OLLMrpc.Bin.Stream.register ("TestListBag", typeof (TestListBag));

			write_bin.write (original);
			out_stream.close ();

			var bytes = mem.steal_as_bytes ();
			var in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			var in_stream = new GLib.DataInputStream (in_base);

			var read_bin = new OLLMrpc.Bin.Stream (in_stream, null);

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

			mem = new GLib.MemoryOutputStream.resizable ();
			out_stream = new GLib.DataOutputStream (mem);
			write_bin = new OLLMrpc.Bin.Stream (null, out_stream);

			var paths_src = new TestPaths () {
				paths = { "a", "bb", "" },
			};
			write_bin.write (paths_src);
			out_stream.close ();

			bytes = mem.steal_as_bytes ();
			in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			in_stream = new GLib.DataInputStream (in_base);
			read_bin = new OLLMrpc.Bin.Stream (in_stream, null);

			var paths_dst = read_bin.parse () as TestPaths;
			if (paths_dst == null) {
				GLib.printerr ("paths parse returned null\n");
				return 1;
			}
			if (paths_dst.paths.length != 3) {
				GLib.printerr ("paths length mismatch\n");
				return 1;
			}
			if (
				paths_dst.paths[0] != "a"
				|| paths_dst.paths[1] != "bb"
				|| paths_dst.paths[2] != ""
			) {
				GLib.printerr ("paths element mismatch\n");
				return 1;
			}

			mem = new GLib.MemoryOutputStream.resizable ();
			out_stream = new GLib.DataOutputStream (mem);
			write_bin = new OLLMrpc.Bin.Stream (null, out_stream);

			var long_name = string.nfill (130, 'x');
			var long_src = new TestPair () {
				name = long_name,
				count = 1,
			};
			write_bin.write (long_src);
			out_stream.close ();

			bytes = mem.steal_as_bytes ();
			in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			in_stream = new GLib.DataInputStream (in_base);
			read_bin = new OLLMrpc.Bin.Stream (in_stream, null);

			var long_dst = read_bin.parse () as TestPair;
			if (long_dst == null) {
				GLib.printerr ("long string parse returned null\n");
				return 1;
			}
			if (long_dst.name != long_name || long_dst.count != 1) {
				GLib.printerr ("long string round-trip mismatch\n");
				return 1;
			}

			mem = new GLib.MemoryOutputStream.resizable ();
			out_stream = new GLib.DataOutputStream (mem);
			write_bin = new OLLMrpc.Bin.Stream (null, out_stream);

			var huge = string.nfill (40000, 'z');
			var huge_src = new TestPair () {
				name = huge,
				count = 2,
			};
			write_bin.write (huge_src);
			out_stream.close ();

			bytes = mem.steal_as_bytes ();
			in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			in_stream = new GLib.DataInputStream (in_base);
			read_bin = new OLLMrpc.Bin.Stream (in_stream, null);

			var huge_dst = read_bin.parse () as TestPair;
			if (huge_dst == null) {
				GLib.printerr ("huge string parse returned null\n");
				return 1;
			}
			if (huge_dst.name != huge || huge_dst.count != 2) {
				GLib.printerr ("huge string round-trip mismatch\n");
				return 1;
			}

			mem = new GLib.MemoryOutputStream.resizable ();
			out_stream = new GLib.DataOutputStream (mem);
			write_bin = new OLLMrpc.Bin.Stream (null, out_stream);

			var list_src = new TestListBag () {
				label = "bag",
				items = new Gee.ArrayList<TestPair> (),
			};
			list_src.items.add (new TestPair () {
				name = "one",
				count = 1,
			});
			list_src.items.add (new TestPair () {
				name = "two",
				count = 2,
			});
			write_bin.write (list_src);
			out_stream.close ();

			bytes = mem.steal_as_bytes ();
			in_base = new GLib.MemoryInputStream.from_bytes (bytes);
			in_stream = new GLib.DataInputStream (in_base);
			read_bin = new OLLMrpc.Bin.Stream (in_stream, null);

			var list_dst = read_bin.parse () as TestListBag;
			if (list_dst == null) {
				GLib.printerr ("list bag parse returned null\n");
				return 1;
			}
			if (list_dst.label != "bag") {
				GLib.printerr ("list bag label mismatch\n");
				return 1;
			}
			if (list_dst.items.size != 2) {
				GLib.printerr ("list bag items size mismatch\n");
				return 1;
			}
			if (
				list_dst.items.get (0).name != "one"
				|| list_dst.items.get (0).count != 1
				|| list_dst.items.get (1).name != "two"
				|| list_dst.items.get (1).count != 2
			) {
				GLib.printerr ("list bag element mismatch\n");
				return 1;
			}
		} catch (GLib.Error e) {
			GLib.printerr ("bin-test: %s\n", e.message);
			return 1;
		}

		return 0;
	}
}
