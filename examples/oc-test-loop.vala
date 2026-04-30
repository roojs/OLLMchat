/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Read a text file, split on whitespace (one streaming delta per word), and
 * run the same check_back_token logic as Call.Chat (newest-first, cap 100).
 *
 *   oc-test-loop <file>
 */

class DummyChatCall : GLib.Object, OLLMchat.Call.ChatInterface {
	public async OLLMchat.Response.Chat send_append(
			Gee.ArrayList<OLLMchat.Message> new_messages,
			GLib.Cancellable? cancellable = null) throws GLib.Error {
		throw new OLLMchat.OllmError.INVALID_ARGUMENT("dummy");
	}
}

static void push_delta(OLLMchat.Response.Chat r, string token)
{
	if (token.length == 0) {
		return;
	}
	r.back_tokens.insert(0, token);
	if (r.back_tokens.size > 100) {
		r.back_tokens.remove_at(r.back_tokens.size - 1);
	}
}

static string[] split_words(string contents)
{
	string[] raw = Regex.split_simple("\\s+", contents);
	var list = new Gee.ArrayList<string>();
	foreach (string w in raw) {
		if (w.length > 0) {
			list.add(w);
		}
	}
	return list.to_array();
}

int main(string[] args)
{
	if (args.length != 2) {
		return 1;
	}

	try {
		string contents;
		FileUtils.get_contents(args[1], out contents);
		string[] chunks = split_words(contents);
		var r = new OLLMchat.Response.Chat(null, new DummyChatCall());

		bool any_loop = false;
		int first_loop_delta = -1;
		for (int i = 0; i < chunks.length; i++) {
			push_delta(r, chunks[i]);
			if (!r.check_back_token()) {
				if (!any_loop) {
					first_loop_delta = i + 1;
				}
				any_loop = true;
			}
		}

		stdout.printf("File: %s\n", args[1]);
		stdout.printf("Deltas: %d\n", chunks.length);
		if (any_loop) {
			stdout.printf("Loop detection: YES\n");
			stdout.printf("First failing delta (1-based): %d\n", first_loop_delta);
		} else {
			stdout.printf("Loop detection: NO\n");
		}
		return 0;
	} catch (FileError e) {
		return 1;
	}
}
