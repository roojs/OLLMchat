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

namespace OLLMcoder.Action
{

/**
 * Base for task execution runners (lifted from {@link Task.Details.run_exec} /
 * {@link Task.Details.run_post_exec}). Not wired in yet — see plan 7.16.1.
 */
public abstract class Base : OLLMchat.Agent.Base
{
	protected Task.Details task;

	protected Base (Task.Details task)
	{
		base (task.runner.sr_factory, task.session);
		this.task = task;
		this.replace_chat (task.chat ());
	}

	public abstract async void run () throws GLib.Error;

	protected override async void fill_model ()
	{
		if (!this.task.skill.header.has_key ("model")) {
			yield base.fill_model ();
			return;
		}
		var skill_model = this.task.skill.header.get ("model").strip ();
		if (skill_model != "" && this.connection.models.has_key (skill_model)) {
			this.chat_call.model = skill_model;
			return;
		}
		if (skill_model != "") {
			this.task.add_message (new OLLMchat.Message ("ui", OLLMchat.Message.fenced (
				"text.oc-frame-warning.collapsed Model unavailable",
				"The skill requested the model \"" + skill_model +
					 "\", but it was not available. Using your selected model instead.")));
		}
		yield base.fill_model ();
	}
}

}
