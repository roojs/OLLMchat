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
	 * ''GLib.ThreadFunc'', then resume the caller context.
	 */
	public interface Thread : GLib.Object
	{
		/**
		 * Invoke a callback on the context that started the local call.
		 *
		 * The worker waits until the callback has run so streaming state and
		 * UI notifications advance one token at a time on the caller thread.
		 *
		 * @param caller_context context that receives the callback
		 * @param callback callback to run on the caller context
		 * @return value returned by the callback
		 */
		protected virtual bool invoke(
			GLib.MainContext caller_context,
			owned GLib.SourceFunc callback
		)
		{
			var mutex = GLib.Mutex();
			var cond = GLib.Cond();
			bool done = false;
			bool keep_source = false;

			var source = new GLib.IdleSource();
			source.set_callback(() => {
				var callback_result = callback();
				mutex.lock();
				keep_source = callback_result;
				done = true;
				cond.signal();
				mutex.unlock();
				return false;
			});
			source.attach(caller_context);

			mutex.lock();
			while (!done) {
				cond.wait(mutex);
			}
			mutex.unlock();
			return keep_source;
		}
	}
}
