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
	 * Shared per-call threading for local GGUF inference.
	 *
	 * Implementing classes create short-lived worker threads in the same
	 * shape as existing scanner code: save the async callback, run a
	 * {{{GLib.ThreadFunc}}}, then resume the caller context when complete.
	 */
	public interface Thread : GLib.Object
	{
		/**
		 * Context that started the current local call.
		 */
		protected abstract GLib.MainContext caller_context { get; set; }

		protected virtual void capture_caller_context()
		{
			this.caller_context = GLib.MainContext.get_thread_default();
			if (this.caller_context == null) {
				this.caller_context = GLib.MainContext.default();
			}
		}

		/**
		 * Invoke a callback on the context that started the local call.
		 *
		 * The worker waits until the callback has run so streaming state and
		 * UI notifications advance one token at a time on the caller thread.
		 *
		 * @param callback callback to run on the caller context
		 */
		protected virtual void invoke_on_caller_context(
			owned GLib.SourceFunc callback
		)
		{
			var mutex = GLib.Mutex();
			var cond = GLib.Cond();
			bool done = false;

			this.caller_context.invoke(() => {
				callback();
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
