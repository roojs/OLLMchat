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

namespace OLLMhf
{
	/**
	 * Hugging Face Hub model record (search hit or full detail).
	 *
	 * {@link model_ref} is the repo id {{{author/name}}} (not a numeric Hub id).
	 * Detail responses populate {@link files} from filtered {{{.gguf}}} siblings.
	 */
	public class Model : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/** Hub repo id {{{author/name}}}. */
		public string model_ref { get; set; default = ""; }

		/** Repo owner segment of {@link model_ref}. */
		public string author { get; set; default = ""; }

		/** Download count from Hub search/detail metadata. */
		public int64 downloads { get; set; default = 0; }

		/** Like count from Hub metadata. */
		public int likes { get; set; default = 0; }

		/** Hub tags (e.g. {{{gguf}}}, {{{text-generation}}}). */
		public string[] tags { get; set; default = {}; }

		/** Hub {{{pipeline_tag}}} when set. */
		public string pipeline_tag { get; set; default = ""; }

		/** Primary library name from Hub metadata. */
		public string library_name { get; set; default = ""; }

		/** True when the repo requires acceptance before download. */
		public bool gated { get; set; default = false; }

		/** True when the repo is private on the Hub. */
		public bool @private { get; set; default = false; }

		/** GGUF (and related) files from detail {{{siblings[]}}}. */
		public Gee.ArrayList<ModelFile> files {
			get; set; default = new Gee.ArrayList<ModelFile>();
		}

		public static void rpc_register() {
			OLLMrpc.Bin.register("Model", typeof(Model));
		}
	}
}
