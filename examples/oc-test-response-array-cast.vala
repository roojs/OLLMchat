/*
 * POC: does Gee.ArrayList<T> cast to Gee.ArrayList<GLib.Object> for Response.result?
 *
 *   valac -o /tmp/oc-test-response-array-cast --pkg=gee-0.8 --pkg=gobject-2.0 \
 *     examples/oc-test-response-array-cast.vala && /tmp/oc-test-response-array-cast
 */

namespace OLLMfiles
{
	public class WireA : GLib.Object
	{
		public string name { get; set; default = "a"; }
	}

	public class WireB : GLib.Object
	{
		public int n { get; set; default = 42; }
	}
}

bool cast_ok(GLib.Object? result, out uint size)
{
	var list = result as Gee.ArrayList<GLib.Object>;
	if (list == null) {
		size = 0;
		return false;
	}
	size = list.size;
	return true;
}

void main()
{
	print("=== Gee.ArrayList<T> as ArrayList<Object> ===\n\n");

	var a_list = new Gee.ArrayList<OLLMfiles.WireA>();
	a_list.add(new OLLMfiles.WireA() { name = "one" });
	a_list.add(new OLLMfiles.WireA() { name = "two" });

	GLib.Object? box_a = a_list;
	uint size;
	print("ArrayList<WireA> via Object?: %s",
		cast_ok(box_a, out size) ? "ok size=" + size.to_string() + "\n" : "FAILED\n");

	var b_list = new Gee.ArrayList<OLLMfiles.WireB>();
	b_list.add(new OLLMfiles.WireB() { n = 7 });
	GLib.Object? box_b = b_list;
	print("ArrayList<WireB> via Object?: %s",
		cast_ok(box_b, out size) ? "ok size=" + size.to_string() + "\n" : "FAILED\n");

	var objs = new Gee.ArrayList<GLib.Object>();
	objs.add(new OLLMfiles.WireA());
	objs.add(new OLLMfiles.WireB());
	print("ArrayList<Object>: %s",
		cast_ok(objs, out size) ? "ok size=" + size.to_string() + "\n" : "FAILED\n");

	print("\nAssign to GLib.Object? result field (Response.result pattern):\n");
	GLib.Object? result = a_list;
	print("  WireA list: %s\n",
		cast_ok(result, out size) ? "ok size=" + size.to_string() : "FAILED");
	result = b_list;
	print("  WireB list: %s\n",
		cast_ok(result, out size) ? "ok size=" + size.to_string() : "FAILED");
}
