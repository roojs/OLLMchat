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
	 * Tool for interacting with the Hugging Face Hub.
	 *
	 * Dynamically evaluates host memory capacity and guides the LLM to search and
	 * select optimized native Multi-Token Prediction (MTP) model configurations.
	 */
	public class Tool : OLLMchat.Tool.BaseTool, OLLMchat.Tool.WrapInterface
	{
		public override string name { get { return "huggingface_hub"; } }

		public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
		public override string title { get { return "Hugging Face Hub Tool"; } }
		public override string example_call {
			get { return "{\"name\": \"huggingface_hub\", \"arguments\": {\"help\": true}}"; }
		}
		public override string description { get {
			return """
Search and download GGUF files from Hugging Face Hub.

You MUST call this tool with help:true before any other invocation. The help response
contains mandatory operational guidance (VRAM budgeting, MTP model selection, and the
full parameter reference). Do not call search, detail, or download until you have
read the help output.""";
		} }

		public override string parameter_description { get {
			return """
@param help {boolean} [required on first call] Set true to retrieve the operational manifest. You MUST call with help:true once before any search, detail, or download call.
@param action {string} [optional] Operation to run. Refer to help for valid values and workflow.
@param query {string} [optional] Search filter terms. Refer to help for usage and examples.
@param model_ref {string} [optional] Hub repo path (author/name). Refer to help for usage.
@param files {array of strings} [optional] Filenames to download. Refer to help for sharding rules.""";
		} }

		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }

		public Tool(OLLMfiles.ProjectManager? project_manager = null)
		{
			base();
			this.project_manager = project_manager;
			if (project_manager != null) {
				OLLMhf.rpc_register();
			}
		}

		/**
		 * {@link OLLMchat.Tool.WrapInterface} entry point; {@code huggingface_hub} is not
		 * wrappable — {@link OLLMtools.ToolBuilder} must not clone it for a {@code .tool} alias.
		 *
		 * @throws Error always {@link GLib.IOError.NOT_SUPPORTED}
		 */
		public OLLMchat.Tool.BaseTool clone() throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED(
				"huggingface_hub cannot be wrapped or cloned");
		}

		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			var req = Json.gobject_deserialize(typeof(Request), parameters_node)
				as OLLMchat.Tool.RequestBase;
			if (req == null) {
				return null;
			}
			var hf_req = (Request) req;
			hf_req.raw = parameters_node;
			return req;
		}

		public OLLMchat.Tool.RequestBase? deserialize_wrapped(Json.Node parameters_node, string command_template)
		{
			return this.deserialize(parameters_node);
		}
	}
}
