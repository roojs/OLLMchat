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
	 * One file entry from Hub model {{{siblings[]}}} (typically a {{{.gguf}}}).
	 */
	public class ModelFile : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/** Repo-relative path (Hub {{{rfilename}}}). */
		public string rfilename { get; set; default = ""; }

		/** File size in bytes (Hub {{{size}}} when present). */
		public int64 size { get; set; default = 0; }

		/** Quantization label when known (e.g. {{{Q4_K_M}}}). */
		public string quant_label { get; set; default = ""; }

		/** Bytes written so far for this sibling. */
		public int64 bytes_written { get; set; default = 0; }

		/** LFS ETag from HEAD (SHA-256) for final verify. */
		public string etag { get; set; default = ""; }

		/** Incremental SHA-256 hex while streaming (resume). */
		public string sha256_partial { get; set; default = ""; }

		/** True when this sibling is fully downloaded and verified. */
		public bool download_complete { get; set; default = false; }

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelFile", typeof(ModelFile));
		}

		/**
		 * Resolve URL for downloading this file from the Hub CDN.
		 *
		 * @param id       Hub repo id {{{author/name}}}
		 * @param revision Branch or commit (default {{{main}}})
		 * @return         Hub CDN URL {{{huggingface.co/MODEL_ID/resolve/REVISION/RFILENAME}}}
		 *                 (HTTPS scheme prefix).
		 */
		public string to_url(string id, string revision = "main") {
			return "https://huggingface.co/" + id
				+ "/resolve/" + revision + "/" + this.rfilename;
		}
	}
}
