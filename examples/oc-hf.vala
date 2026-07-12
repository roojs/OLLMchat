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
	protected static string? opt_download = null;
	protected static string? opt_file = null;
	protected static string? opt_models_dir = null;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS]

Hugging Face Hub catalog — search, model detail, and GGUF download.

Options:
  --search TERM       Hub search (e.g. speculative)
  --detail REF        Hub model ref author/name (JSON on stdout)
  --download REF      Download GGUF siblings for model ref
  --file NAME         Limit download to one sibling filename
  --models-dir DIR    Install root (default ~/.local/share/ollmchat/models)

Examples:
  {ARG} --search speculative
  {ARG} --detail author/some-draft-model
  {ARG} --download author/some-draft-model --file draft-q4_k_m.gguf
  {ARG} --debug --search speculative
"""; }

	protected const OptionEntry[] local_options = {
		{ "search", 0, 0, OptionArg.STRING, ref opt_search, "Hub search term", "TERM" },
		{ "detail", 0, 0, OptionArg.STRING, ref opt_detail, "Hub model ref (author/name)", "MODEL_REF" },
		{ "download", 0, 0, OptionArg.STRING, ref opt_download, "Download model ref", "MODEL_REF" },
		{ "file", 0, 0, OptionArg.STRING, ref opt_file, "Single sibling filename", "NAME" },
		{ "models-dir", 0, 0, OptionArg.STRING, ref opt_models_dir, "Models install directory", "DIR" },
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
		var mode_count = (opt_search != null && opt_search.strip() != "" ? 1 : 0)
			+ (opt_detail != null && opt_detail.strip() != "" ? 1 : 0)
			+ (opt_download != null && opt_download.strip() != "" ? 1 : 0);

		if (mode_count == 0) {
			return this.help.replace("{ARG}", remaining_args[0]);
		}
		if (mode_count > 1) {
			return "Error: use only one of --search, --detail, or --download\n";
		}
		return null;
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		OLLMhf.rpc_register();

		if (opt_download != null && opt_download.strip() != "") {
			var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
			yield rpc.connect(new OLLMrpc.Request());
			var detail_req = new OLLMrpc.Request() {
				method = "/api/models/" + opt_download.strip(),
				result_type = typeof(OLLMhf.Model),
			};
			var detail_resp = yield rpc.call(detail_req);
			var dl = new OLLMhf.Download((OLLMhf.Model) detail_resp.result[0]);
			if (opt_models_dir != null && opt_models_dir.strip() != "") {
				dl.models_dir = opt_models_dir.strip();
			}
			if (opt_file != null && opt_file.strip() != "") {
				dl.file_filter = { opt_file.strip() };
			}
			var last_report = (int64) 0;
			dl.progress.connect((notif) => {
				if (notif.progress_total > 0
					&& notif.progress_completed - last_report
						< notif.progress_total / 20
					&& notif.progress_completed != notif.progress_total) {
					return;
				}
				last_report = notif.progress_completed;
				command_line.print(
					"%s %lld/%lld\n",
					notif.message,
					notif.progress_completed,
					notif.progress_total
				);
			});
			yield dl.start();
			command_line.print("ok %s\n", opt_download.strip());
			return;
		}

		var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
		yield rpc.connect(new OLLMrpc.Request());
		var json = new OLLMrpc.Bin.Json(OLLMrpc.Bin.Mode.AUTO);

		if (opt_search != null && opt_search.strip() != "") {
			var req = new OLLMrpc.Request() {
				method = "/api/models",
				param = new OLLMhf.Param.Search() {
					search = opt_search.strip(),
					filter = "gguf",
					limit = 20,
					sort = "downloads",
					direction = "-1",
					full = true,
				},
				result_type = typeof(OLLMhf.ModelArray),
			};
			var resp = yield rpc.call(req);
			var arr = new Json.Array();
			foreach (var model in ((OLLMhf.ModelArray) resp.result[0]).items) {
				var node = json.from_gobject(model);
				arr.add_element(node);
			}
			var root = new Json.Node(Json.NodeType.ARRAY);
			root.set_array(arr);
			stdout.printf("%s\n", Json.to_string(root, true));
			return;
		}

		var detail_req = new OLLMrpc.Request() {
			method = "/api/models/" + opt_detail.strip(),
			result_type = typeof(OLLMhf.Model),
		};
		var detail_resp = yield rpc.call(detail_req);
		var hub_model = (OLLMhf.Model) detail_resp.result[0];
		yield hub_model.fetch_siblings(rpc);
		var node = json.from_gobject(hub_model);
		stdout.printf(
			"%s\n",
			Json.to_string(node, true)
		);
	}
}

int main(string[] args)
{
	var app = new OcHfApp();
	return app.run(args);
}
