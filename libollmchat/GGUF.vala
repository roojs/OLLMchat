/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMchat
{
	internal class GGUF : Object
	{
		private static bool initialized = false;

		/** Set from init(); 0 = CPU only, -1 = offload all layers when GPU is available. */
		internal static int n_gpu_layers = 0;

		public static void init()
		{
			if (initialized) {
				return;
			}

			Llama.log_set(log_callback);
			Llama.backend_init();

			if (Llama.supports_gpu_offload()) {
				n_gpu_layers = -1;
				GLib.debug("GGUF: GPU offload available, offloading all layers");
			} else {
				GLib.debug("GGUF: no GPU backend, using CPU");
			}

			initialized = true;
		}

		[CCode (callback = true)]
		private static void log_callback(Llama.LogLevel level, string text, void* user_data)
		{
			if (level == Llama.LogLevel.NONE || text == "") {
				return;
			}

			if (level == Llama.LogLevel.ERROR) {
				GLib.warning("libllama: %s", text);
			} else {
				GLib.debug("libllama: %s", text);
			}
		}
	}
}
