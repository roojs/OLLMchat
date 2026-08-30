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

namespace OLLMchatGtk
{
	/**
	 * Non-Linux stub for {@link Sudo}.
	 *
	 * Same constructor, {@link prepare}, {@link reset}, {@link submit},
	 * {@link overlay}, and signals. Methods are empty. There is no password
	 * row and no sudo. {@link overlay} only re-parents Allow into the
	 * button row.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.sudo = new Sudo(this.allow_once_btn);
	 * this.button_box.append(this.sudo.overlay);
	 * }}}
	 */
	public class Sudo : Gtk.Box
	{
		/**
		 * Unused on this host. Matches the Linux {@link Sudo.checked} signal.
		 *
		 * @param password unused
		 */
		public signal void checked(string password);

		/**
		 * Unused on this host. Matches the Linux {@link Sudo.busy} signal.
		 *
		 * @param on unused
		 */
		public signal void busy(bool on);

		/**
		 * Overlay that packs Allow in the permission button row.
		 */
		public Gtk.Overlay overlay;

		/**
		 * Re-parent Allow into {@link overlay}. No password widgets.
		 *
		 * @param allow the permission Allow button
		 */
		public Sudo(Gtk.Button allow)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, visible: false);
			this.overlay = new Gtk.Overlay();
			this.overlay.set_child(allow);
		}

		/**
		 * No-op. Root prompts do not run on this host.
		 */
		public async void prepare()
		{
		}

		/**
		 * No-op.
		 */
		public void reset()
		{
		}

		/**
		 * No-op.
		 */
		public void submit()
		{
		}
	}
}
