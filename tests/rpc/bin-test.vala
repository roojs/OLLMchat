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
			get; set; default = new Gee.ArrayList<TestPair>();
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "items":
					var val = GLib.Value(prop.value_type);
					this.get_property(prop.name, ref val);
					var list = (Gee.ArrayList<TestPair>) val;
					ctx.write_tag(prop.name);
					ctx.write_gtype(typeof(TestPair),
						(uint8) GLib.Type.OBJECT | 0x80);
					if (list.size < 128) {
						ctx.out_stream.put_byte((uint8) list.size);
					} else {
						ctx.out_stream.put_byte(
							(uint8) (0x80 | ((list.size >> 8) & 0x7F)));
						ctx.out_stream.put_byte((uint8) (list.size & 0xFF));
					}
					foreach (var child in list) {
						child.bin_write(ctx);
					}
					return;
				default:
					bin_default_write_prop(ctx, prop);
					return;
			}
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "items":
					if ((type_byte & 0x7F) != GLib.Type.OBJECT || (type_byte & 0x80) == 0) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY(
							"prop '%s' expected object array",prop.name);
					}
					if (ctx.read_gtype() != typeof(TestPair)) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY(
							"prop '%s' expected TestPair elements",	prop.name);
					}
					var count = (uint) ctx.in_stream.read_byte();
					if ((count & 0x80) != 0) {
						count = ((count & 0x7F) << 8) | ctx.in_stream.read_byte();
					}
					var list = new Gee.ArrayList<TestPair>();
					for (var i = 0; i < count; i++) {
						var child = (TestPair) GLib.Object.new(typeof(TestPair));
						child.bin_read(ctx);
						list.add(child);
					}
					var val = GLib.Value(prop.value_type);
					val.set_object(list);
					this.set_property(prop.name, val);
					return;
				default:
					bin_default_read_prop(ctx, prop, type_byte);
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

		public override void bin_write(OLLMrpc.Bin.Stream ctx) throws GLib.Error
		{
			unowned GLib.ObjectClass obj_class = this.get_class();
			GLib.ParamSpec[] properties = obj_class.list_properties();

			foreach (var prop in properties) {
				if (prop.name == "g-type-instance" || prop.name == "ref-count") {
					continue;
				}
				if (prop.name == "extra") {
					continue;
				}
				this.bin_write_prop(ctx, prop);
			}
			ctx.out_stream.put_uint16(OLLMrpc.Bin.Stream.TOKEN_END);
		}
	}

	class TestRpcBin : RpcTestAppBase
	{
		public TestRpcBin()
		{
			base("com.roojs.ollmchat.test-rpc-bin");
		}

		protected override string get_app_name()
		{
			return "test-rpc-bin";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			try {

		var mem = new GLib.MemoryOutputStream.resizable();
		var out_stream = new GLib.DataOutputStream(mem);

		var write_bin = new OLLMrpc.Bin.Stream(null, out_stream);

		var original = new TestPair() {
			name = "alpha",
			count = 42,
		};

					OLLMrpc.Bin.register("TestPair", typeof(TestPair));
			OLLMrpc.Bin.register(
				"TestSkipDefault",
				typeof(TestSkipDefault)
			);
			OLLMrpc.Bin.register("TestParent", typeof(TestParent));
			OLLMrpc.Bin.register("TestPaths", typeof(TestPaths));
			OLLMrpc.Bin.register("TestListBag", typeof(TestListBag));

			write_bin.write(original);
			out_stream.close();

			var bytes = mem.steal_as_bytes();
			var in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			var in_stream = new GLib.DataInputStream(in_base);

			var read_bin = new OLLMrpc.Bin.Stream(in_stream, null);

			var parsed = read_bin.parse() as TestPair;
			this.check(command_line, !(parsed == null), "parse returned null\n");
			this.check(command_line, !(parsed.name != "alpha" || parsed.count != 42), "round-trip mismatch\n");

			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);

			var nested_src = new TestParent() {
				label = "parent",
				child = new TestPair() {
					name = "nested",
					count = 7,
				},
			};
			write_bin.write(nested_src);
			out_stream.close();

			bytes = mem.steal_as_bytes();
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);

			var nested_dst = read_bin.parse() as TestParent;
			this.check(command_line, !(nested_dst == null), "nested parse returned null\n");
			this.check(command_line, !(nested_dst.label != "parent"), "nested label mismatch\n");
			this.check(command_line, !(nested_dst.child == null), "nested child is null\n");
			this.check(command_line, !(
				nested_dst.child.name != "nested"
				|| nested_dst.child.count != 7
			), "nested child mismatch\n");

			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);

			var skip_src = new TestSkipDefault() {
				keep = "visible",
				extra = new GLib.Object(),
			};
			write_bin.write(skip_src);
			out_stream.close();

			bytes = mem.steal_as_bytes();
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);

			var skip_dst = read_bin.parse() as TestSkipDefault;
			this.check(command_line, !(skip_dst == null), "skip parse returned null\n");
			this.check(command_line, !(skip_dst.keep != "visible"), "skip keep mismatch\n");
			this.check(command_line, !(skip_dst.extra != null), "unsupported prop should stay null after round-trip\n");

			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);

			var paths_src = new TestPaths() {
				paths = { "a", "bb", "" },
			};
			write_bin.write(paths_src);
			out_stream.close();

			bytes = mem.steal_as_bytes();
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);

			var paths_dst = read_bin.parse() as TestPaths;
			this.check(command_line, !(paths_dst == null), "paths parse returned null\n");
			this.check(command_line, !(paths_dst.paths.length != 3), "paths length mismatch\n");
			this.check(command_line, !(
				paths_dst.paths[0] != "a"
				|| paths_dst.paths[1] != "bb"
				|| paths_dst.paths[2] != ""
			), "paths element mismatch\n");

			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);

			var long_name = string.nfill(130, 'x');
			var long_src = new TestPair() {
				name = long_name,
				count = 1,
			};
			write_bin.write(long_src);
			out_stream.close();

			bytes = mem.steal_as_bytes();
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);

			var long_dst = read_bin.parse() as TestPair;
			this.check(command_line, !(long_dst == null), "long string parse returned null\n");
			this.check(command_line, !(long_dst.name != long_name || long_dst.count != 1), "long string round-trip mismatch\n");

			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);

			var huge = string.nfill(40000, 'z');
			var huge_src = new TestPair() {
				name = huge,
				count = 2,
			};
			write_bin.write(huge_src);
			out_stream.close();

			bytes = mem.steal_as_bytes();
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);

			var huge_dst = read_bin.parse() as TestPair;
			this.check(command_line, !(huge_dst == null), "huge string parse returned null\n");
			this.check(command_line, !(huge_dst.name != huge || huge_dst.count != 2), "huge string round-trip mismatch\n");

			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);

			var list_src = new TestListBag() {
				label = "bag",
				items = new Gee.ArrayList<TestPair>(),
			};
			list_src.items.add(new TestPair() {
				name = "one",
				count = 1,
			});
			list_src.items.add(new TestPair() {
				name = "two",
				count = 2,
			});
			write_bin.write(list_src);
			out_stream.close();

			bytes = mem.steal_as_bytes();
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);

			var list_dst = read_bin.parse() as TestListBag;
			this.check(command_line, !(list_dst == null), "list bag parse returned null\n");
			this.check(command_line, !(list_dst.label != "bag"), "list bag label mismatch\n");
			this.check(command_line, !(list_dst.items.size != 2), "list bag items size mismatch\n");
			this.check(
				command_line,
				!(
					list_dst.items.get(0).name != "one"
					|| list_dst.items.get(0).count != 1
					|| list_dst.items.get(1).name != "two"
					|| list_dst.items.get(1).count != 2
				),
				"list bag element mismatch"
			);

			OLLMrpc.Request.rpc_register();
			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
			var req_a = new OLLMrpc.Request() {
				id = 1,
				method = "RPC-Daemon.hello"
			};
			var req_b = new OLLMrpc.Request() {
				id = 2,
				method = "RPC-Daemon.hello"
			};
			write_bin.write(req_a);
			var after_first = (size_t) mem.data_size;
			write_bin.write(req_b);
			out_stream.close();
			bytes = mem.steal_as_bytes();
			var second_slice = bytes.slice((int) after_first, (int) bytes.get_size());
			var needle = (uint8[]) "RPC-Daemon.hello";
			var hay = second_slice.get_data();
			var found_hello = false;
			for (var i = 0; i + needle.length <= hay.length; i++) {
				var match = true;
				for (var j = 0; j < needle.length; j++) {
					if (hay[i + j] != needle[j]) {
						match = false;
						break;
					}
				}
				if (!match) {
					continue;
				}
				found_hello = true;
				break;
			}
			this.check(
				command_line,
				!found_hello,
				"second Request.method still carries full UTF-8"
			);
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);
			var parsed_a = read_bin.parse() as OLLMrpc.Request;
			var parsed_b = read_bin.parse() as OLLMrpc.Request;
			this.check(command_line, !(parsed_a == null || parsed_b == null), "method-ref parse null\n");
			this.check(
				command_line,
				!(
					parsed_a.method != "RPC-Daemon.hello"
					|| parsed_b.method != "RPC-Daemon.hello"
					|| parsed_a.id != 1
					|| parsed_b.id != 2
				),
				"method-ref round-trip mismatch"
			);

			} catch (GLib.Error e) {
				this.fail(command_line, "bin-test: %s".printf(e.message));
			}
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcBin().run(args);
}
