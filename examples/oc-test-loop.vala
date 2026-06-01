/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Read a text file, split on whitespace (one streaming delta per word), and
 * run the same detect_looping logic as Call.Chat (check before prepend, cap 200).
 *
 *   oc-test-loop <file>
 */

class DummyChatCall : OLLMchat.Call.ChatBase {
	public override string model { get; set; default = "dummy"; }
	public override OLLMchat.Call.Options options { get; set; default = new OLLMchat.Call.Options(); }

	public DummyChatCall()
	{
		base(null);
	}

	public override async OLLMchat.Response.Chat send(
			Gee.ArrayList<OLLMchat.Message> messages,
			GLib.Cancellable? cancellable = null) throws GLib.Error {
		throw new OLLMchat.OllmError.INVALID_ARGUMENT("dummy");
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
			if (!r.detect_looping(chunks[i])) {
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
