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

namespace OLLMchat.Settings
{
	/**
	 * Outbound remote file-server connection (client side).
	 *
	 * JSON key ''filesd_client'' on {@link Config2}. At most one row in the
	 * Connections tab; empty ''url'' means not configured.
	 */
	public class FilesdClient : Object, Json.Serializable
	{
		/**
		 * Remote ''ollmfilesd'' HTTPS base URL (e.g. [[https://host:8443]]).
		 */
		public string url { get; set; default = ""; }

		/**
		 * Every ''host:port'' from the last successful pairing reply,
		 * one per line. Empty when this phone has not paired.
		 */
		public string addresses { get; set; default = ""; }

		/**
		 * Desktop id from the pairing mDNS TXT record.
		 *
		 * PEM files for that desktop live in a directory of this
		 * name under the user data directory. Empty until pairing
		 * stores a reply.
		 */
		public string server_id { get; set; default = ""; }

		/**
		 * Connection state. JSON is the ordinal.
		 *
		 * 0 requested, 1 disabled, 2 enabled, 3 live, 4 unreachable,
		 * 5 socket.
		 */
		public enum State {
			REQUESTED,
			DISABLED,
			ENABLED,
			LIVE,
			UNREACHABLE,
			SOCKET;

			/**
			 * Connections-row status text for this state.
			 *
			 * Requested, disabled, and unreachable name themselves.
			 * Enabled, live, and socket read as active.
			 *
			 * @return the row subtitle
			 */
			public string label()
			{
				switch (this) {
					case REQUESTED:
						return "Requested";
					case DISABLED:
						return "Disabled";
					case UNREACHABLE:
						return "Unreachable";
					default:
						return "Active";
				}
			}
		}

		public State state { get; set; default = State.REQUESTED; }

		public FilesdClient()
		{
		}

		/**
		 * Delete the pairing certificates for {@link server_id}.
		 *
		 * An empty server id means nothing was stored. The key,
		 * certificate, CSR, and CA live in a directory of that name
		 * under the user data directory.
		 */
		public void remove()
		{
			if (this.server_id == "") {
				return;
			}
			(new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat",
					this.server_id),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
			}).remove();
		}

		/**
		 * One attempt to register or hello the desktop.
		 *
		 * A stored certificate the desktop does not know returns
		 * {@link OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED} so the caller
		 * can sign a new certificate with the PIN. Success stores
		 * {@link url} and {@link addresses}.
		 *
		 * @param host desktop address from discovery
		 * @param port desktop port
		 * @param pin six digits from the pairing window
		 * @param force_register true to ignore a stored CA and sign again
		 * @param requester device string stored as the desktop row title
		 * @return zero when hello succeeds, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int try_connection(
			string host,
			uint16 port,
			string pin,
			bool force_register,
			string requester
		) {
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", this.server_id);
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
			};
			tls_files.ensure();
			var has_credentials = !force_register && GLib.FileUtils.test(
				GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS);
			if (!has_credentials) {
				var csr = "";
				try {
					GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "client.csr"), out csr);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				OLLMrpc.Response response;
				try {
					var link = new OLLMrpc.Transport.TlsClient(host, port) {
						accept_any = true
					};
					response = link.call(new OLLMrpc.Request() {
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", pin, csr, requester)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (response.error != null) {
					return response.error.code;
				}
				var packed = (string[]) response.retval;
				if (packed.length < 2) {
					return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
				}
				try {
					GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "client.pem"), packed[0]);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				tls_files.ensure();
				this.addresses = string.joinv("\n", packed[2:packed.length]);
			}
			if (this.addresses == "") {
				this.addresses = host + ":" + port.to_string();
			}
			var authed = new OLLMrpc.Transport.TlsClient(host, port) {
				tls_certificate = tls_files.certificate,
				tls_database = tls_files.trust
			};
			if (has_credentials) {
				var pair_code = this.complete_pairing(authed, pin);
				if (pair_code != 0) {
					return pair_code;
				}
			}
			OLLMrpc.Response hello;
			try {
				hello = authed.call(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (hello.error != null) {
				return hello.error.code;
			}
			this.url = "tcp://" + host + ":" + port.to_string();
			return 0;
		}

		/**
		 * Completes a new pairing window with stored credentials.
		 *
		 * The server validates the stored certificate before accepting the
		 * current PIN through ''ClientCert.pair''.
		 *
		 * @param link authenticated TLS client from {@link try_connection}
		 * @param pin current pairing PIN
		 * @return zero when the server accepts the pairing, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		private int complete_pairing(OLLMrpc.Transport.TlsClient link, string pin)
		{
			try {
				var response = link.call(new OLLMrpc.Request() {
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
				if (response.error != null) {
					return response.error.code;
				}
				return 0;
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			var val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(
			string property_name, Value value, ParamSpec pspec)
		{
			if (property_name == "state") {
				var node = new Json.Node(Json.NodeType.VALUE);
				node.set_int((int) this.state);
				return node;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec,
			Json.Node property_node)
		{
			if (property_name == "state") {
				value = Value(typeof(State));
				value.set_enum((int) property_node.get_int());
				return true;
			}
			return default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
	}
}
