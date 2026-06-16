/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Minimal Android harness for GIO TLS backend registration and libsoup HTTPS.
 *
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

namespace OLLMapp
{
	/* Site with a normal public CA cert; example.com often fails verification on Android. */
	const string HTTPS_TEST_URL = "https://roojs.com/";

	public class GtkFixesPocWindow : Gtk.ApplicationWindow
	{
		private Gtk.Label https_status_label;
		private bool tls_ready;

		public GtkFixesPocWindow(GtkFixesPocApplication app, bool tls_ready)
		{
			Object(application: app, title: "GIO TLS probe");
			this.tls_ready = tls_ready;
			this.set_default_size(420, 360);

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

			box.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

			box.append(new Gtk.Label("HTTPS (libsoup)") {
				halign = Gtk.Align.START
			});

			this.https_status_label = new Gtk.Label(
				tls_ready ? "Tap the button to fetch roojs.com" : "Fix backend first"
			) {
				wrap = true,
				halign = Gtk.Align.START
			};
			box.append(this.https_status_label);

			var https_button = new Gtk.Button.with_label("GET %s".printf(HTTPS_TEST_URL));
			https_button.sensitive = tls_ready;
			https_button.clicked.connect(() => {
				this.run_https_test.begin();
			});
			box.append(https_button);

			this.child = box;
			GLib.message("GTK fixes POC: TLS harness backend=%s ready=%s",
			             backend, tls_ready.to_string());
		}

		private static string format_cert_flags (GLib.TlsCertificateFlags flags)
		{
			if (flags == GLib.TlsCertificateFlags.NO_FLAGS) {
				return "NO_FLAGS";
			}

			var parts = new string[] {};
			if ((flags & GLib.TlsCertificateFlags.UNKNOWN_CA) != 0) {
				parts += "UNKNOWN_CA";
			}
			if ((flags & GLib.TlsCertificateFlags.BAD_IDENTITY) != 0) {
				parts += "BAD_IDENTITY";
			}
			if ((flags & GLib.TlsCertificateFlags.NOT_ACTIVATED) != 0) {
				parts += "NOT_ACTIVATED";
			}
			if ((flags & GLib.TlsCertificateFlags.EXPIRED) != 0) {
				parts += "EXPIRED";
			}
			if ((flags & GLib.TlsCertificateFlags.REVOKED) != 0) {
				parts += "REVOKED";
			}
			if ((flags & GLib.TlsCertificateFlags.INSECURE) != 0) {
				parts += "INSECURE";
			}
			if ((flags & GLib.TlsCertificateFlags.GENERIC_ERROR) != 0) {
				parts += "GENERIC_ERROR";
			}

			return string.joinv("|", parts);
		}

		private bool on_accept_certificate (
			Soup.Message msg,
			GLib.TlsCertificate cert,
			GLib.TlsCertificateFlags errors)
		{
			GLib.message(
				"GTK fixes POC: accept_certificate subject=%s issuer=%s errors=0x%x (%s)",
				cert.get_subject_name() ?? "(null)",
				cert.get_issuer_name() ?? "(null)",
				(uint) errors,
				format_cert_flags(errors));
			return false;
		}

		private async void run_https_test()
		{
			this.https_status_label.label = "Fetching…";
			log_tls_trust_store();
			GLib.message("GTK fixes POC: HTTPS test start url=%s backend=%s",
			             HTTPS_TEST_URL, get_tls_backend_type_name());

			var session = new Soup.Session();
			AndroidConnectionTls.apply_to_session (session);

			var message = new Soup.Message("GET", HTTPS_TEST_URL);
			message.accept_certificate.connect(on_accept_certificate);

			try {
				yield session.send_and_read_async(
					message, GLib.Priority.DEFAULT, null);
				var status = message.get_status();
				if (status == Soup.Status.OK) {
					this.https_status_label.label = "HTTPS 200 OK";
				} else {
					this.https_status_label.label =
						"HTTPS %u".printf(status);
				}
				GLib.message("GTK fixes POC: TLS test status=%u", status);
			} catch (GLib.Error e) {
				this.https_status_label.label =
					"TLS failed: %s".printf(e.message);
				GLib.message(
					"GTK fixes POC: TLS test failed domain=%s code=%d message=%s peer_errors=0x%x (%s)",
					e.domain.to_string(), e.code, e.message,
					(uint) message.tls_peer_certificate_errors,
					format_cert_flags(message.tls_peer_certificate_errors));
			}
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

	[CCode (cname = "ollmapp_log_tls_trust_store", cheader_filename = "android-gio-tls.h")]
	private extern void log_tls_trust_store();

	int main(string[] args)
	{
		bool tls_ready = configure_android_gio_tls_modules();
		var app = new GtkFixesPocApplication(tls_ready);
		return app.run(args);
	}
}
