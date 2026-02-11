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
	 * Lightweight factory: creates Manager and Runner only. Message building lives in Runner.
	 */
	public class Factory : OLLMchat.Agent.Factory
	{
		public Manager skill_manager { get; private set; }
		public string skill_name { get; private set; }

		public Factory(Gee.ArrayList<string> skills_directories, string skill_name = "")
		{
			this.name = "skill-runner";
			this.title = "Skills Agent";
			this.skill_manager = new Manager(skills_directories);
			this.skill_name = skill_name != "" ? skill_name : "task_creator";
		}

		public override OLLMchat.Agent.Base create_agent(OLLMchat.History.SessionBase session)
		{
			return new Runner(this, session);
		}
	}
}
