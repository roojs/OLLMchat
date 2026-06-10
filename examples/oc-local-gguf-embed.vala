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
	string model_path = "";
	string text = "hello from ollmchat";

	var options = new OptionEntry[] {
		{ "model", 'm', 0, OptionArg.FILENAME, ref model_path, "Path to a GGUF file", "FILE" },
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

	string model_dir = Path.get_dirname(model_path);
	string model_name = Path.get_basename(model_path);
	if (model_name.has_suffix(".gguf")) {
		model_name = model_name[0:model_name.length - 5];
	}

	var conn = new OLLMchat.Settings.Connection() {
		name = "local",
		url = model_dir,
	};

	var call = new OLLMchat.CallLocal.Embeddings(conn, model_name);
	call.input = { text };

	try {
		var embed = yield call.exec_embedding();
		stdout.printf("rows=%d width=%d\n", embed.embeddings.rows, embed.embeddings.width);
		stdout.printf("first=");
		int limit = int.min(8, embed.embeddings.width);
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
