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

namespace OLLMcoder.Task
{

public class ProgressRunner : GLib.Object, ProgressItem
{
	public weak OLLMcoder.Skill.Runner runner { get; private set; }

	/** true = Task Creation row; false = Reviewing Task List row */
	public bool in_creation { get; set; default = true; }
	public uint try_no  { get; set; default = 0; }
	public uint try_max { get; set; default = 0; }

	private PhaseEnum status_value = PhaseEnum.NONE;

	public PhaseEnum status {
		get { return this.status_value; }
		set {
			if (this.status_value == value) {
				return;
			}
			this.status_value = value;
			this.notify_property("status_str");
		}
	}

	public string title {
		owned get {
			var b = this.in_creation ? "Task Creation" : "Reviewing Task List";
			if (this.try_no == 0 || this.try_max == 0) {
				return b;
			}
			return "%s (%u/%u)".printf(b, this.try_no + 1, this.try_max);
		}
	}

	public string status_str {
		owned get { return this.status.to_human(); }
	}

	public GLib.ListModel children {
		get;
		default = new GLib.ListStore(typeof (ProgressItem));
	}

	public OLLMchat.Tool.RequestBase? tool_request { get; set; default = null; }

	public string tooltip_text {
		owned get { return ""; }
	}

	public int msg_idx { get; set; default = -1; }

	public ProgressRunner(OLLMcoder.Skill.Runner r)
	{
		Object();
		this.runner = r;
	}
}

}
