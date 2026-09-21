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

namespace OLLMrpc.Transport
{
	[CCode (cname = "ocrpc_cert_create_pem_files", cheader_filename = "android/cert-openssl.h")]
	extern bool ocrpc_cert_create_pem_files(string cert_path, string key_path, string cn, bool server_san, string ca_pem_path, string ca_key_path) throws GLib.Error;

	/**
	 * The key and certificate files one program uses for HTTPS RPC.
	 *
	 * Android host: mint with OpenSSL (''android/cert-openssl.c''). Desktop
	 * compiles ''Transport/Cert.vala'' instead (meson, not ''#if'').
	 *
	 * Used by both ends: ollmfilesd makes the server's files, ollmapp
	 * makes the client's. Configure with construct properties, then call
	 * {@link ensure} once: it creates the files if needed and sets
	 * {@link certificate} (this program's own) and {@link trust} (the
	 * product CA the other end must be signed by). When
	 * {@link ca_pem_path} and {@link ca_key_path} are set the certificate
	 * is signed with that CA; otherwise it is self-signed.
	 *
	 * {@link ensure} does not throw. Files that are missing or will not
	 * load are recreated; anything else (directory not creatable, CA
	 * files missing, cannot write) is a broken install and aborts with
	 * {@link GLib.error}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * // device client (ollmapp)
	 * var client = new OLLMrpc.Transport.Cert() {
	 *     dir = GLib.Path.build_filename(
	 *         GLib.Environment.get_user_data_dir(), "ollmchat"),
	 *     cert_pem = "client.pem",
	 *     key_pem = "client-key.pem",
	 *     cn = "ollmchat-device",
	 *     product_ca_resource = true,
	 * };
	 * client.ensure();
	 * var http = new OLLMrpc.Transport.HttpClient(url) {
	 *     bin_body = true,
	 *     tls_certificate = client.certificate,
	 *     tls_database = client.trust
	 * };
	 * }}}
	 */
	public class Cert : GLib.Object
	{
		/** Directory the key, certificate and trust files live in. */
		public string dir { get; set; default = ""; }

		/** Certificate file name under {@link dir}. */
		public string cert_pem { get; set; default = "server.pem"; }

		/** Private key file name under {@link dir}. */
		public string key_pem { get; set; default = "server-key.pem"; }

		/** Name written into the certificate (X.509 common name). */
		public string cn { get; set; default = "ollmrpc"; }

		/** Server only: also make the certificate valid for ''localhost''. */
		public bool server_san { get; set; default = false; }

		/**
		 * Product CA certificate file used to sign our certificate.
		 * Empty (with empty {@link ca_key_path}) means self-signed.
		 */
		public string ca_pem_path { get; set; default = ""; }

		/** Product CA private key file (ollmfilesd only). */
		public string ca_key_path { get; set; default = ""; }

		/**
		 * Trust PEM basename under {@link dir} when {@link ca_pem_path} is
		 * empty. Default ''ollmrpc-ca.pem''.
		 */
		public string trust_pem { get; set; default = "ollmrpc-ca.pem"; }

		/**
		 * When true, {@link ensure} (re)writes the trust PEM from the
		 * bundled ''/ollmrpc/ollmrpc-ca.pem'' GResource on every call, so
		 * device clients always trust the current product CA.
		 */
		public bool product_ca_resource { get; set; default = false; }

		/** This program's own certificate and key, set by {@link ensure}. */
		public GLib.TlsCertificate certificate { get; private set; }

		/**
		 * Product CA trust store for {@link HttpClient.tls_database},
		 * set by {@link ensure} from {@link ca_pem_path} or the
		 * {@link trust_pem} file under {@link dir}. Null when neither
		 * exists (system trust), matching
		 * {@link HttpClient.tls_database}.
		 */
		public GLib.TlsDatabase? trust { get; private set; default = null; }

		/**
		 * Make sure this program's key and certificate files exist
		 * under {@link dir}, then set {@link certificate} and
		 * {@link trust} from them.
		 *
		 * If the key/certificate files are missing or will not load
		 * they are deleted and created again with
		 * {@link create_pem_files}. With {@link product_ca_resource}
		 * the trust file is rewritten from the bundled copy each time.
		 * Anything else that goes wrong (cannot create the directory,
		 * cannot write a file, CA files unreadable) means the install
		 * is broken and aborts with {@link GLib.error}.
		 */
		public void ensure()
		{
			if (this.dir == "") {
				GLib.error("Cert.dir is required");
			}
			if (!GLib.FileUtils.test(this.dir, GLib.FileTest.IS_DIR)
				&& GLib.DirUtils.create_with_parents(this.dir, 0700) != 0) {
				GLib.error("mkdir %s failed", this.dir);
			}

			var cert_path = GLib.Path.build_filename(this.dir, this.cert_pem);
			var key_path = GLib.Path.build_filename(this.dir, this.key_pem);
			if (GLib.FileUtils.test(cert_path, GLib.FileTest.EXISTS)
				&& GLib.FileUtils.test(key_path, GLib.FileTest.EXISTS)) {
				try {
					this.certificate = new GLib.TlsCertificate.from_files(cert_path, key_path);
				} catch (GLib.Error e) {
					GLib.warning("recreating %s: %s", cert_path, e.message);
					GLib.FileUtils.remove(cert_path);
					GLib.FileUtils.remove(key_path);
				}
			}
			if (!GLib.FileUtils.test(cert_path, GLib.FileTest.EXISTS)) {
				this.create_pem_files(cert_path, key_path);
			}

			var trust_path = this.ca_pem_path;
			if (trust_path == "") {
				trust_path = GLib.Path.build_filename(this.dir, this.trust_pem);
			}
			if (this.product_ca_resource) {
				try {
					GLib.FileUtils.set_contents(trust_path,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("write trust PEM %s: %s", trust_path, e.message);
				}
			}
			if (!GLib.FileUtils.test(trust_path, GLib.FileTest.EXISTS)) {
				return;
			}
			try {
				this.trust = GLib.TlsFileDatabase.@new(trust_path);
			} catch (GLib.Error e) {
				GLib.error("trust PEM %s: %s", trust_path, e.message);
			}
		}

		/**
		 * Create one key file and one certificate file and load them
		 * into {@link certificate}. Makes one pair: the server's when
		 * run in ollmfilesd, the client's when run in ollmapp.
		 *
		 * Called by {@link ensure} when the files are missing or
		 * unreadable; any failure is {@link GLib.error}.
		 *
		 * @param cert_path where to write the certificate file
		 * @param key_path where to write the private key file
		 */
		private void create_pem_files(string cert_path, string key_path)
		{
			try {
				ocrpc_cert_create_pem_files(cert_path, key_path, this.cn, this.server_san, this.ca_pem_path, this.ca_key_path);
				this.certificate = new GLib.TlsCertificate.from_files(cert_path, key_path);
			} catch (GLib.Error e) {
				GLib.error("write %s: %s", cert_path, e.message);
			}
		}
	}
}
