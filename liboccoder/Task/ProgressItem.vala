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
 *
 * Implementors provide **`message`**, **`idx_notify_id`**, and **`msg_idx_txt`** (delegates to {@link msg_idx_to_string}). Default **`assign_message`** watches **`idx-last`** and **notify**s **`msg_idx_txt`**.
 */
public interface ProgressItem : GLib.Object
{
	public abstract PhaseEnum status { get; set; }

	public abstract string title { owned get; }

	public abstract string status_str { owned get; }

	public abstract GLib.ListModel children { get; }

	/**
	 * Chat row span for this progress row.
	 * Progress strip scroll uses {@link OLLMchat.Message.idx_first} when set,
	 * otherwise {@link OLLMchat.Message.idx_last}.
	 */
	public abstract OLLMchat.Message? message { get; set; }

	/** Non-zero while `assign_message` is watching `message.notify["idx-last"]`; cleared on disconnect. */
	public abstract ulong idx_notify_id { get; set; }

	/** Idx column string from `this.message` span (`first–last`, or —). */
	public virtual string msg_idx_to_string()
	{
		if (this.message == null) {
			return "—";
		}
		if (this.message.idx_first >= 0 && this.message.idx_last >= 0) {
			return this.message.idx_first == this.message.idx_last
				? this.message.idx_first.to_string()
				: "%d-%d".printf(this.message.idx_first, this.message.idx_last);
		}
		return "—";
	}

	/**
	 * After {@link Tool} execution, the {@link OLLMchat.Tool.RequestBase} copied from {@link OLLMchat.Tool.BaseTool.last_request} for this row; **null** if not a tool row or not yet run.
	 */
	public abstract OLLMchat.Tool.RequestBase? tool_request { get; set; }

	/**
	 * Tooltip for the progress title column; **""** if none.
	 */
	public abstract string tooltip_text { owned get; }

	public void assign_message(OLLMchat.Message m)
	{
		/* GLib.debug("prog assign msg=%p first=%d last=%d", m, m.idx_first, m.idx_last); */
		if (this.message != null && this.idx_notify_id != 0) {
			/* GLib.debug(
				"prog assign rebind had_watcher old=%p old_first=%d old_last=%d new=%p new_first=%d new_last=%d",
				this.message,
				this.message.idx_first,
				this.message.idx_last,
				m,
				m.idx_first,
				m.idx_last); */
			this.message.disconnect(this.idx_notify_id);
			this.idx_notify_id = 0;
		}
		this.message = m;
		this.notify_property("msg_idx_txt");
		if (m.idx_first >= 0 && m.idx_last >= 0) {
			return;
		}
		this.idx_notify_id = m.notify["idx-last"].connect(() => {
			/* GLib.debug("prog idx_last notify msg=%p first=%d last=%d", m, m.idx_first, m.idx_last); */
			this.notify_property("msg_idx_txt");
			if (m.idx_first >= 0 && m.idx_last >= 0 && this.idx_notify_id != 0) {
				m.disconnect(this.idx_notify_id);
				this.idx_notify_id = 0;
			}
		});
	}
}

}
