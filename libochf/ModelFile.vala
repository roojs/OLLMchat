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
	 * One file entry from Hub model detail (typically a {{{.gguf}}} sibling).
	 */
	public class ModelFile : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/** Repo-relative path (e.g. {{{draft-q4_k_m.gguf}}}). */
		public string filename { get; set; default = ""; }

		/** File size in bytes from Hub metadata. */
		public int64 size_bytes { get; set; default = 0; }

		/** Quantization label when known (e.g. {{{Q4_K_M}}}). */
		public string quant_label { get; set; default = ""; }

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelFile", typeof(ModelFile));
		}

		/**
		 * Resolve URL for downloading this file from the Hub CDN.
		 *
		 * @param model_ref Hub repo id {{{author/name}}}
		 * @param revision  Branch or commit (default {{{main}}})
		 * @return          {{{https://huggingface.co/{model_ref}/resolve/{rev}/{filename}}}}
		 */
		public string to_url(string model_ref, string revision = "main") {
			return "https://huggingface.co/" + model_ref
				+ "/resolve/" + revision + "/" + this.filename;
		}
	}
}
