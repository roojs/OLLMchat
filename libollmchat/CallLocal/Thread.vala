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
	public delegate void InferenceWork() throws GLib.Error;
	public delegate GLib.Object InferenceWorkWithResult() throws GLib.Error;
	public delegate void CallerContextWork();

	private class ThreadDispatch : GLib.Object
	{
		private static GLib.Mutex contexts_mutex = GLib.Mutex();
		private static Gee.HashMap<GLib.Object, GLib.MainContext> contexts =
			new Gee.HashMap<GLib.Object, GLib.MainContext>();

		public static void set_context(
			GLib.Object owner,
			GLib.MainContext context
		)
		{
			contexts_mutex.lock();
			contexts.set(owner, context);
			contexts_mutex.unlock();
		}

		public static bool context(
			GLib.Object owner,
			out GLib.MainContext context
		)
		{
			contexts_mutex.lock();
			if (!contexts.has_key(owner)) {
				contexts_mutex.unlock();
				context = GLib.MainContext.default();
				return false;
			}
			context = contexts.get(owner);
			contexts_mutex.unlock();
			return true;
		}

		public static void clear_context(GLib.Object owner)
		{
			contexts_mutex.lock();
			contexts.unset(owner);
			contexts_mutex.unlock();
		}
	}

	/**
	 * Shared per-call threading for local GGUF inference.
	 *
	 * Implementing classes run synchronous libllama work on a short-lived
	 * background thread. The async caller yields until the worker finishes,
	 * while token streaming callbacks are marshalled to the caller context.
	 */
	public interface Thread : GLib.Object
	{
		/**
		 * Run synchronous inference work on a per-call background thread.
		 *
		 * @param work synchronous local inference body
		 * @param cancellable optional cancellable checked before dispatch
		 * @throws GLib.Error when thread startup or inference fails
		 */
		protected virtual async void run_on_background_thread(
			owned InferenceWork work,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error
		{
			if (cancellable != null && cancellable.is_cancelled()) {
				throw new GLib.IOError.CANCELLED("Operation was cancelled");
			}

			var caller_context = GLib.MainContext.get_thread_default();
			if (caller_context == null) {
				caller_context = GLib.MainContext.default();
			}
			ThreadDispatch.set_context((GLib.Object) this, caller_context);

			GLib.SourceFunc callback = run_on_background_thread.callback;
			GLib.Error? thread_error = null;
			GLib.Thread<bool> background_thread =
				new GLib.Thread<bool>.try("local-inference", () => {
					try {
						work();
					} catch (GLib.Error e) {
						thread_error = e;
					}
					caller_context.invoke((owned) callback);
					return true;
				});

			yield;
			background_thread.join();
			ThreadDispatch.clear_context((GLib.Object) this);

			if (thread_error != null) {
				throw thread_error;
			}
		}

		/**
		 * Run synchronous inference work and return its result.
		 *
		 * @param work synchronous local inference body returning a result
		 * @param cancellable optional cancellable checked before dispatch
		 * @return result produced by the background worker
		 * @throws GLib.Error when thread startup or inference fails
		 */
		protected virtual async GLib.Object run_on_background_thread_with_result(
			owned InferenceWorkWithResult work,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error
		{
			GLib.Object? result = null;
			yield this.run_on_background_thread(() => {
				result = work();
			}, cancellable);

			if (result == null) {
				throw new OllmError.FAILED(
					"Background inference completed without a result"
				);
			}
			return result;
		}

		/**
		 * Invoke a callback on the context that started the local call.
		 *
		 * The worker waits until the callback has run so streaming state and
		 * UI notifications advance one token at a time on the caller thread.
		 *
		 * @param work callback to run on the caller context
		 */
		protected virtual void invoke_on_caller_context(
			owned CallerContextWork work
		)
		{
			GLib.MainContext caller_context;
			if (!ThreadDispatch.context((GLib.Object) this, out caller_context)) {
				work();
				return;
			}

			var mutex = GLib.Mutex();
			var cond = GLib.Cond();
			bool done = false;

			caller_context.invoke(() => {
				work();
				mutex.lock();
				done = true;
				cond.signal();
				mutex.unlock();
				return false;
			});

			mutex.lock();
			while (!done) {
				cond.wait(mutex);
			}
			mutex.unlock();
		}
	}
}
