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

namespace OLLMapp
{
	/**
	 * Optional whole-window touch/button capture for popover hit-testing debug.
	 *
	 * Enable with {@code --touch-debug} on the Android POC. Logs via
	 * {@link GLib.debug} and updates an on-screen HUD.
	 *
	 * Events delivered only to GDK popup surfaces (e.g. open popovers) do not
	 * pass through this controller — they stay on the popup native layer.
	 *
	 * @since 1.0
	 */
	public class AndroidTouchDebug : GLib.Object
	{
		public static bool enabled { get; private set; }

		public static void parse_args (string[] args)
		{
			foreach (var arg in args) {
				if (arg == "--touch-debug") {
					AndroidTouchDebug.enabled = true;
					OLLMchat.ApplicationInterface.debug_on = true;
				}
				if (arg == "--debug") {
					OLLMchat.ApplicationInterface.debug_on = true;
				}
			}
		}

		/**
		 * Enable when {@code files/touch-debug} exists beside the GTK asset tree
		 * (external app files dir). Useful on device when argv is empty.
		 */
		public static void try_enable_from_storage ()
		{
			if (AndroidTouchDebug.enabled) {
				return;
			}

			var data_home = GLib.Environment.get_user_data_dir ();
			if (data_home == null || data_home == "") {
				return;
			}

			var flag_path = GLib.Path.build_filename (
				GLib.Path.get_dirname (data_home),
				"touch-debug");
			if (!GLib.FileUtils.test (
				flag_path,
				GLib.FileTest.EXISTS)) {
				return;
			}

			AndroidTouchDebug.enabled = true;
			OLLMchat.ApplicationInterface.debug_on = true;
			GLib.message ("touch-debug: enabled via %s", flag_path);
		}

		public AndroidTouchDebug (Gtk.Widget root, Gtk.Label hud)
		{
			Object ();
			this.attach_phase (root, hud, Gtk.PropagationPhase.CAPTURE);
			this.attach_phase (root, hud, Gtk.PropagationPhase.BUBBLE);
		}

		private void attach_phase (
			Gtk.Widget root,
			Gtk.Label hud,
			Gtk.PropagationPhase phase)
		{
			var controller = new Gtk.EventControllerLegacy ();
			controller.propagation_phase = phase;
			controller.event.connect ((event) => {
				if (!AndroidTouchDebug.enabled) {
					return false;
				}

				var type_name = "";
				switch (event.type) {
				case Gdk.EventType.TOUCH_BEGIN:
					type_name = "TOUCH_BEGIN";
					break;
				case Gdk.EventType.TOUCH_END:
					type_name = "TOUCH_END";
					break;
				case Gdk.EventType.BUTTON_PRESS:
					type_name = "BUTTON_PRESS";
					break;
				case Gdk.EventType.BUTTON_RELEASE:
					type_name = "BUTTON_RELEASE";
					break;
				default:
					return false;
				}

				var x = 0.0;
				var y = 0.0;
				event.get_position (out x, out y);
				var picked = root.pick (x, y, Gtk.PickFlags.DEFAULT);
				var phase_name = phase == Gtk.PropagationPhase.CAPTURE ?
					"capture" : "bubble";
				var pick_label = "none";
				if (picked != null) {
					var widget_name = picked.get_name ();
					if (widget_name != null && widget_name != "") {
						pick_label = "%s:%s".printf (
							picked.get_type_name (),
							widget_name);
					} else {
						pick_label = picked.get_type_name ();
					}
				}

				GLib.debug (
					"touch phase=%s type=%s xy=(%.0f,%.0f) pick=%s",
					phase_name,
					type_name,
					x,
					y,
					pick_label);

				hud.label = "%s %s (%.0f,%.0f)\n%s".printf (
					phase_name,
					type_name,
					x,
					y,
					pick_label);

				return false;
			});
			root.add_controller (controller);
		}
	}
}
