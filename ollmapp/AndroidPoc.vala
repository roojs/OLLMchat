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
	public class AndroidPocWindow : Adw.ApplicationWindow
	{
		private Gtk.Entry url_entry;
		private Gtk.Entry api_key_entry;
		private Gtk.Entry model_entry;
		private Gtk.TextView prompt_view;
		private Gtk.TextView response_view;
		private Gtk.Button send_button;
		private Gtk.Spinner spinner;

		public AndroidPocWindow(AndroidPocApplication app)
		{
			Object(
				application: app,
				title: "OLLMchat Android POC"
			);
			this.set_default_size(420, 720);

			var toolbar_view = new Adw.ToolbarView();
			toolbar_view.add_top_bar(new Adw.HeaderBar());

			var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};

			var intro_label = new Gtk.Label(
				"Remote-only chat proof of concept. " +
				"Use a LAN or emulator-reachable Ollama/OpenAI endpoint."
			) {
				wrap = true,
				xalign = 0
			};
			main_box.append(intro_label);

			this.url_entry = new Gtk.Entry() {
				text = "http://10.0.2.2:11434/api",
				placeholder_text = "http://host:11434/api"
			};
			main_box.append(this.field("Server URL", this.url_entry));

			this.api_key_entry = new Gtk.Entry() {
				placeholder_text = "Optional API key",
				visibility = false
			};
			main_box.append(this.field("API key", this.api_key_entry));

			this.model_entry = new Gtk.Entry() {
				text = "llama3.2",
				placeholder_text = "Model name"
			};
			main_box.append(this.field("Model", this.model_entry));

			this.prompt_view = new Gtk.TextView() {
				vexpand = true,
				wrap_mode = Gtk.WrapMode.WORD_CHAR
			};
			this.prompt_view.buffer.text = "Say hello from Android.";
			main_box.append(this.text_area("Prompt", this.prompt_view));

			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			this.spinner = new Gtk.Spinner() {
				visible = false
			};
			this.send_button = new Gtk.Button.with_label("Send");
			this.send_button.clicked.connect(() => {
				this.send.begin();
			});
			button_box.append(this.send_button);
			button_box.append(this.spinner);
			main_box.append(button_box);

			this.response_view = new Gtk.TextView() {
				editable = false,
				vexpand = true,
				wrap_mode = Gtk.WrapMode.WORD_CHAR
			};
			this.response_view.buffer.text = "Response will appear here.";
			main_box.append(this.text_area("Response", this.response_view));

			var scrolled_window = new Gtk.ScrolledWindow() {
				child = main_box,
				vexpand = true
			};
			toolbar_view.content = scrolled_window;
			this.content = toolbar_view;
		}

		private Gtk.Widget field(string label, Gtk.Entry entry)
		{
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
			box.append(new Gtk.Label(label) {
				xalign = 0
			});
			box.append(entry);
			return box;
		}

		private Gtk.Widget text_area(string label, Gtk.TextView text_view)
		{
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
			box.append(new Gtk.Label(label) {
				xalign = 0
			});
			box.append(new Gtk.ScrolledWindow() {
				child = text_view,
				min_content_height = 140,
				vexpand = true
			});
			return box;
		}

		private async void send()
		{
			if (this.prompt_view.buffer.text.strip() == "") {
				this.response_view.buffer.text = "Enter a prompt first.";
				return;
			}

			this.send_button.sensitive = false;
			this.spinner.visible = true;
			this.spinner.spinning = true;
			this.response_view.buffer.text = "Sending...";

			var connection = new OLLMchat.Settings.Connection() {
				name = "Android POC",
				url = this.url_entry.text.strip(),
				api_key = this.api_key_entry.text.strip(),
				is_default = true
			};
			var call = new OLLMchat.Call.ChatCompletions(
				connection,
				this.model_entry.text.strip()
			) {
				stream = false,
				think = false
			};
			call.messages.add(
				new OLLMchat.Message("user", this.prompt_view.buffer.text.strip())
			);

			try {
				this.response_view.buffer.text = (
					yield call.send(call.messages)
				).chat_content;
			} catch (GLib.Error e) {
				this.response_view.buffer.text = "Request failed: " + e.message;
			}

			this.spinner.spinning = false;
			this.spinner.visible = false;
			this.send_button.sensitive = true;
		}
	}

	public class AndroidPocApplication : Adw.Application
	{
		public AndroidPocApplication()
		{
			Object(
				application_id: "org.roojs.ollmchat.AndroidPoc",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);

			this.activate.connect(() => {
				var window = new AndroidPocWindow(this);
				window.present();
			});
		}
	}

	int main(string[] args)
	{
		var app = new AndroidPocApplication();
		return app.run(args);
	}
}
