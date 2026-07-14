/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMchat.Agent
{
	/**
	 * Background conversation summarizer for agents with summary history.
	 *
	 * Shared by Chatter and Coding Assistant. Extends {@link Base} so
	 * {@link Call.ChatCompletions} streams through {@link handle_stream_chunk}
	 * instead of a manual signal hook. Overrides streaming handlers to persist
	 * ''summary'' messages rather than ''content-stream'' rows.
	 */
	public class Summarizer : Base
	{
		private Message? draft_summary;
		private bool waiting_shown;
		private static GLib.Regex hash_ref_regex;

		static construct
		{
			hash_ref_regex = new GLib.Regex("^(user|think|agent|tool)-[0-9]+$");
		}

		/**
		 * @param agent the main agent whose factory and session drive summarization
		 */
		public Summarizer(Base agent)
		{
			base(agent.factory, agent.session);
			this.chat_call.think = false;
			this.chat_call.tools.clear();
		}

		/**
		 * Show background summarizing wait once per attempt (ui-waiting-bg; does not block input).
		 */
		public override void handle_stream_started()
		{
			if (this.waiting_shown) {
				return;
			}
			this.waiting_shown = true;
			this.session.manager.message_added(
				new Message("ui-waiting-bg", "summarizing conversation"),
				this.session);
		}

		/**
		 * Stream summary text into a ''summary'' transcript message.
		 *
		 * Does not call {@link Base.handle_stream_chunk} — the default session
		 * path creates ''content-stream'' messages.
		 */
		public override void handle_stream_chunk(
			string new_text,
			bool is_thinking,
			Response.Chat response)
		{
			if (is_thinking) {
				return;
			}
			if (new_text.length == 0 && !response.done) {
				return;
			}
			if (this.draft_summary == null) {
				this.draft_summary = new Message("summary", new_text);
				this.session.messages.add(this.draft_summary);
				this.session.notify_property("display_info");
			} else if (new_text.length > 0) {
				this.draft_summary.content += new_text;
			}
			if (response.done
				&& response.message != null
				&& response.message.content != "") {
				this.draft_summary.content = response.message.content;
			}
			if (response.done && this.draft_summary != null) {
				this.session.manager.message_added(this.draft_summary, this.session);
			}
		}

		/**
		 * Summarize the completed turn.
		 *
		 * Scans session.messages for the latest user-sent row at run time.
		 * Builds turn-reference payload, calls the model with tools and
		 * thinking disabled, streams into a ''summary'' message, and
		 * validates hash links (one retry on failure).
		 *
		 * @param cancellable optional cancel token for the summary request
		 */
		public async void run(
			GLib.Cancellable? cancellable = null)
		{
			var user_sent_index = 0;
			for (int i = this.session.messages.size - 1; i >= 0; i--) {
				if (this.session.messages.get(i).role == "user-sent") {
					user_sent_index = i;
					break;
				}
			}

			var turn_end = this.session.messages.size;
			if (user_sent_index >= turn_end) {
				GLib.debug("summarize early return no user-sent user_sent_index=%d turn_end=%d",
					user_sent_index, turn_end);
				return;
			}

			var previous_summary = "";
			foreach (var msg in this.session.messages) {
				if (msg.role == "summary") {
					previous_summary = msg.content;
				}
			}

			var allowed = new Gee.HashSet<string>();
			var prev_render = new Markdown.Document.Render();
			prev_render.parse(previous_summary);
			foreach (var link in prev_render.document.links) {
				if (link.path != "" || link.hash == "") {
					continue;
				}
				allowed.add(link.hash);
			}

			var turn_references = "";
			for (var i = user_sent_index; i < turn_end; i++) {
				var msg = this.session.messages.get(i);
				var n = i.to_string();
				switch (msg.role) {
					case "user-sent":
						allowed.add("user-" + n);
						turn_references += "### User ([#user-" + n + "](#user-" + n + "))\n\n"
							+ Message.fenced("text", msg.content);
						break;
					case "user":
						allowed.add("user-" + n);
						break;
					case "think-stream":
						allowed.add("think-" + n);
						turn_references += "### Thinking ([#think-" + n + "](#think-" + n + "))\n\n"
							+ Message.fenced("text", msg.content);
						break;
					case "content-stream":
						if (msg.content.strip() == "") {
							break;
						}
						allowed.add("agent-" + n);
						turn_references += "### Assistant ([#agent-" + n + "](#agent-" + n + "))\n\n"
							+ Message.fenced("text", msg.content);
						break;
					case "assistant":
						if (msg.tool_calls.size == 0) {
							break;
						}
						allowed.add("tool-" + n);
						turn_references += "### Tool call ([#tool-" + n + "](#tool-" + n + "))\n\n";
						foreach (var tool_call in msg.tool_calls) {
							var args_node = new Json.Node(Json.NodeType.OBJECT);
							args_node.set_object(tool_call.function.arguments);
							var args_gen = new Json.Generator();
							args_gen.set_root(args_node);
							turn_references += tool_call.function.name + "\n"
								+ Message.fenced("json", args_gen.to_data(null));
						}
						break;
					case "tool":
						allowed.add("tool-" + n);
						turn_references += "### Tool result ([#tool-" + n + "](#tool-" + n + "))\n\n"
							+ Message.fenced("text", msg.name + "\n" + msg.content);
						break;
				}
			}

			var allowed_references = "";
			foreach (var hash in allowed) {
				allowed_references += "- [#" + hash + "](#" + hash + ")\n";
			}

			var usage = this.session.model_usage;
			if (usage.connection == ""
				|| !this.session.manager.config.connections.has_key(usage.connection)) {
				GLib.debug("summarize early return no connection");
				return;
			}

			var validation_issue = "";
			for (var attempt = 0; attempt < 2; attempt++) {
				this.draft_summary = null;
				this.waiting_shown = false;
				try {
					var tpl = new Prompt.Template("chatter_summary.md") {
						source = "resource:///",
						base_dir = "chat-prompts"
					};
					tpl.load();
					var user_text = tpl.fill(
						"previous_summary", previous_summary,
						"turn_references", turn_references,
						"allowed_references", allowed_references
					);
					if (validation_issue != "") {
						user_text += "\n\n### Validation issue (fix and resubmit)\n\n"
							+ validation_issue;
					}

					var messages = new Gee.ArrayList<Message>();
					messages.add(new Message("system", tpl.system_message));
					messages.add(new Message("user", user_text));

					yield this.fill_model();
					yield this.chat_call.send(messages, cancellable);

					if (this.draft_summary == null
						|| this.draft_summary.content.strip() == "") {
						GLib.debug("summarize after send empty draft attempt=%d",
							attempt);
						return;
					}
					GLib.debug("summarize after send draft_len=%u attempt=%d",
						this.draft_summary.content.length, attempt);

					var sum_render = new Markdown.Document.Render();
					sum_render.parse(this.draft_summary.content);
					var issue = "";
					foreach (var link in sum_render.document.links) {
						if (link.path != "") {
							issue = "Summary link must be hash-only, not: " + link.href;
							break;
						}
						if (link.hash == "") {
							continue;
						}
						if (!hash_ref_regex.match(link.hash)) {
							issue = "Invalid hash reference: #" + link.hash;
							break;
						}
						if (!allowed.contains(link.hash)) {
							issue = "Disallowed hash reference: #" + link.hash;
							break;
						}
					}

					if (issue == "") {
						GLib.debug("summarize validation ok");
						this.session.save_async.begin();
						return;
					}

					GLib.debug("summarize validation fail: %s", issue);
					this.session.messages.remove(this.draft_summary);
					this.draft_summary = null;
					validation_issue = issue;
				} catch (GLib.Error e) {
					GLib.warning("Summarization failed: %s", e.message);
					return;
				}
			}
		}
	}
}
