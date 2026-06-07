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
		private static bool backend_initialized = false;

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

			if (!backend_initialized) {
				Llama.backend_init();
				backend_initialized = true;
			}

			var model_params = Llama.model_default_params();
			unowned Llama.Model? model = Llama.model_load_from_file(this.model_path, model_params);
			if (model == null) {
				throw new OllmError.FAILED("Failed to load GGUF model");
			}

			var ctx_params = Llama.context_default_params();
			ctx_params.embeddings = true;
			ctx_params.pooling_type = this.to_llama_pooling(this.pooling);
			ctx_params.n_ctx = this.context_length > 0 ? this.context_length : 2048;
			ctx_params.n_threads = this.threads > 0 ? this.threads : (int)GLib.get_num_processors();
			ctx_params.n_threads_batch = ctx_params.n_threads;

			unowned Llama.Context? ctx = Llama.init_from_model(model, ctx_params);
			if (ctx == null) {
				Llama.model_free(model);
				throw new OllmError.FAILED("Failed to create llama context");
			}

			try {
				return this.embed_with_context(model, ctx, text, (int)ctx_params.n_ctx);
			} finally {
				Llama.free(ctx);
				Llama.model_free(model);
			}
		}

		private Response.FloatArray embed_with_context(
			Llama.Model model,
			Llama.Context ctx,
			string text,
			int context_length
		) throws Error
		{
			unowned Llama.Vocab vocab = Llama.model_get_vocab(model);
			int token_count = -Llama.tokenize(
				vocab,
				text,
				(int)text.length,
				null,
				0,
				true,
				true
			);
			if (token_count <= 0) {
				throw new OllmError.FAILED("Failed to count prompt tokens");
			}
			if (token_count > context_length) {
				throw new OllmError.FAILED("Prompt exceeds embedding context length");
			}

			var tokens = new int[token_count];
			token_count = Llama.tokenize(
				vocab,
				text,
				(int)text.length,
				tokens,
				tokens.length,
				true,
				true
			);
			if (token_count <= 0 || token_count > tokens.length) {
				throw new OllmError.FAILED("Failed to tokenize prompt");
			}

			var batch = Llama.batch_init(token_count, 0, 1);
			try {
				for (int i = 0; i < token_count; i++) {
					batch.token[i] = tokens[i];
					batch.pos[i] = i;
					batch.n_seq_id[i] = 1;
					batch.seq_id[i][0] = 0;
					batch.logits[i] = (int8)(i == token_count - 1 ? 1 : 0);
				}

				if (Llama.decode(ctx, batch) < 0) {
					throw new OllmError.FAILED("llama_decode failed");
				}

				unowned float* embedding = Llama.get_embeddings_seq(ctx, 0);
				if (embedding == null) {
					embedding = Llama.get_embeddings_ith(ctx, token_count - 1);
				}
				if (embedding == null) {
					embedding = Llama.get_embeddings(ctx);
				}
				if (embedding == null) {
					throw new OllmError.FAILED("Model did not return embeddings");
				}

				int dimension = Llama.model_n_embd(model);
				var vector = new float[dimension];
				for (int i = 0; i < dimension; i++) {
					vector[i] = embedding[i];
				}

				var result = new Response.FloatArray(dimension);
				result.add(vector);
				result.normalize_vector_at(0);
				return result;
			} finally {
				Llama.batch_free(batch);
			}
		}

		private Llama.PoolingType to_llama_pooling(GGUFPooling pooling)
		{
			switch (pooling) {
				case GGUFPooling.NONE:
					return Llama.PoolingType.NONE;
				case GGUFPooling.CLS:
					return Llama.PoolingType.CLS;
				case GGUFPooling.LAST:
					return Llama.PoolingType.LAST;
				case GGUFPooling.MEAN:
					return Llama.PoolingType.MEAN;
				case GGUFPooling.UNSPECIFIED:
				default:
					return Llama.PoolingType.UNSPECIFIED;
			}
		}
	}
}
