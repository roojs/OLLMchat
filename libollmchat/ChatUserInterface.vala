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

namespace OLLMchat
{
	/**
	 * Minimal host surface for {@link Agent.Factory} activate/deactivate.
	 * Implemented by the main chat window (ollmapp: OllmchatWindow).
	 */
	public interface ChatUserInterface : GLib.Object
	{
		public abstract Agent.Base? session_agent();
		public abstract GLib.Object above_input_widget();
		/** Right pane tab stack as {@link GLib.Object}; ollmapp uses {@link Adw.ViewStack}. */
		public abstract GLib.Object tab_view();
		/** Right pane show/hide on idle (see ollmapp WindowPane.schedule_pane_update). */
		public abstract void schedule_pane_update(bool visible);
	}
}
