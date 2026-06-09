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
	internal class GGUFBackend : Object
	{
		private static bool initialized = false;

		public static void ensure_initialized()
		{
			if (initialized) {
				return;
			}

			Llama.log_set(log_callback);
			Llama.backend_init();
			initialized = true;
			GLib.debug("GGUFBackend: libllama ready");
		}

		public static Llama.ModelParams model_params()
		{
			ensure_initialized();

			var model_params = Llama.ModelParams();
			if (Llama.supports_gpu_offload()) {
				model_params.n_gpu_layers = -1;
				GLib.debug("GGUFBackend: GPU offload available, offloading all layers");
			} else {
				GLib.debug("GGUFBackend: no GPU backend, using CPU");
			}

			return model_params;
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
