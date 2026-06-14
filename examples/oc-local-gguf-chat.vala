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
	var prompt = "Hello, who are you?";
	var max_tokens = 128;

	var options = new OptionEntry[] {
		{ "model", 'm', 0, OptionArg.FILENAME, ref model_path, "Path to model.gguf inside a model directory", "FILE" },
		{ "prompt", 'p', 0, OptionArg.STRING, ref prompt, "Prompt text", "TEXT" },
		{ "max-tokens", 'n', 0, OptionArg.INT, ref max_tokens, "Tokens to generate", "N" },
		{ null }
	};

	try {
		var opt_context = new OptionContext("- local CallLocal.ChatCompletions smoke test");
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

	var model_folder = GLib.Path.get_dirname(model_path);
	var model_name = GLib.Path.get_basename(model_folder);
	var models_root = GLib.Path.get_dirname(model_folder);

	var conn = new OLLMchat.Settings.Connection() {
		name = "local",
		url = models_root,
	};

	var call = new OLLMchat.CallLocal.ChatCompletions(conn, model_name);
	call.stream = false;
	call.max_tokens = max_tokens;
	call.messages.add(new OLLMchat.Message("user", prompt));

	try {
		var response = yield call.send(call.messages);
		stdout.printf("%s\n", response.message.content);
		return 0;
	} catch (Error e) {
		stderr.printf("Generation failed: %s\n", e.message);
		return 1;
	}
}
