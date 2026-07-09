/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

class OcHfApp : TestAppBase
{
	protected static string? opt_search = null;
	protected static string? opt_detail = null;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS]

Hugging Face Hub catalog — search and model detail (live JSON).

Options:
  --search TERM    Hub search (e.g. speculative)
  --detail REF     Hub model ref author/name

Examples:
  {ARG} --search speculative
  {ARG} --detail author/some-draft-model
  {ARG} --debug --search speculative
"""; }

	protected const OptionEntry[] local_options = {
		{ "search", 0, 0, OptionArg.STRING, ref opt_search, "Hub search term", "TERM" },
		{ "detail", 0, 0, OptionArg.STRING, ref opt_detail, "Hub model ref (author/name)", "MODEL_REF" },
		{ null }
	};

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var base_opts = new OptionEntry[2];
		base_opts[0] = base_options[0];
		base_opts[1] = { null };
		opt_context.add_main_entries(base_opts, null);

		var app_group = new OptionGroup("oc-hf", "Hub catalog", "Hugging Face Hub options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);

		return opt_context;
	}

	public OcHfApp()
	{
		base("org.roojs.oc-hf");
	}

	public override OLLMchat.Settings.Config2 load_config()
	{
		return new OLLMchat.Settings.Config2();
	}

	protected override string get_app_name()
	{
		return "Hugging Face Hub catalog (oc-hf)";
	}

	protected override string? validate_args(string[] remaining_args)
	{
		var has_search = opt_search != null && opt_search.strip() != "";
		var has_detail = opt_detail != null && opt_detail.strip() != "";

		if (!has_search && !has_detail) {
			return this.help.replace("{ARG}", remaining_args[0]);
		}
		if (has_search && has_detail) {
			return "Error: use --search or --detail, not both\n";
		}
		return null;
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		OLLMhf.rpc_register();

		var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
		yield rpc.connect(new OLLMrpc.Request());

		if (opt_search != null && opt_search.strip() != "") {
			var req = new OLLMrpc.Request() {
				method = "/api/models",
				param = new OLLMhf.Param.Search() {
					search = opt_search.strip(),
					filter = "gguf",
					limit = 20,
					sort = "downloads",
					direction = "-1",
				},
				result_type = typeof(OLLMhf.ModelArray),
			};
			var resp = yield rpc.call(req);
			var bag = (OLLMhf.ModelArray) resp.result[0];
			var arr = new Json.Array();
			foreach (var model in bag.items) {
				arr.add_element(Json.gobject_serialize(model));
			}
			var root = new Json.Node(Json.NodeType.ARRAY);
			root.set_array(arr);
			stdout.printf("%s\n", Json.to_string(root, true));
			return;
		}

		var model_ref = opt_detail != null ? opt_detail.strip() : "";
		if (model_ref == "") {
			throw new GLib.IOError.INVALID_ARGUMENT("--detail requires a model ref");
		}
		var detail_req = new OLLMrpc.Request() {
			method = "/api/models/" + model_ref,
			param = new OLLMhf.Param.ModelDetails(),
			result_type = typeof(OLLMhf.Model),
		};
		var detail_resp = yield rpc.call(detail_req);
		var model = (OLLMhf.Model) detail_resp.result[0];
		stdout.printf("%s\n", Json.to_string(Json.gobject_serialize(model), true));
	}
}

int main(string[] args)
{
	var app = new OcHfApp();
	return app.run(args);
}
