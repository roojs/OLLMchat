/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

int main(string[] args)
{
	string model_path = "";
	string text = "hello from ollmchat";
	int context_length = 2048;
	int threads = 0;
	string pooling = "mean";

	var options = new OptionEntry[] {
		{ "model", 'm', 0, OptionArg.FILENAME, ref model_path, "Path to a GGUF embedding model", "FILE" },
		{ "text", 't', 0, OptionArg.STRING, ref text, "Text to embed", "TEXT" },
		{ "ctx", 0, 0, OptionArg.INT, ref context_length, "Context length", "TOKENS" },
		{ "threads", 0, 0, OptionArg.INT, ref threads, "Worker threads, 0 = lib default", "N" },
		{ "pooling", 0, 0, OptionArg.STRING, ref pooling, "Pooling: mean, cls, last, none", "MODE" },
		{ null }
	};

	try {
		var opt_context = new OptionContext("- load a GGUF with libllama and print one embedding");
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

	var probe = new OLLMchat.Local.GGUFEmbeddingProbe(model_path) {
		context_length = context_length,
		threads = threads,
		pooling = parse_pooling(pooling)
	};

	try {
		var embeddings = probe.embed_text(text);
		stdout.printf("rows=%d width=%d\n", embeddings.rows, embeddings.width);
		stdout.printf("first=");
		int limit = int.min(8, embeddings.width);
		for (int i = 0; i < limit; i++) {
			stdout.printf("%s%.6f", i == 0 ? "" : ",", embeddings.data[i]);
		}
		stdout.printf("\n");
		return 0;
	} catch (Error e) {
		stderr.printf("Embedding failed: %s\n", e.message);
		return 1;
	}
}

private OLLMchat.Local.GGUFPooling parse_pooling(string value)
{
	switch (value.down()) {
		case "none":
			return OLLMchat.Local.GGUFPooling.NONE;
		case "cls":
			return OLLMchat.Local.GGUFPooling.CLS;
		case "last":
			return OLLMchat.Local.GGUFPooling.LAST;
		case "mean":
			return OLLMchat.Local.GGUFPooling.MEAN;
		default:
			return OLLMchat.Local.GGUFPooling.MEAN;
	}
}
