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
	string prompt = "Hello, who are you?";
	int max_tokens = 128;
	int context_length = 2048;
	int threads = 0;

	var options = new OptionEntry[] {
		{ "model", 'm', 0, OptionArg.FILENAME, ref model_path, "Path to a GGUF chat model", "FILE" },
		{ "prompt", 'p', 0, OptionArg.STRING, ref prompt, "Prompt text", "TEXT" },
		{ "max-tokens", 'n', 0, OptionArg.INT, ref max_tokens, "Tokens to generate", "N" },
		{ "ctx", 0, 0, OptionArg.INT, ref context_length, "Context length", "TOKENS" },
		{ "threads", 0, 0, OptionArg.INT, ref threads, "Worker threads, 0 = lib default", "N" },
		{ null }
	};

	try {
		var opt_context = new OptionContext("- load a GGUF with libllama and print a short completion");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);
		opt_context.parse(ref args);
	} catch (Error e) {
		stderr.printf("Option parsing failed: %s\n", e.message);
		return 1;
	}

	if (model_path == "") {
		stderr.printf("Missing --model path to a GGUF chat model\n");
		return 1;
	}

	var probe = new OLLMchat.Local.GGUFChatProbe(model_path) {
		context_length = context_length,
		threads = threads
	};

	try {
		string completion = probe.generate(prompt, max_tokens);
		stdout.printf("%s\n", completion);
		return 0;
	} catch (Error e) {
		stderr.printf("Generation failed: %s\n", e.message);
		return 1;
	}
}
