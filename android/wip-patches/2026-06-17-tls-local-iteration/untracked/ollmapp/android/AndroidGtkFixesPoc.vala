/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Minimal Android harness for GIO TLS backend registration on GTK Android.
 *
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

namespace OLLMapp
{
	public class GtkFixesPocWindow : Gtk.ApplicationWindow
	{
		public GtkFixesPocWindow(GtkFixesPocApplication app, bool tls_ready)
		{
			Object(application: app, title: "GIO TLS probe");
			this.set_default_size(420, 240);

			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16) {
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16,
				vexpand = true
			};

			box.append(new Gtk.Label("GIO TLS backend") {
				halign = Gtk.Align.START
			});
			box.append(new Gtk.Label(
				"Checks whether libgioopenssl.so registered a real "
				+ "GTlsBackend (not GDummyTlsBackend). See logcat for "
				+ "OLLMchat TLS and GLib-GIO debug lines."
			) {
				wrap = true,
				halign = Gtk.Align.START
			});

			var backend = get_tls_backend_type_name();
			var status = tls_ready
				? "Ready: %s".printf(backend)
				: "Not ready: %s".printf(backend);
			box.append(new Gtk.Label(status) {
				wrap = true,
				halign = Gtk.Align.START
			});

			this.child = box;
			GLib.message("GTK fixes POC: TLS harness backend=%s ready=%s",
			             backend, tls_ready.to_string());
		}
	}

	public class GtkFixesPocApplication : Gtk.Application
	{
		private bool tls_ready;

		public GtkFixesPocApplication(bool tls_ready)
		{
			Object(
				application_id: "org.roojs.ollmchat.gtkfixespoc",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);
			this.tls_ready = tls_ready;

			this.activate.connect(() => {
				var window = new GtkFixesPocWindow(this, this.tls_ready);
				window.present();
			});
		}
	}

	[CCode (cname = "ollmapp_configure_android_gio_tls_modules", cheader_filename = "android-gio-tls.h")]
	private extern bool configure_android_gio_tls_modules();

	[CCode (cname = "ollmapp_android_gio_tls_backend_type_name", cheader_filename = "android-gio-tls.h")]
	private extern unowned string get_tls_backend_type_name();

	int main(string[] args)
	{
		bool tls_ready = configure_android_gio_tls_modules();
		var app = new GtkFixesPocApplication(tls_ready);
		return app.run(args);
	}
}
