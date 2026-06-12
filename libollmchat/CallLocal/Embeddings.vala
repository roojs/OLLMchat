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
	/**
	 * Local GGUF implementation of embeddings calls.
	 *
	 * Runs model load, decode, and vector extraction on a per-call worker
	 * thread so callers yield instead of blocking their main context.
	 */
	public class Embeddings : Call.Embeddings, Thread
	{
		public Call.Options config_options { get; private set; default = new Call.Options(); }

		/**
		 * Create a local embeddings call for a model directory.
		 *
		 * @param connection local GGUF connection
		 * @param model model directory name under the connection URL
		 * @param config_options optional local runtime options
		 */
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

		/**
		 * Execute embeddings on a short-lived worker thread.
		 *
		 * @return embedding response populated from local GGUF output
		 * @throws GLib.Error when thread startup or inference fails
		 */
		public new async Response.Embed exec_embedding() throws GLib.Error
		{
			var caller_context = GLib.MainContext.get_thread_default();
			if (caller_context == null) {
				caller_context = GLib.MainContext.default();
			}
			var connection = this.connection;
			var model_name = this.model;
			var model_path = GLib.Path.build_filename(
				connection.url,
				model_name,
				"model.gguf"
			);
			var input = this.input[0:this.input.length];
			var num_ctx = this.config_options.num_ctx;
			var embeddings = new Response.FloatArray(0);
			bool embeddings_ready = false;
			GLib.SourceFunc callback = exec_embedding.callback;
			GLib.Error? thread_error = null;

			owned GLib.ThreadFunc<bool> run = () => {
				try {
					GGUF.init();

					var model_params = Llama.ModelParams();
					model_params.n_gpu_layers = GGUF.n_gpu_layers;
					var llama_model = new Llama.Model.from_file(
						model_path,
						model_params
					);

					var ctx_params = Llama.ContextParams();
					if (num_ctx > 0) {
						ctx_params.n_ctx = (uint)num_ctx;
					}
					ctx_params.n_threads = (int)GLib.get_num_processors();
					ctx_params.n_threads_batch = ctx_params.n_threads;
					ctx_params.pooling_type = Llama.PoolingType.MEAN;

					var ctx = new Llama.Context.from_model(llama_model, ctx_params);
					Llama.set_embeddings(ctx, true);

					var fa = new Response.FloatArray(llama_model.n_embd());

					foreach (var text in input) {
						this.embed_with_context(llama_model, ctx, text, fa);
					}

					embeddings = fa;
					embeddings_ready = true;
				} catch (GLib.Error e) {
					thread_error = e;
				}
				var source = new GLib.IdleSource();
				source.set_callback((owned) callback);
				source.attach(caller_context);
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
			if (!embeddings_ready) {
				throw new OllmError.FAILED("Local embeddings returned no data");
			}

			var embed = new Response.Embed(connection);
			embed.model = model_name;
			embed.embeddings = embeddings;
			embed.prompt_eval_count = input.length;
			return embed;
		}

		private void embed_with_context(
			Llama.Model model,
			Llama.Context ctx,
			string text,
			Response.FloatArray result
		) throws GLib.Error
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
