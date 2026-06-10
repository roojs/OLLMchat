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
	/**
	 * Phase-1 local GGUF chat/generation probe backed by llama.cpp/libllama.
	 */
	public class GGUFChatProbe : Object
	{
		public string model_path { get; construct; }
		public int context_length { get; set; default = 2048; }
		public int threads { get; set; default = 0; }

		public GGUFChatProbe(string model_path)
		{
			Object(model_path: model_path);
		}

		// Hard-coded DeepSeek-R1-Distill-Qwen template for local POC testing.
		private const string USER_BEGIN = "\uFF5CUser\uFF5C";
		private const string ASSISTANT_BEGIN = "\uFF5CAssistant\uFF5C\n";

		private string format_prompt(string user_message)
		{
			return USER_BEGIN + user_message + ASSISTANT_BEGIN;
		}

		public string generate(string prompt, int max_tokens = 128) throws Error
		{
			if (this.model_path == "") {
				throw new OllmError.INVALID_ARGUMENT("GGUF model path is required");
			}
			if (prompt.strip() == "") {
				throw new OllmError.INVALID_ARGUMENT("Prompt is required");
			}
			if (max_tokens <= 0) {
				throw new OllmError.INVALID_ARGUMENT("max_tokens must be positive");
			}

			GGUF.init();

			var model_params = Llama.ModelParams();
			model_params.n_gpu_layers = GGUF.n_gpu_layers;
			var model = new Llama.Model.from_file(this.model_path, model_params);
			if (model == null) {
				throw new OllmError.FAILED("Failed to load GGUF model");
			}

			string formatted_prompt = this.format_prompt(prompt);
			GLib.debug("GGUFChatProbe: formatted prompt: %s", formatted_prompt);

			unowned Llama.Vocab vocab = model.get_vocab();
			int prompt_tokens_count = -vocab.tokenize(
				formatted_prompt,
				(int)formatted_prompt.length,
				null,
				0,
				false,
				true
			);
			if (prompt_tokens_count <= 0) {
				throw new OllmError.FAILED("Failed to count prompt tokens");
			}

			int n_ctx = this.context_length > 0 ? this.context_length : prompt_tokens_count + max_tokens;
			if (prompt_tokens_count + max_tokens > n_ctx) {
				throw new OllmError.FAILED("Prompt exceeds available context length");
			}

			var ctx_params = Llama.ContextParams();
			ctx_params.n_ctx = (uint)n_ctx;
			ctx_params.n_batch = (uint)prompt_tokens_count;
			ctx_params.n_threads = this.threads > 0 ? this.threads : (int)GLib.get_num_processors();
			ctx_params.n_threads_batch = ctx_params.n_threads;

			var ctx = new Llama.Context.from_model(model, ctx_params);
			if (ctx == null) {
				throw new OllmError.FAILED("Failed to create llama context");
			}

			var prompt_tokens = new int[prompt_tokens_count];
			prompt_tokens_count = vocab.tokenize(
				formatted_prompt,
				(int)formatted_prompt.length,
				prompt_tokens,
				prompt_tokens.length,
				false,
				true
			);
			if (prompt_tokens_count <= 0) {
				throw new OllmError.FAILED("Failed to tokenize prompt");
			}

			var sampler = Llama.sampler_init_dist(Llama.DEFAULT_SEED);
			if (sampler == null) {
				throw new OllmError.FAILED("Failed to create sampler");
			}

			var output = new StringBuilder();
			int n_cur = 0;

			var prompt_batch = Llama.Batch(prompt_tokens_count, 0, 1);
			try {
				for (int i = 0; i < prompt_tokens_count; i++) {
					prompt_batch.token[prompt_batch.n_tokens] = prompt_tokens[i];
					prompt_batch.pos[prompt_batch.n_tokens] = n_cur + i;
					prompt_batch.n_seq_id[prompt_batch.n_tokens] = 1;
					prompt_batch.seq_id[prompt_batch.n_tokens][0] = 0;
					prompt_batch.logits[prompt_batch.n_tokens] = (int8)(i == prompt_tokens_count - 1 ? 1 : 0);
					prompt_batch.n_tokens++;
				}

				if (ctx.decode(prompt_batch) < 0) {
					throw new OllmError.FAILED("llama_decode failed on prompt");
				}
			} finally {
				prompt_batch.free();
			}
			n_cur += prompt_tokens_count;

			int generated = 0;
			while (generated < max_tokens) {
				int new_token = Llama.sampler_sample(sampler, ctx, -1);
				if (new_token < 0 || vocab.is_eog(new_token)) {
					break;
				}
				Llama.sampler_accept(sampler, new_token);

				var piece_buf = new char[128];
				int piece_len = vocab.token_to_piece(new_token, piece_buf, piece_buf.length, 0, true);
				if (piece_len < 0) {
					throw new OllmError.FAILED("Failed to convert token to text");
				}

				output.append_len((string)piece_buf, piece_len);
				generated++;

				var token_batch = Llama.Batch(1, 0, 1);
				try {
					token_batch.token[0] = new_token;
					token_batch.pos[0] = n_cur;
					token_batch.n_seq_id[0] = 1;
					token_batch.seq_id[0][0] = 0;
					token_batch.logits[0] = 1;
					token_batch.n_tokens = 1;

					if (ctx.decode(token_batch) < 0) {
						throw new OllmError.FAILED("llama_decode failed during generation");
					}
				} finally {
					token_batch.free();
				}
				n_cur++;
			}

			return output.str;
		}
	}
}
