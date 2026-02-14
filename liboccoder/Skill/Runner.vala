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

namespace OLLMcoder.Skill
{
	/**
	 * Agent that runs a single skill. Builds system message (template + available skills + current skill)
	 * and user message (template or pass-through); injects them and sends.
	 */
	public class Runner : OLLMchat.Agent.Base
	{
		public Definition skill { get; private set; }
		private Factory sr_factory {
			get { return (Factory) this.factory; }
		}

		private string _active_template_key = "skill";
		/** Template key for current step (e.g. "skill", "task_creation_initial", "task_execution"). */
		public string active_template_key {
			get { return _active_template_key; }
			set { _active_template_key = value; }
		}

		private Gee.HashMap<string, PromptTemplate> templates = new Gee.HashMap<string, PromptTemplate>();

		private const string SKILL_PROMPTS_DIR = "resources/skill-prompts";

		private static string template_filename_for(string key)
		{
			switch (key) {
				case "skill":
					return "skill.template.md";
				case "task_creation_initial":
					return "task_creation_initial.md";
				case "task_refinement":
					return "task_refinement.md";
				case "task_post_completion":
					return "task_post_completion.md";
				case "task_execution":
					return "task_execution.md";
				default:
					return key + ".md";
			}
		}

		private PromptTemplate get_template(string key) throws GLib.Error
		{
			if (this.templates.has_key(key)) {
				return this.templates.get(key);
			}
			var filename = template_filename_for(key);
			PromptTemplate t;
			if (key != "skill") {
				t = PromptTemplate.from_dir(filename, SKILL_PROMPTS_DIR);
			} else {
				t = new PromptTemplate(filename);
			}
			t.load();
			this.templates.set(key, t);
			return t;
		}

		public Runner(Factory factory, OLLMchat.History.SessionBase session)
		{
			base(factory, session);
		}

		private string system_message() throws GLib.Error
		{
			var missing = this.skill.validate_skills(this.sr_factory.skill_manager.by_name);
			if (missing.size > 0) {
				throw new GLib.FileError.INVAL("Skill references missing or unavailable skills: "
					+ string.joinv(", ", missing.to_array()));
			}

			this.skill.apply_skills(this.sr_factory.skill_manager.by_name);
			return get_template(this.active_template_key).system_fill("current_skill", this.skill.to_markdown(), null);
		}

		public override async void fill_model()
		{
			if (this.skill.header.has_key("model")) {
				var skill_model = this.skill.header.get("model").strip();
				if (skill_model != "" && this.connection.models.has_key(skill_model)) {
					this.chat_call.model = skill_model;
					this.add_message(new OLLMchat.Message("ui", "skill using " + skill_model + " model."));
					return;
				}
				if (skill_model != "") {
					this.add_message(new OLLMchat.Message("ui-warning",
						"The skill requested the model \"" + skill_model + "\", but it was not available. Using your selected model instead."));
				}
			}
			yield base.fill_model();
		}

		private string user_prompt(string user_query) throws GLib.Error
		{
			return get_template(this.active_template_key).fill("query", user_query);
		}

		private void fill_tools()
		{
			this.chat_call.tools.clear();
			if (!this.skill.header.has_key("tools")) {
				return;
			}
			foreach (var name in this.skill.header.get("tools").split(" ")) {
				var tool_name = name.strip();
				if (tool_name == "") {
					continue;
				}
				if (!this.session.manager.tools.has_key(tool_name)) {
					this.add_message(new OLLMchat.Message("ui-warning",
						"The skill requested the tool \"" + tool_name + "\", but it was not available."));
					continue;
				}
				this.chat_call.tools.set(tool_name, this.session.manager.tools.get(tool_name));
			}
		}

		public override async void send_async(OLLMchat.Message message, GLib.Cancellable? cancellable = null)
		{
			this.sr_factory.skill_manager.scan();
			this.skill = this.sr_factory.skill_manager.by_name.get(this.sr_factory.skill_name);
			if (this.skill == null) {
				this.add_message(new OLLMchat.Message("ui", "Skill not found: " + this.sr_factory.skill_name));
				return;
			}

			var messages = new Gee.ArrayList<OLLMchat.Message>();

			string system_content;
			try {
				system_content = this.system_message();
			} catch (GLib.Error e) {
				this.add_message(new OLLMchat.Message("ui", e.message));
				this.session.is_running = false;
				return;
			}

			if (system_content != "") {
				var system_msg = new OLLMchat.Message("system", system_content);
				this.session.messages.add(system_msg);
				messages.add(system_msg);
			}

			string user_content;
			try {
				user_content = this.user_prompt(message.content);
			} catch (GLib.Error e) {
				this.add_message(new OLLMchat.Message("ui", e.message));
				this.session.is_running = false;
				return;
			}
			this.session.messages.add(new OLLMchat.Message("user", user_content));

			foreach (var msg in this.session.messages) {
				if (msg.role == "user" || msg.role == "assistant" || msg.role == "tool") {
					messages.add(msg);
				}
			}

			this.session.is_running = true;
			GLib.debug("is_running=true session %s", this.session.fid);

			yield this.fill_model();
			this.fill_tools();

			this.chat_call.cancellable = cancellable;
			try {
				var response = yield this.chat_call.send(messages, cancellable);
			} catch (GLib.Error e) {
				this.add_message(new OLLMchat.Message("ui", e.message));
				this.session.is_running = false;
			}
		}
	}
}
