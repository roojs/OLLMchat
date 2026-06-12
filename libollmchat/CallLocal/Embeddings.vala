/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMchat.CallLocal
{
	public class Embeddings : Call.Embeddings, Thread
	{
		public Call.Options config_options { get; private set; default = new Call.Options(); }
		protected GLib.MainContext caller_context { get; set; default = GLib.MainContext.default(); }

		public Embeddings(
			Settings.Connection connection,
			string model,
			Call.Options? config_options = null
		)
		{
			base(connection, model);
			if (config_options != null) {
				this.config_options = config_options;
			}
		}

		public new async Response.Embed exec_embedding() throws Error
		{
			this.capture_caller_context();
			var embed = new Response.Embed(this.connection);
			GLib.SourceFunc callback = exec_embedding.callback;
			GLib.Error? thread_error = null;

			owned GLib.ThreadFunc<bool> run = () => {
				try {
					GGUF.init();

					var model_params = Llama.ModelParams();
					model_params.n_gpu_layers = GGUF.n_gpu_layers;
					var llama_model = new Llama.Model.from_file(
						GLib.Path.build_filename(
							this.connection.url,
							this.model,
							"model.gguf"
						),
						model_params
					);

					var ctx_params = Llama.ContextParams();
					if (this.config_options.num_ctx > 0) {
						ctx_params.n_ctx = (uint)this.config_options.num_ctx;
					}
					ctx_params.n_threads = (int)GLib.get_num_processors();
					ctx_params.n_threads_batch = ctx_params.n_threads;
					ctx_params.pooling_type = Llama.PoolingType.MEAN;

					var ctx = new Llama.Context.from_model(llama_model, ctx_params);
					Llama.set_embeddings(ctx, true);

					var fa = new Response.FloatArray(llama_model.n_embd());

					foreach (var text in this.input) {
						this.embed_with_context(llama_model, ctx, text, fa);
					}

					embed.model = this.model;
					embed.embeddings = fa;
					embed.prompt_eval_count = this.input.length;
				} catch (GLib.Error e) {
					thread_error = e;
				}
				this.caller_context.invoke((owned) callback);
				return true;
			};

			var background_thread = new GLib.Thread<bool>.try(
				"local-embedding",
				run
			);

			yield;
			background_thread.join();

			if (thread_error != null) {
				throw thread_error;
			}

			return embed;
		}

		private void embed_with_context(
			Llama.Model model,
			Llama.Context ctx,
			string text,
			Response.FloatArray result
		) throws Error
		{
			unowned Llama.Vocab vocab = model.get_vocab();
			var tokens = vocab.tokenize(text, true, true);

			var batch = Llama.Batch(tokens.length, 0, 1);
			try {
				for (int i = 0; i < tokens.length; i++) {
					batch.token[batch.n_tokens] = tokens[i];
					batch.pos[batch.n_tokens] = i;
					batch.n_seq_id[batch.n_tokens] = 1;
					batch.seq_id[batch.n_tokens][0] = 0;
					batch.logits[batch.n_tokens] = 1;
					batch.n_tokens++;
				}

				if (ctx.decode(batch) < 0) {
					throw new OllmError.FAILED("llama_decode failed");
				}

				unowned float* embedding = ctx.get_embeddings_seq(0);
				if (embedding == null) {
					embedding = ctx.get_embeddings_ith(tokens.length - 1);
				}
				if (embedding == null) {
					embedding = ctx.get_embeddings();
				}

				var dimension = model.n_embd();
				var vector = new float[dimension];
				for (int i = 0; i < dimension; i++) {
					vector[i] = embedding[i];
				}

				result.add(vector);
				result.normalize_vector_at(result.rows - 1);
			} finally {
				batch.free();
			}
		}
	}
}
