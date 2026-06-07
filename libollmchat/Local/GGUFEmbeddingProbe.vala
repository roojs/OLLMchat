/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMchat.Local
{
	public enum GGUFPooling
	{
		UNSPECIFIED,
		NONE,
		MEAN,
		CLS,
		LAST
	}

	/**
	 * Phase-1 local GGUF embedding probe backed by llama.cpp/libllama.
	 *
	 * This is intentionally narrow: it proves the distro library can load a GGUF
	 * and produce one embedding without defining the full libollmchat backend yet.
	 */
	public class GGUFEmbeddingProbe : Object
	{
		public string model_path { get; construct; }
		public int context_length { get; set; default = 2048; }
		public int threads { get; set; default = 0; }
		public GGUFPooling pooling { get; set; default = GGUFPooling.MEAN; }

		public GGUFEmbeddingProbe(string model_path)
		{
			Object(model_path: model_path);
		}

		public Response.FloatArray embed_text(string text) throws Error
		{
			if (this.model_path == "") {
				throw new OllmError.INVALID_ARGUMENT("GGUF model path is required");
			}
			if (text.strip() == "") {
				throw new OllmError.INVALID_ARGUMENT("Embedding text is required");
			}

			string? error_message = null;
			var embedding = OllmchatLlamaProbe.embed_text(
				this.model_path,
				text,
				this.context_length,
				this.threads,
				this.to_probe_pooling(this.pooling),
				out error_message
			);
			if (embedding == null) {
				throw new OllmError.FAILED(
					error_message != null ? error_message : "Local GGUF embedding failed"
				);
			}

			var vector = new float[embedding.length()];
			for (int i = 0; i < vector.length; i++) {
				vector[i] = embedding.get(i);
			}

			var result = new Response.FloatArray(vector.length);
			result.add(vector);
			return result;
		}

		private OllmchatLlamaProbe.Pooling to_probe_pooling(GGUFPooling pooling)
		{
			switch (pooling) {
				case GGUFPooling.NONE:
					return OllmchatLlamaProbe.Pooling.NONE;
				case GGUFPooling.CLS:
					return OllmchatLlamaProbe.Pooling.CLS;
				case GGUFPooling.LAST:
					return OllmchatLlamaProbe.Pooling.LAST;
				case GGUFPooling.MEAN:
					return OllmchatLlamaProbe.Pooling.MEAN;
				case GGUFPooling.UNSPECIFIED:
				default:
					return OllmchatLlamaProbe.Pooling.UNSPECIFIED;
			}
		}
	}
}
