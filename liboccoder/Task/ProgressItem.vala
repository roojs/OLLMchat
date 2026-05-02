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

namespace OLLMcoder.Task
{

/**
 * Row surface for the task progress UI ({@link ProgressList}). **status** is {@link PhaseEnum} (reuse);
 * it **changes** as the row advances. **status_str** is **not** stored — use {@link PhaseEnum.to_human}
 * for the stage column / Gtk bindings (**Pango** markup). The **status** setter emits **notify** for **status_str** only.
 *
 * **children** — {@link GLib.ListModel} whose items are {@link ProgressItem} (**7.14.2**): on {@link Details} use the
 * execution {@link ToolList} (see **7.14.1.3**). On {@link Tool}, an empty {@link GLib.ListStore}.
 */
public interface ProgressItem : GLib.Object
{
	public abstract PhaseEnum status { get; set; }

	public abstract string title { owned get; }

	public abstract string status_str { owned get; }

	public abstract GLib.ListModel children { get; }

	/** Last **`Message.idx`** for this row (**continue-from** / **`scroll_to_idx`**); **-1** if unset. */
	public abstract int msg_idx { get; set; }

	/**
	 * After {@link Tool} execution, the {@link OLLMchat.Tool.RequestBase} copied from {@link OLLMchat.Tool.BaseTool.last_request} for this row; **null** if not a tool row or not yet run.
	 */
	public abstract OLLMchat.Tool.RequestBase? tool_request { get; set; }

	/**
	 * Tooltip for the progress title column; **""** if none.
	 */
	public abstract string tooltip_text { owned get; }
}

}
