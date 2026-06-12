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
	 * Local GGUF implementation of chat completions.
	 *
	 * Runs prompt decode and token generation on a worker thread.
	 * Streaming tokens are marshalled back to the caller context before
	 * flowing through the existing stream signals.
	 */
	public class ChatCompletions : Call.ChatCompletions, Thread
	{
		public Call.Options config_options { get; private set; default = new Call.Options(); }

		// Hard-coded DeepSeek-R1-Distill-Qwen template from Phase-1 probe.
		private const string USER_BEGIN = "\uFF5CUser\uFF5C";
		private const string ASSISTANT_BEGIN = "\uFF5CAssistant\uFF5C\n";

		private signal bool chunk_ready(
			Response.Chat resp,
			Response.Chunk chunk,
			bool emit_stream
		);
		private signal void stream_done(
			Response.Chat resp,
			Response.Chunk chunk,
			bool emit_stream
		);

		construct {
			this.chunk_ready.connect((resp, chunk, emit_stream) => {
				var token = resp.addChunk(chunk);
				if (!emit_stream) {
					return token == "" || resp.detect_looping(token);
				}

				if (resp.is_first_chunk) {
					resp.is_first_chunk = false;
					this.stream_start();
					if (this.agent != null) {
						this.agent.handle_stream_started();
					}
				}

				if (resp.new_content.length > 0) {
					this.stream_chunk(resp.new_content, false, resp);
					if (this.agent != null) {
						this.agent.handle_stream_chunk(
							resp.new_content,
							false,
							resp
						);
					}
				}

				return token == "" || resp.detect_looping(token);
			});

			this.stream_done.connect((resp, chunk, emit_stream) => {
				resp.addChunk(chunk);
				if (emit_stream) {
					this.stream_chunk("", false, resp);
					if (this.agent != null) {
						this.agent.handle_stream_chunk("", false, resp);
					}
				}
			});
		}

		/**
		 * Create a local chat completions call for a model directory.
		 *
		 * @param connection local GGUF connection
		 * @param model model directory name under the connection URL
		 * @param config_options optional local runtime options
		 */
		public ChatCompletions(
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
		 * Send messages through the local chat completions backend.
		 *
		 * @param messages chat messages to send
		 * @param cancellable optional cancellation handle for generation
		 * @return completed chat response
		 * @throws GLib.Error when validation, inference, or tools fail
		 */
		public new async Response.Chat send(
			Gee.ArrayList<Message> messages,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error
		{
			if (messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT(
					"Chat messages array is empty. Provide messages to send."
				);
			}
			this.streaming_response = new Response.Chat(this.connection, this);
			this.cancellable = cancellable;
			this.messages = messages;

			if (this.stream) {
				var response = yield this.exec_stream();
				try {
					if (response.done && response.message.tool_calls.size > 0) {
						return yield this.toolsReply(response);
					}
				} catch (GLib.Error e) {
					response.done = true;
					throw e;
				}
				return response;
			}

			var response_obj = yield this.exec();
			if (response_obj.message.tool_calls.size > 0) {
				return yield this.toolsReply(response_obj);
			}
			return response_obj;
		}

		/**
		 * Execute streaming chat generation on a worker thread.
		 *
		 * @return accumulated streaming chat response
		 * @throws GLib.Error when thread startup or inference fails
		 */
		public new async Response.Chat exec_stream() throws GLib.Error
		{
			if (this.messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT(
					"Messages are required for chat completions"
				);
			}
			var resp = (Response.Chat) this.streaming_response;
			resp.call = this;
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
			var formatted_prompt = this.format_messages(this.messages);
			var max_tokens = this.max_tokens >= 0 ?
				this.max_tokens :
				this.config_options.num_predict;
			var num_ctx = this.config_options.num_ctx;
			var seed_value = this.seed >= 0 ?
				(uint)this.seed :
				(this.config_options.seed >= 0 ?
					(uint)this.config_options.seed :
					Llama.DEFAULT_SEED);
			var cancellable = this.cancellable;
			GLib.SourceFunc callback = exec_stream.callback;
			GLib.Error? thread_error = null;

			owned GLib.ThreadFunc<bool> run = () => {
				try {
					this.generate(
						resp,
						caller_context,
						model_name,
						model_path,
						formatted_prompt,
						max_tokens,
						num_ctx,
						seed_value,
						(new GLib.DateTime.now_utc()).format(
							"%Y-%m-%dT%H:%M:%SZ"
						),
						cancellable,
						true
					);
				} catch (GLib.Error e) {
					thread_error = e;
				}
				var source = new GLib.IdleSource();
				source.set_callback((owned) callback);
				source.attach(caller_context);
				return true;
			};

			var background_thread = new GLib.Thread<bool>.try(
				"local-chat-stream",
				run
			);

			yield;
			background_thread.join();

			if (thread_error != null) {
				throw thread_error;
			}
			return resp;
		}

		/**
		 * Execute non-streaming chat generation on a worker thread.
		 *
		 * @return completed chat response
		 * @throws GLib.Error when thread startup or inference fails
		 */
		public new async Response.Chat exec() throws GLib.Error
		{
			if (this.messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT(
					"Messages are required for chat completions"
				);
			}
			var resp = new Response.Chat(this.connection, this);
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
			var formatted_prompt = this.format_messages(this.messages);
			var max_tokens = this.max_tokens >= 0 ?
				this.max_tokens :
				this.config_options.num_predict;
			var num_ctx = this.config_options.num_ctx;
			var seed_value = this.seed >= 0 ?
				(uint)this.seed :
				(this.config_options.seed >= 0 ?
					(uint)this.config_options.seed :
					Llama.DEFAULT_SEED);
			var cancellable = this.cancellable;
			GLib.SourceFunc callback = exec.callback;
			GLib.Error? thread_error = null;

			owned GLib.ThreadFunc<bool> run = () => {
				try {
					this.generate(
						resp,
						caller_context,
						model_name,
						model_path,
						formatted_prompt,
						max_tokens,
						num_ctx,
						seed_value,
						(new GLib.DateTime.now_utc()).format(
							"%Y-%m-%dT%H:%M:%SZ"
						),
						cancellable,
						false
					);
				} catch (GLib.Error e) {
					thread_error = e;
				}
				var source = new GLib.IdleSource();
				source.set_callback((owned) callback);
				source.attach(caller_context);
				return true;
			};

			var background_thread = new GLib.Thread<bool>.try(
				"local-chat",
				run
			);

			yield;
			background_thread.join();

			if (thread_error != null) {
				throw thread_error;
			}
			return resp;
		}

		private void generate(
			Response.Chat resp,
			GLib.MainContext caller_context,
			string model_name,
			string model_path,
			string formatted_prompt,
			int max_tokens,
			int num_ctx,
			uint seed_value,
			string created_at,
			GLib.Cancellable? cancellable,
			bool emit_stream
		) throws GLib.Error
		{
			var total_start = GLib.get_monotonic_time();
			GGUF.init();

			var load_start = GLib.get_monotonic_time();
			var model_params = Llama.ModelParams();
			model_params.n_gpu_layers = GGUF.n_gpu_layers;
			var model = new Llama.Model.from_file(
				model_path,
				model_params
			);
			var load_duration = GLib.get_monotonic_time() - load_start;

			GLib.debug("formatted prompt: %s", formatted_prompt);

			unowned Llama.Vocab vocab = model.get_vocab();
			var prompt_tokens = vocab.tokenize(formatted_prompt, false, true);

			var ctx_params = Llama.ContextParams();
			if (num_ctx > 0) {
				ctx_params.n_ctx = (uint)num_ctx;
			}
			ctx_params.n_batch = (uint)prompt_tokens.length;
			ctx_params.n_threads = (int)GLib.get_num_processors();
			ctx_params.n_threads_batch = ctx_params.n_threads;

			var ctx = new Llama.Context.from_model(model, ctx_params);

			var sampler = Llama.sampler_init_dist(
				seed_value
			);

			var n_cur = 0;

			var prompt_eval_start = GLib.get_monotonic_time();
			var prompt_batch = Llama.Batch(prompt_tokens.length, 0, 1);
			try {
				for (int i = 0; i < prompt_tokens.length; i++) {
					prompt_batch.token[prompt_batch.n_tokens] = prompt_tokens[i];
					prompt_batch.pos[prompt_batch.n_tokens] = n_cur + i;
					prompt_batch.n_seq_id[prompt_batch.n_tokens] = 1;
					prompt_batch.seq_id[prompt_batch.n_tokens][0] = 0;
					prompt_batch.logits[prompt_batch.n_tokens] =
						(int8)(i == prompt_tokens.length - 1 ? 1 : 0);
					prompt_batch.n_tokens++;
				}

				if (ctx.decode(prompt_batch) < 0) {
					throw new OllmError.FAILED("llama_decode failed on prompt");
				}
			} finally {
				prompt_batch.free();
			}
			var prompt_eval_duration =
				GLib.get_monotonic_time() - prompt_eval_start;
			n_cur += prompt_tokens.length;

			var eval_start = GLib.get_monotonic_time();
			var generated = 0;
			while (max_tokens < 0 || generated < max_tokens) {
				if (cancellable != null && cancellable.is_cancelled()) {
					break;
				}

				var new_token = Llama.sampler_sample(sampler, ctx, -1);
				if (new_token < 0 || vocab.is_eog(new_token)) {
					break;
				}
				Llama.sampler_accept(sampler, new_token);

				var chunk = new Response.Chunk() {
					model = model_name,
					message = new Message(
						"assistant",
						vocab.token_to_piece(new_token)
					),
				};
				generated++;

				if (!this.invoke(caller_context, () => {
					return this.chunk_ready(resp, chunk, emit_stream);
				})) {
					throw new OllmError.FAILED(
						"Streaming stopped: output repeated; possible infinite generation loop."
					);
				}

				var token_batch = Llama.Batch(1, 0, 1);
				try {
					token_batch.token[0] = new_token;
					token_batch.pos[0] = n_cur;
					token_batch.n_seq_id[0] = 1;
					token_batch.seq_id[0][0] = 0;
					token_batch.logits[0] = 1;
					token_batch.n_tokens = 1;

					if (ctx.decode(token_batch) < 0) {
						throw new OllmError.FAILED(
							"llama_decode failed during generation"
						);
					}
				} finally {
					token_batch.free();
				}
				n_cur++;
			}
			var eval_duration = GLib.get_monotonic_time() - eval_start;

			this.invoke(caller_context, () => {
				this.stream_done(
					resp,
					new Response.Chunk() {
						model = model_name,
						done = true,
						prompt_eval_count = prompt_tokens.length,
						eval_count = generated,
						total_duration =
							(GLib.get_monotonic_time() - total_start) * 1000,
						load_duration = load_duration * 1000,
						prompt_eval_duration = prompt_eval_duration * 1000,
						eval_duration = eval_duration * 1000,
						created_at = created_at,
						message = new Message("assistant", ""),
					},
					emit_stream
				);
				return false;
			});
		}

		private string format_messages(Gee.ArrayList<Message> messages)
		{
			string[] parts = {};
			foreach (var m in messages) {
				switch (m.role) {
				case "user":
				case "user-sent":
					parts += USER_BEGIN + m.content;
					continue;
				case "assistant":
				case "content-stream":
				case "content-non-stream":
					parts += ASSISTANT_BEGIN + m.content;
					continue;
				}
			}
			parts += ASSISTANT_BEGIN;
			return string.joinv("", parts);
		}
	}
}
