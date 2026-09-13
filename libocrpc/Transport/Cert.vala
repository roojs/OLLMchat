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
	/**
	 * Server leaf TLS identity for HTTPS RPC (product CA, not public Web PKI).
	 *
	 * Files under {@link dir}: ''server.pem'' / ''server-key.pem'' (leaf).
	 * {@link trust_pem_path} is the product CA PEM path clients put in
	 * {@link GLib.TlsFileDatabase} — Android ships that CA in GResource; it
	 * never needs this class or the CA private key.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var cert = new OLLMrpc.Transport.Cert(tls_dir, ca_pem, ca_key);
	 * http.tls_certificate = cert.certificate;
	 * var db = GLib.TlsFileDatabase.@new(cert.trust_pem_path);
	 * }}}
	 */
	public class Cert : GLib.Object
	{
		public string dir { get; construct; }

		public GLib.TlsCertificate certificate { get; private set; }

		/**
		 * Product CA PEM path (what clients trust).
		 */
		public string trust_pem_path { get; private set; default = ""; }

		/**
		 * Load existing leaf PEMs under {@link dir}, or mint a leaf signed
		 * by the product CA and load them.
		 *
		 * @param dir directory for ''server.pem'' / ''server-key.pem''
		 * @param ca_pem_path product CA certificate PEM
		 * @param ca_key_path product CA private key PEM (server-only)
		 * @throws GLib.Error mkdir, GnuTLS, or PEM load failure
		 */
		public Cert(string dir, string ca_pem_path, string ca_key_path) throws GLib.Error
		{
			GLib.Object(dir: dir);
			this.trust_pem_path = ca_pem_path;
			var cert_path = GLib.Path.build_filename(dir, "server.pem");
			var key_path = GLib.Path.build_filename(dir, "server-key.pem");
			if (!GLib.FileUtils.test(dir, GLib.FileTest.IS_DIR)) {
				if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
					throw new GLib.IOError.FAILED("mkdir %s failed", dir);
				}
			}
			if (GLib.FileUtils.test(cert_path, GLib.FileTest.EXISTS)
				&& GLib.FileUtils.test(key_path, GLib.FileTest.EXISTS)) {
				this.certificate = new GLib.TlsCertificate.from_files(
					cert_path, key_path);
				return;
			}
			var init_ret = GnuTLS.global_init();
			if (init_ret < 0) {
				throw new GLib.IOError.FAILED("gnutls_global_init: %s",
					((GnuTLS.ErrorCode)init_ret).to_string());
			}
			var ca_pem_text = "";
			var ca_key_text = "";
			GLib.FileUtils.get_contents(ca_pem_path, out ca_pem_text);
			GLib.FileUtils.get_contents(ca_key_path, out ca_key_text);
			var ca_pem_datum = GnuTLS.Datum() {
				data = ca_pem_text,
				size = ca_pem_text.length
			};
			var ca_key_datum = GnuTLS.Datum() {
				data = ca_key_text,
				size = ca_key_text.length
			};
			var ca_crt = GnuTLS.X509.Certificate.create();
			var ca_imp = ca_crt.import(
				ref ca_pem_datum, GnuTLS.X509.CertificateFormat.PEM);
			if (ca_imp < 0) {
				throw new GLib.IOError.FAILED("ca import: %s",
					((GnuTLS.ErrorCode)ca_imp).to_string());
			}
			var ca_key = GnuTLS.X509.PrivateKey.create();
			var ca_key_imp = ca_key.import(
				ref ca_key_datum, GnuTLS.X509.CertificateFormat.PEM);
			if (ca_key_imp < 0) {
				throw new GLib.IOError.FAILED("ca key import: %s",
					((GnuTLS.ErrorCode)ca_key_imp).to_string());
			}
			var key = GnuTLS.X509.PrivateKey.create();
			var gen_ret = key.generate(GnuTLS.PKAlgorithm.RSA, 2048);
			if (gen_ret < 0) {
				throw new GLib.IOError.FAILED("privkey_generate: %s",
					((GnuTLS.ErrorCode)gen_ret).to_string());
			}
			var crt = GnuTLS.X509.Certificate.create();
			var cn = "ollmrpc";
			var dn_ret = crt.set_dn_by_oid(
				"2.5.4.3", 0, cn, cn.length);
			if (dn_ret < 0) {
				throw new GLib.IOError.FAILED("set_dn_by_oid: %s",
					((GnuTLS.ErrorCode)dn_ret).to_string());
			}
			var ver_ret = crt.set_version(3);
			if (ver_ret < 0) {
				throw new GLib.IOError.FAILED("set_version: %s",
					((GnuTLS.ErrorCode)ver_ret).to_string());
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8)GLib.Random.int_range(0, 256);
			}
			var ser_ret = crt.set_serial(serial, serial.length);
			if (ser_ret < 0) {
				throw new GLib.IOError.FAILED("set_serial: %s",
					((GnuTLS.ErrorCode)ser_ret).to_string());
			}
			var now = (time_t)(GLib.get_real_time() / 1000000);
			crt.set_activation_time(now);
			crt.set_expiration_time(now + (time_t)(3650 * 24 * 60 * 60));
			/* GNUTLS_SAN_DNSNAME=1, GNUTLS_SAN_IPADDRESS=4 (vapi enum lacks cprefix). */
			var san_dns = crt.set_subject_alternative_name(
				(GnuTLS.X509.SubjectAltName)1, "localhost");
			if (san_dns < 0) {
				throw new GLib.IOError.FAILED("SAN DNS: %s",
					((GnuTLS.ErrorCode)san_dns).to_string());
			}
			var san_ip = crt.set_subject_alternative_name(
				(GnuTLS.X509.SubjectAltName)4, "\x7f\x00\x00\x01");
			if (san_ip < 0) {
				throw new GLib.IOError.FAILED("SAN IP: %s",
					((GnuTLS.ErrorCode)san_ip).to_string());
			}
			var key_ret = crt.set_key(key);
			if (key_ret < 0) {
				throw new GLib.IOError.FAILED("set_key: %s",
					((GnuTLS.ErrorCode)key_ret).to_string());
			}
			var sign_ret = crt.sign2(
				ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0);
			if (sign_ret < 0) {
				throw new GLib.IOError.FAILED("sign2: %s",
					((GnuTLS.ErrorCode)sign_ret).to_string());
			}
			var key_pem_len = (size_t)0;
			key.export(GnuTLS.X509.CertificateFormat.PEM, null, ref key_pem_len);
			var key_pem = new uint8[key_pem_len];
			var key_exp = key.export(
				GnuTLS.X509.CertificateFormat.PEM, key_pem, ref key_pem_len);
			if (key_exp < 0) {
				throw new GLib.IOError.FAILED("privkey_export: %s",
					((GnuTLS.ErrorCode)key_exp).to_string());
			}
			var crt_pem_len = (size_t)0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_pem_len);
			var crt_pem = new uint8[crt_pem_len];
			var crt_exp = crt.export(
				GnuTLS.X509.CertificateFormat.PEM, crt_pem, ref crt_pem_len);
			if (crt_exp < 0) {
				throw new GLib.IOError.FAILED("crt_export: %s",
					((GnuTLS.ErrorCode)crt_exp).to_string());
			}
			GLib.FileUtils.set_contents(key_path, (string)key_pem);
			GLib.FileUtils.set_contents(cert_path, (string)crt_pem);
			this.certificate = new GLib.TlsCertificate.from_files(
				cert_path, key_path);
		}
	}
}
