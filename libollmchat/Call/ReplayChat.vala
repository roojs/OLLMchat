/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMchat.Call
{
	/**
	 * Chat implementation that returns replayed content instead of calling the LLM.
	 * Takes the raw message list; each send() returns the next relevant message's content,
	 * skipping roles that are not LLM content (e.g. ui, system, project).
	 * Used by tests to drive the real Runner/List flow with session messages.
	 */
	public class ReplayChat : Chat
	{
		private Gee.ArrayList<Message> replay_messages;
		private int replay_index { get; set; default = 0; }
		private Gee.HashSet<int> run_issues { get; set; default = new Gee.HashSet<int>(); }

		/**
		 * Array index of the content message last returned by send(); -1 if
		 * none yet.
		 */
		public int last_return_ix { get; private set; default = -1; }

		public ReplayChat(
				Settings.Connection connection,
				string model,
				Gee.ArrayList<Message> replay_messages)
		{
			base(connection, model);
			this.replay_messages = replay_messages;
			this.stream = false;
			var state = -1;
			for (var i = 0; i < this.replay_messages.size; i++) {
				var m = this.replay_messages.get(i);
				if (m.role == "content-stream" || m.role == "content-non-stream" || m.role == "assistant") {
					if (m.content != "") {
						state = i;
					}
					continue;
				}
				if ((m.role == "ui" || m.role == "ui-warning") && state >= 0
					&& ((m.content ?? "").contains("had issues")
						|| (m.content ?? "").contains("Task list had issues")
						|| ((m.content ?? "").contains("Executor") && (m.content ?? "").contains("failed")))) {
					this.run_issues.add(state);
				}
			}
		}

		/**
		 * Compare replay parse outcome with what the live run did for the last
		 * returned content. replay_issues is the parser issues string (non-empty
		 * means replay had issues). Uses last_returned_content_index from the
		 * most recent send(). On mismatch (live had issues but replay did not,
		 * or the reverse), report and exit; replay cannot be recovered when
		 * outcomes diverge.
		 *
		 * @param replay_issues parser issues string, or empty string if none
		 */
		public void report_replay_outcome(string replay_issues = "")
		{
			var content_preview = "";
			if (this.last_return_ix >= 0 && this.last_return_ix < this.replay_messages.size) {
				content_preview = this.replay_messages.get(this.last_return_ix).content ?? "";
			}
			if (this.run_issues.contains(this.last_return_ix) && replay_issues == "") {
				var live_reported = "";
				for (var j = this.last_return_ix + 1; j < this.replay_messages.size; j++) {
					var n = this.replay_messages.get(j);
					if (n.role == "content-stream" || n.role == "content-non-stream"
						|| n.role == "think-stream" || n.role == "assistant") {
						break;
					}
					if ((n.role == "ui" || n.role == "ui-warning")
						&& (n.content ?? "").contains("had issues")) {
						live_reported = n.content ?? "";
						break;
					}
				}
				GLib.printerr(@"Replay fatal: array index $(this.last_return_ix): live run had issues here but replay did not.

Content replayed:
---
$(content_preview)
---

Live run reported:
$(live_reported)
");
				GLib.Process.exit(1);
			}
			if (!this.run_issues.contains(this.last_return_ix) && replay_issues != "") {
				GLib.printerr(@"Replay fatal: array index $(this.last_return_ix): live run had no issues here but replay did.

Content replayed:
---
$(content_preview)
---

Replay parse issues:
$(replay_issues)
");
				GLib.Process.exit(1);
			}
		}

		public override async Response.Chat send(Gee.ArrayList<Message> messages, GLib.Cancellable? cancellable = null)
		{
			if (messages.size == 0) {
				GLib.printerr("Chat messages array is empty. Provide messages to send.\n");
				Process.exit(1);
			}
			while (this.replay_index < this.replay_messages.size) {
				var msg = this.replay_messages.get(this.replay_index);
				var idx = this.replay_index;
				this.replay_index++;
				if (msg.role != "content-stream" && msg.role != "content-non-stream"
					&& msg.role != "assistant") {
					continue;
				}
				if (msg.content == "") {
					continue;
				}
				this.last_return_ix = idx;
				this.messages = messages;
				var response = new Response.Chat(this.connection, this);
				response.message = new Message("assistant", msg.content);
				response.message.idx = msg.idx;
				GLib.debug(
					"replay send array_ix=%d msg.idx=%d role=%s len=%d",
					idx,
					msg.idx,
					msg.role,
					msg.content.length);
				response.done = true;
				return response;
			}
			GLib.debug("No more content messages replay_index=%d total=%d",
				this.replay_index, (int) this.replay_messages.size);
			GLib.printerr("Replay: no more content messages.\n");
			GLib.Process.exit(1);
		}
	}
}
