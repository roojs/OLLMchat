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
	 * Header status bar for daemon activity (filesystem scan, vector index, etc.).
	 *
	 * Emit {@link notification} with {@link OLLMrpc.Notification} objects;
	 * daemon RPC events pass through unchanged, client work uses
	 * ''client.*'' method names.
	 */
	public class ActivityBanner : Gtk.Box
	{
		/**
		 * Activity or daemon event.
		 *
		 * @param notif RPC-shaped notification (''method'' + ''message'')
		 */
		public signal void notification(OLLMrpc.Notification notif);

		public Gtk.Label label { get; private set; }
		public Gtk.ProgressBar progress_bar { get; private set; }
		public Gtk.Revealer revealer { get; private set; }

		private int total_scan = 0;
		private uint hide_timeout_id = 0;

		public ActivityBanner()
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				margin_start: 0,
				margin_end: 0,
				margin_top: 2,
				margin_bottom: 2
			);

			this.css_classes = {"banner"};

			this.revealer = new Gtk.Revealer() {
				child = this,
				reveal_child = false,
				transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN
			};

			this.label = new Gtk.Label("") {
				hexpand = true,
				halign = Gtk.Align.CENTER,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				margin_bottom = 0
			};
			this.append(this.label);

			this.progress_bar = new Gtk.ProgressBar() {
				show_text = false,
				fraction = 0.0,
				hexpand = true,
				height_request = 6
			};
			this.append(this.progress_bar);
		}

		construct
		{
			this.notification.connect(this.on_notification);
		}

		/**
		 * Dispatch a daemon ''event.*'' or client ''client.*'' notification.
		 *
		 * @param notif RPC-shaped notification (''method'' + ''message'')
		 */
		private void on_notification(OLLMrpc.Notification notif)
		{
			switch (notif.method) {
				case "client.project.load_start":
					this.label.label = "Loading project list…";
					this.progress_bar.fraction = 0.0;
					this.show();
					break;

				case "client.project.load_end":
					this.hide();
					break;

				case "event.filesystem.scan_start":
					this.label.label =
						"Filesystem scan: %s…".printf(
							GLib.Path.get_basename(notif.message));
					this.show();
					break;

				case "event.filesystem.scan_end":
					var fs_end_space = notif.message.index_of(" ");
					if (fs_end_space < 0) {
						return;
					}
					var fs_file_count = int.parse(
						notif.message.substring(0, fs_end_space));
					this.label.label =
						"Filesystem scan ended — %d files".printf(
							fs_file_count);
					this.hide();
					break;

				case "event.vector.scan_start":
					this.label.label = "Vector indexing…";
					this.progress_bar.fraction = 0.0;
					this.show();
					break;

				case "event.vector.scan_end":
					this.hide();
					break;

				case "event.vector.scan_update":
					var space = notif.message.index_of(" ");
					if (space < 0) {
						return;
					}
					var queue_text = notif.message.substring(0, space);
					var current_file = notif.message.substring(space + 1);
					var queue_size = int.parse(queue_text);

					this.total_scan = int.max(this.total_scan, queue_size);
					if (this.total_scan == 0) {
						this.total_scan = 1;
					}

					this.progress_bar.fraction =
						1.0 - ((double)queue_size / (double)this.total_scan);

					var files_scanned = this.total_scan - queue_size;
					var basename = GLib.Path.get_basename(current_file);

					if (queue_size == 0) {
						this.progress_bar.fraction = 1.0;
						this.label.label =
							"Vector indexing: %s — %d/%d".printf(
								basename, this.total_scan, this.total_scan);
						this.hide();
						return;
					}

					this.label.label =
						"Vector indexing: %s — %d/%d".printf(
							basename, files_scanned, this.total_scan);
					this.show();
					break;

				case "event.hf.download.start":
					this.label.label =
						"Downloading %s…".printf(notif.message);
					this.progress_bar.fraction = 0.0;
					this.show();
					break;

				case "event.hf.download.progress":
					if (notif.progress_total > 0) {
						this.progress_bar.fraction =
							(double) notif.progress_completed
							/ (double) notif.progress_total;
					}
					this.label.label =
						"Downloading %s — %lld/%lld".printf(
							GLib.Path.get_basename(notif.message),
							notif.progress_completed,
							notif.progress_total);
					this.show();
					break;

				case "event.hf.download.end":
					if (notif.message.contains(" error: ")) {
						this.label.label = "Download failed: " + notif.message;
					} else {
						this.label.label =
							"Download complete: %s".printf(notif.message);
						this.progress_bar.fraction = 1.0;
					}
					this.hide();
					break;

				case "event.browser.download.start":
					this.label.label =
						"Downloading %s…".printf(GLib.Path.get_basename(notif.message));
					this.progress_bar.fraction = 0.0;
					this.show();
					break;

				case "event.browser.download.progress":
					this.label.label =
						"Downloading %s…".printf(GLib.Path.get_basename(notif.message));
					if (notif.progress_total > 0) {
						this.progress_bar.fraction =
							(double) notif.progress_completed
							/ (double) notif.progress_total;
					} else {
						this.progress_bar.pulse();
					}
					this.show();
					break;

				case "event.browser.download.end":
					if (notif.message.contains(" error: ")) {
						this.label.label = "Download failed: " + notif.message;
					} else {
						this.label.label =
							"Download complete: %s".printf(
								GLib.Path.get_basename(notif.message));
						this.progress_bar.fraction = 1.0;
					}
					this.hide();
					break;

				default:
					break;
			}
		}

		/**
		 * Show the banner and cancel any pending auto-hide.
		 */
		public void show()
		{
			if (this.hide_timeout_id != 0) {
				GLib.Source.remove(this.hide_timeout_id);
				this.hide_timeout_id = 0;
			}
			this.revealer.reveal_child = true;
		}

		/**
		 * Schedule auto-hide after two seconds unless {@link show} runs first.
		 */
		public new void hide()
		{
			if (this.hide_timeout_id != 0) {
				GLib.Source.remove(this.hide_timeout_id);
				this.hide_timeout_id = 0;
			}
			this.hide_timeout_id = GLib.Timeout.add_seconds(2, () => {
				this.revealer.reveal_child = false;
				this.total_scan = 0;
				this.hide_timeout_id = 0;
				return false;
			});
		}
	}
}
