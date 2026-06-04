/*
 * POC only — wire types: static rpc_register() → Rpc.rpc_register(Type).
 * Rpc.rpc_register null-checks result_types; RpcClient static construct calls wire rpc_register.
 *
 *   valac -o /tmp/oc-test-rpc-result-type --pkg=json-glib-1.0 --pkg=gee-0.8 --pkg=gobject-2.0 \
 *     examples/oc-test-rpc-result-type.vala && /tmp/oc-test-rpc-result-type
 */

namespace OLLMfiles
{
	public class ProjectEntry : GLib.Object, Json.Serializable
	{
		public string path { get; set; default = ""; }
		public bool skip_scan { get; set; default = false; }

		public static void rpc_register()
		{
			Rpc.rpc_register(typeof(ProjectEntry));
		}
	}

	public class ProjectList : GLib.Object
	{
		public Gee.ArrayList<ProjectEntry> projects {
			get; set;
			default = new Gee.ArrayList<ProjectEntry>();
		}

		public static void rpc_register()
		{
			Rpc.rpc_register(typeof(ProjectList));
		}
	}

	namespace Rpc
	{
		public static Gee.HashMap<string, Type> result_types;

		public static void rpc_register(Type t)
		{
			if (result_types == null) {
				result_types = new Gee.HashMap<string, Type>();
			}
			result_types.set(t.name(), t);
		}
	}

	public class RpcClient : GLib.Object
	{
		static construct
		{
			ProjectList.rpc_register();
			ProjectEntry.rpc_register();
		}
	}
}

void main()
{
	var list_name = typeof(OLLMfiles.ProjectList).name();
	var entry_name = typeof(OLLMfiles.ProjectEntry).name();

	print("=== POC: static WireType.rpc_register() ===\n\n");

	print("1) Before any rpc_register — Type.from_name only:\n");
	print("   %s valid=%s\n", list_name,
		(Type.from_name(list_name) != Type.INVALID).to_string());
	print("   map null=%s\n", (OLLMfiles.Rpc.result_types == null).to_string());

	print("\n2) After ProjectList.rpc_register() only:\n");
	OLLMfiles.ProjectList.rpc_register();
	var map_ok = OLLMfiles.Rpc.result_types != null
		&& OLLMfiles.Rpc.result_types.has_key(list_name);
	print("   in_map=%s from_name valid=%s\n",
		map_ok.to_string(),
		(Type.from_name(list_name) != Type.INVALID).to_string());

	print("\n3) RpcClient static construct:\n");
	new OLLMfiles.RpcClient();
	print("   list in_map=%s entry in_map=%s\n",
		OLLMfiles.Rpc.result_types.has_key(list_name).to_string(),
		OLLMfiles.Rpc.result_types.has_key(entry_name).to_string());
	var t = OLLMfiles.Rpc.result_types.get(list_name);
	print("   type=%s valid=%s\n", t.name(), (t != Type.INVALID).to_string());

	var line = """{"jsonrpc":"2.0","id":1,"result":{"projects":[{"path":"/a","skip_scan":false},{"path":"/b","skip_scan":true}]}}""";
	var parser = new Json.Parser();
	try {
		parser.load_from_data(line, -1);
	} catch (GLib.Error e) {
		GLib.error("%s", e.message);
	}
	var result_node = parser.get_root().get_object().get_member("result");

	print("\n4) Json.gobject_deserialize top-level:\n");
	var shell = Json.gobject_deserialize(t, result_node) as OLLMfiles.ProjectList;
	print("   projects.size=%u\n", shell != null ? shell.projects.size : 0u);

	print("\n5) Manual projects[] fill:\n");
	var list = new OLLMfiles.ProjectList();
	var arr = result_node.get_object().get_member("projects").get_array();
	for (uint i = 0; i < arr.get_length(); i++) {
		var row = Json.gobject_deserialize(
			typeof(OLLMfiles.ProjectEntry), arr.get_element(i)
		) as OLLMfiles.ProjectEntry;
		list.projects.add(row);
	}
	print("   projects.size=%u\n", list.projects.size);
}
