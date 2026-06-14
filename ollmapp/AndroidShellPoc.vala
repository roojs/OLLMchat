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
	public class AndroidShellPocWindow : Adw.ApplicationWindow
	{
		public AndroidShellPocWindow(AndroidShellPocApplication app)
		{
			Object(
				application: app,
				title: "OLLMchat Android Shell"
			);
			this.set_default_size(420, 720);

			var toolbar_view = new Adw.ToolbarView();
			toolbar_view.add_top_bar(new Adw.HeaderBar());

			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				valign = Gtk.Align.CENTER
			};
			var title_label = new Gtk.Label("OLLMchat Android POC") {
				wrap = true
			};
			title_label.add_css_class("title-1");
			box.append(title_label);
			box.append(new Gtk.Label(
				"This APK shell proves the GTK Android packaging path " +
				"without loading the desktop window, tools, vector search, " +
				"or local GGUF support."
			) {
				wrap = true,
				justify = Gtk.Justification.CENTER
			});
			box.append(new Gtk.Label(
				"Remote chat is the next layer once libollmchat's " +
				"network dependencies are wrapped for Android."
			) {
				wrap = true,
				justify = Gtk.Justification.CENTER
			});

			toolbar_view.content = box;
			this.content = toolbar_view;
		}
	}

	public class AndroidShellPocApplication : Adw.Application
	{
		public AndroidShellPocApplication()
		{
			Object(
				application_id: "org.roojs.ollmchat.androidpoc",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);

			this.activate.connect(() => {
				var window = new AndroidShellPocWindow(this);
				window.present();
			});
		}
	}

	int main(string[] args)
	{
		var app = new AndroidShellPocApplication();
		return app.run(args);
	}
}
