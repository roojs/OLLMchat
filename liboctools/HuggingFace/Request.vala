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

namespace OLLMtools.HuggingFace
{
	/**
	 * Request container providing full API integration, VRAM profiling, and MTP guides.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		public bool help { get; set; default = false; }
		public string action { get; set; default = ""; }
		public string query { get; set; default = ""; }
		public string model_ref { get; set; default = ""; }
		public Gee.ArrayList<string> files {
			get; set; default = new Gee.ArrayList<string>();
		}

		private OLLMhf.Model? download_model = null;
		internal Json.Node? raw = null;

		public Request()
		{
		}

		public override bool deserialize_property(
			string property_name,
			out Value value,
			ParamSpec pspec,
			Json.Node property_node
		) {
			if (property_name != "files") {
				return default_deserialize_property(
					property_name, out value, pspec, property_node);
			}
			this.files.clear();
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var arr = property_node.get_array();
				for (uint i = 0; i < arr.get_length(); i++) {
					this.files.add(arr.get_string_element(i));
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.files);
			return true;
		}

		public override string to_summary()
		{
			if (this.help) {
				return "help";
			}
			var request_message = "Action: "
				+ (this.action.strip() != "" ? this.action.strip() : "(none)");
			if (this.query.strip() != "") {
				request_message += "\nQuery: " + this.query.strip();
			}
			if (this.model_ref.strip() != "") {
				request_message += "\nModel: " + this.model_ref.strip();
			}
			if (this.action.strip().down() == "download" || this.files.size > 0) {
				request_message += "\nFiles: "
					+ (this.files.size > 0
						? string.joinv(", ", this.files.to_array())
						: "(none — send a JSON array, e.g. [\"model.gguf\"])");
			}
			request_message += "\nTool call arguments (JSON): "
				+ Json.to_string(this.raw, false);
			return request_message;
		}

		protected override bool build_perm_question()
		{
			if (this.action.strip().down() != "download") {
				return false;
			}

			var hub_ref = this.model_ref.strip();
			var file_list = new Gee.ArrayList<string>();
			file_list.add_all(this.files);
			int64 total_bytes = 0;
			foreach (var sibling in this.download_model.siblings) {
				if (file_list.index_of(sibling.rfilename) < 0) {
					continue;
				}
				total_bytes += sibling.size;
			}

			this.one_time_only = true;
			this.permission_target_path = "hf_download#" 	+ hub_ref + "#" +
				 string.joinv(",", this.files.to_array());
			this.permission_operation = OLLMchat.ChatPermission.Operation.WRITE;
			this.permission_question = "Download " + hub_ref
				+ " (" + 
					( 	this.files.size == 1 ? this.files.get(0)
						: this.files.size.to_string() + " files")
				+ ", about "
				+ "%.1f".printf((double) total_bytes / (1024.0 * 1024.0 * 1024.0))
				+ " GB)?";
			return true;
		}

		/**
		 * Download needs Hub detail before {@link build_perm_question} can run.
		 */
		public override async string execute()
		{
			if (this.help || this.action.strip().down() != "download") {
				return yield base.execute();
			}

			this.agent.add_message(new OLLMchat.Message("ui",
				OLLMchat.Message.fenced(
					"text.oc-frame-info.collapsed Hugging Face Hub: download",
					this.to_summary())));

			if (this.model_ref.strip() == "") {
				var err = "ERROR: 'model_ref' is required for download. Refer to help for usage.";
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-danger.collapsed Hugging Face Hub: download",
						this.to_summary() + "\n\n" + err)));
				return this.to_summary() + "\n\n" + err;
			}
			if (this.files.size == 0) {
				var err = "ERROR: 'files' is required for download — "
					+ "send a JSON array of filename strings, "
					+ "e.g. {\"files\": [\"model.gguf\"]}. "
					+ "Refer to help for sharding rules.";
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-danger.collapsed Hugging Face Hub: download",
						this.to_summary() + "\n\n" + err)));
				return this.to_summary() + "\n\n" + err;
			}

			var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
			try {
				// FIXME - we should probably cache this info - assume the
				// llm would have fetched it before..
				yield rpc.connect(new OLLMrpc.Request());
				var detail_resp = yield rpc.call(new OLLMrpc.Request() {
					method = "/api/models/" + this.model_ref.strip(),
					result_type = typeof(OLLMhf.Model),
				});
				if (detail_resp.error != null) {
					throw new GLib.IOError.FAILED(detail_resp.error.message);
				}
				if (detail_resp.result.size == 0) {
					throw new GLib.IOError.FAILED("empty Hub model response");
				}
				this.download_model = (OLLMhf.Model) detail_resp.result[0];
			} catch (GLib.Error e) {
				var err = "ERROR: " + e.message;
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-danger.collapsed Hugging Face Hub: download",
						this.to_summary() + "\n\n" + err)));
				return this.to_summary() + "\n\n" + err;
			}

			var file_list = new Gee.ArrayList<string>();
			file_list.add_all(this.files);
			var matched = 0;
			int64 total_bytes = 0;
			foreach (var sibling in this.download_model.siblings) {
				if (file_list.index_of(sibling.rfilename) < 0) {
					continue;
				}
				matched++;
				total_bytes += sibling.size;
			}

			if (matched != this.files.size) {
				var err = "ERROR: One or more requested files were not found in model siblings.";
				err += "\nRepo has "
					+ this.download_model.siblings.size.to_string()
					+ " sibling file(s) — call detail to list exact filenames.";
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-danger.collapsed Hugging Face Hub: download",
						this.to_summary() + "\n\n" + err)));
				return this.to_summary() + "\n\n" + err;
			}
			if (total_bytes <= 0) {
				var err = "ERROR: Could not determine download size for the requested files.";
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-danger.collapsed Hugging Face Hub: download",
						this.to_summary() + "\n\n" + err)));
				return this.to_summary() + "\n\n" + err;
			}

			var result = yield base.execute();
			if (result.has_prefix("ERROR:")) {
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-danger.collapsed Hugging Face Hub: download",
						this.to_summary() + "\n\n" + result)));
			}
			return result;
		}

		/**
		 * Probe kernel GPU VRAM reporting (NVIDIA proc, then DRM sysfs).
		 *
		 * @return Formatted budget string for help output, or "unknown"
		 */
		private string vram_limit_text()
		{
			int64 total_vram_bytes = 0;
#if !G_OS_WIN32
			if (GLib.FileUtils.test(
				"/proc/driver/nvidia/gpus", GLib.FileTest.IS_DIR)) {
				GLib.Dir? gpu_dir = null;
				try {
					gpu_dir = GLib.Dir.open("/proc/driver/nvidia/gpus");
				} catch (GLib.Error e) {
				}
				var entry = gpu_dir != null ? gpu_dir.read_name() : null;
				while (entry != null) {
					if (entry == "." || entry == "..") {
						entry = gpu_dir.read_name();
						continue;
					}
					var info_path = GLib.Path.build_filename(
						"/proc/driver/nvidia/gpus", entry, "information");
					if (!GLib.FileUtils.test( info_path, GLib.FileTest.EXISTS)) {
						entry = gpu_dir.read_name();
						continue;
					}
					var contents = "";
					try {
						GLib.FileUtils.get_contents(info_path, out contents);
					} catch (GLib.Error e) {
						entry = gpu_dir.read_name();
						continue;
					}
					var vram_mib = new GLib.Regex("^Total\\s*:\\s*(\\d+)\\s*MiB",
						GLib.RegexCompileFlags.MULTILINE);

					GLib.MatchInfo match_info;
					if (vram_mib.match(contents, 0, out match_info)) {
						total_vram_bytes += int64.parse( match_info.fetch(1)) * 1024 * 1024;
					}
					entry = gpu_dir.read_name();
				}
			}
			if (total_vram_bytes <= 0) {
				for (var card = 0; card < 16; card++) {
					var vram_path = "/sys/class/drm/card" 	+ card.to_string()
						+ "/device/mem_info_vram_total";

					if (!GLib.FileUtils.test( vram_path, GLib.FileTest.EXISTS)) {
						continue;
					}
					var text = "";
					try {
						GLib.FileUtils.get_contents(vram_path, out text);
					} catch (GLib.Error e) {
						continue;
					}
					try {
						total_vram_bytes += int64.parse(text.strip());
					} catch (GLib.Error e) {
					}
				}
			}
#endif
			if (total_vram_bytes <= 0) {
				return "unknown";
			}
			return "about "
				+ "%.1f".printf(
					(double) total_vram_bytes / (1024.0 * 1024.0 * 1024.0))
				+ " GB VRAM";
		}

		private string help_text()
		{
			return @"
================================================================================
HUGGING FACE HUB ENGINE — SYSTEM OPERATIONAL MANIFEST
================================================================================
HOST MACHINE SPECIFICATIONS
  • Available Memory Limit (VRAM/Unified): $(this.vram_limit_text())
================================================================================

WHEN THE USER ASKS FOR A MODEL
  If the user wants to download, find, or install a GGUF from Hugging Face, you do it
  with this tool (search → detail → download). Do NOT tell them to download manually
  (browser, huggingface-cli, wget, etc.) or suggest steps they should run themselves.
  The user approves downloads in-app; progress appears in the activity bar.

PRIMARY STRATEGY: MULTI-TOKEN PREDICTION (MTP) SPECULATIVE INFERENCE
To maximize performance, prioritize downloading models with built-in MTP heads
(or explicit Draft-Model companions). This speeds up token generation by up to 2x
by predicting multiple tokens per forward pass.

CRITICAL HARDWARE BUDGETING RULES:
  1. SINGLE-FILE MTP MODELS: Highly recommended. These feature integrated self-speculation
     heads (e.g., Unsloth MTP GGUF series). They use only ~1-2% more VRAM than basic weights,
     making them incredibly memory efficient.
  2. TRADITIONAL DRAFT PAIRS: If downloading a separate draft model, the combined file
     sizes of BOTH the target and draft models must fit entirely inside the Memory Limit
     noted above, leaving a 2-4GB safety gap for context allocation.
  3. QUANTIZATION CHOICE: Scale quantization down (e.g., Q4_K_M or IQ3 variants) to guarantee
     the file sizes safely accommodate the host machine's memory boundaries.

---
PARAMETER REFERENCE
---
  help       {boolean}  Set true on your FIRST call only. Returns this manifest.
  action     {string}   Required on operational calls. One of:
                         • \"search\"  — find GGUF repos matching query
                         • \"detail\"  — fetch file tree and sizes for one model_ref
                         • \"download\" — fetch specific files from model_ref
  query      {string}   Required for action \"search\". Hub search terms.
                         Include MTP/draft keywords when targeting speculative models.
  model_ref  {string}   Required for \"detail\" and \"download\". Hub repo id \"author/name\".
  files      {string[]} Required for \"download\". Exact sibling filenames from detail output.
                         Include every shard (.gguf-split-N) when the model is split.

---
1. SEARCH ACTIONS FOR MTP & SPECULATION
---
When looking for assets, include tactical tokens in your query parameter:
  • Query for optimized MTP: {\"action\": \"search\", \"query\": \"Qwen3.5 MTP GGUF\"}
  • Query for draft models:   {\"action\": \"search\", \"query\": \"llama draft model\"}

---
2. OPERATION PIPELINE
---
  Step A: Call \"search\" with your target model architectural intent.
  Step B: Call \"detail\" using the exact \"model_ref\" repo string to fetch its file tree.
  Step C: Review file sizes under the \"siblings\" list to calculate memory compliance.
  Step D: Execute \"download\" with precise filenames in the \"files\" array.
          You will be asked to confirm the download (file list and total size)
          before it starts. Progress appears in the activity bar.
          (Always include ALL related .gguf-split-x parts if the model is sharded).
================================================================================";
		}

		protected override async string execute_request() throws GLib.Error
		{
			var act = this.action.strip().down();
			if (!this.help && act != "download") {
				var frame_title = "Hugging Face Hub";
				if (this.action.strip() != "") {
					frame_title += ": " + this.action.strip();
				}
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-info.collapsed " + frame_title,
						this.to_summary())));
			}

			if (this.help) {
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-info.collapsed Hugging Face Hub: help",
						this.to_summary())));
				var help_result = this.help_text();
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-success.collapsed Hugging Face Hub: help",
						help_result)));
				return help_result;
			}

			if (act == "") {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Call with help:true first. Refer to the help manifest for parameter details.");
			}

			var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
			yield rpc.connect(new OLLMrpc.Request());
			var json_helper = new OLLMrpc.Bin.Json(OLLMrpc.Bin.Mode.AUTO);

			switch (act) {
				case "search":
					if (this.query.strip() == "") {
						throw new GLib.IOError.INVALID_ARGUMENT(
							"'query' is required for search. Refer to help for examples.");
					}

					var search_req = new OLLMrpc.Request() {
						method = "/api/models",
						param = new OLLMhf.Param.Search() {
							search = this.query.strip(),
							filter = "gguf",
							limit = 20,
							sort = "downloads",
							direction = "-1",
							full = true,
						},
						result_type = typeof(OLLMhf.ModelArray),
					};

					var search_resp = yield rpc.call(search_req);
					if (search_resp.error != null) {
						throw new GLib.IOError.FAILED(search_resp.error.message);
					}
					if (search_resp.result.size == 0) {
						throw new GLib.IOError.FAILED("empty Hub search response");
					}

					var arr = new Json.Array();
					foreach (var model in ((OLLMhf.ModelArray) search_resp.result[0]).items) {
						arr.add_element(json_helper.from_gobject(model));
					}
					var root = new Json.Node(Json.NodeType.ARRAY);
					root.set_array(arr);
					var search_result = Json.to_string(root, true);
					this.agent.add_message(new OLLMchat.Message("ui",
						OLLMchat.Message.fenced(
							"json.oc-frame-success.collapsed Hugging Face Hub: search results",
							search_result)));
					return search_result;

				case "detail":
					if (this.model_ref.strip() == "") {
						throw new GLib.IOError.INVALID_ARGUMENT(
							"'model_ref' is required for detail. Refer to help for usage.");
					}

					var detail_resp = yield rpc.call(new OLLMrpc.Request() {
						method = "/api/models/" + this.model_ref.strip(),
						result_type = typeof(OLLMhf.Model),
					});
					if (detail_resp.error != null) {
						throw new GLib.IOError.FAILED(detail_resp.error.message);
					}
					if (detail_resp.result.size == 0) {
						throw new GLib.IOError.FAILED("empty Hub model response");
					}

					var detail_result = Json.to_string(json_helper.from_gobject(
						(OLLMhf.Model) detail_resp.result[0]), true);
					this.agent.add_message(new OLLMchat.Message("ui",
						OLLMchat.Message.fenced(
							"json.oc-frame-success.collapsed Hugging Face Hub: detail",
							detail_result)));
					return detail_result;

				case "download":
					if (this.model_ref.strip() == "") {
						throw new GLib.IOError.INVALID_ARGUMENT(
							"'model_ref' is required for download. Refer to help for usage.");
					}
					if (this.files.size == 0) {
						throw new GLib.IOError.INVALID_ARGUMENT(
							"'files' is required for download — send a JSON array of "
							+ "filename strings, e.g. {\"files\": [\"model.gguf\"]}. "
							+ "Refer to help for sharding rules.");
					}

					OLLMhf.Model hub_model = this.download_model;
					if (hub_model == null) {
						var detail_resp = yield rpc.call(new OLLMrpc.Request() {
							method = "/api/models/" + this.model_ref.strip(),
							result_type = typeof(OLLMhf.Model),
						});
						if (detail_resp.error != null) {
							throw new GLib.IOError.FAILED(detail_resp.error.message);
						}
						if (detail_resp.result.size == 0) {
							throw new GLib.IOError.FAILED("empty Hub model response");
						}
						hub_model = (OLLMhf.Model) detail_resp.result[0];
					}

					var dl = new OLLMhf.Download(hub_model);
					dl.file_filter = this.files.to_array();

					var hub_ref = this.model_ref.strip();
					this.agent.notification(new OLLMrpc.Notification() {
						method = "event.hf.download.start",
						object_type = "Model",
						message = hub_ref,
					});

					int64 last_report = 0;
					dl.progress.connect((notif) => {
						if (notif.progress_total > 0
							&& notif.progress_completed - last_report
								< notif.progress_total / 20
							&& notif.progress_completed != notif.progress_total) {
							return;
						}
						last_report = notif.progress_completed;
						this.agent.notification(notif);
					});

					dl.start.begin(null, (obj, res) => {
						try {
							dl.start.end(res);
							this.agent.notification(new OLLMrpc.Notification() {
								method = "event.hf.download.end",
								object_type = "Model",
								message = hub_ref,
							});
						} catch (GLib.Error e) {
							this.agent.notification(new OLLMrpc.Notification() {
								method = "event.hf.download.end",
								object_type = "Model",
								message = hub_ref + " error: " + e.message,
							});
						}
					});

					var download_result = "Download started for " + hub_ref
						+ " (" + string.joinv(", ", this.files.to_array())
						+ "). Watch the activity bar for progress.";
					this.agent.add_message(new OLLMchat.Message("ui",
						OLLMchat.Message.fenced(
							"text.oc-frame-success.collapsed Hugging Face Hub: download",
							download_result)));
					return download_result;

				default:
					throw new GLib.IOError.INVALID_ARGUMENT(
						"Unknown action: '%s'. Refer to help for valid values.".printf(this.action));
			}
		}
	}
}
