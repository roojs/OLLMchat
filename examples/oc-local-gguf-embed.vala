/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

async int main(string[] args)
{
	var model_path = "";
	var text = "hello from ollmchat";

	var options = new OptionEntry[] {
		{ "model", 'm', 0, OptionArg.FILENAME, ref model_path, "Path to model.gguf inside a model directory", "FILE" },
		{ "text", 't', 0, OptionArg.STRING, ref text, "Text to embed", "TEXT" },
		{ null }
	};

	try {
		var opt_context = new OptionContext("- local CallLocal.Embeddings smoke test");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);
		opt_context.parse(ref args);
	} catch (Error e) {
		stderr.printf("Option parsing failed: %s\n", e.message);
		return 1;
	}

	if (model_path == "") {
		stderr.printf("Missing --model path to a GGUF embedding model\n");
		return 1;
	}

	var model_folder = GLib.Path.get_dirname(model_path);
	var model_name = GLib.Path.get_basename(model_folder);
	var models_root = GLib.Path.get_dirname(model_folder);

	var conn = new OLLMchat.Settings.Connection() {
		name = "local",
		url = models_root,
	};

	var call = new OLLMchat.CallLocal.Embeddings(conn, model_name);
	call.input = { text };

	try {
		var embed = yield call.exec_embedding();
		stdout.printf("rows=%d width=%d\n", embed.embeddings.rows, embed.embeddings.width);
		stdout.printf("first=");
		var limit = int.min(8, embed.embeddings.width);
		for (int i = 0; i < limit; i++) {
			stdout.printf("%s%.6f", i == 0 ? "" : ",", embed.embeddings.data[i]);
		}
		stdout.printf("\n");
		return 0;
	} catch (Error e) {
		stderr.printf("Embedding failed: %s\n", e.message);
		return 1;
	}
}
