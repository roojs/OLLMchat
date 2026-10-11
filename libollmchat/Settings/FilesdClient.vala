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
		 * @return zero when hello succeeds, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int try_connection(
			string host,
			uint16 port,
			string pin,
			bool force_register
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
			var client = new GLib.SocketClient() {
				timeout = 10
			};
			var has_credentials = !force_register && GLib.FileUtils.test(
				GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS);
			if (!has_credentials) {
				var csr = "";
				try {
					GLib.FileUtils.get_contents(
						GLib.Path.build_filename(dir, "client.csr"), out csr);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				GLib.SocketConnection conn;
				try {
					conn = client.connect_to_host(host, (uint16) port);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					conn.socket.blocking = true;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				GLib.TlsClientConnection tls;
				try {
					tls = GLib.TlsClientConnection.@new(conn, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				try {
					tls.handshake();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				OLLMrpc.Bin.Stream bin;
				try {
					bin = new OLLMrpc.Bin.Stream(
						new GLib.DataInputStream(tls.get_input_stream()),
						new GLib.DataOutputStream(tls.get_output_stream())
					);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					bin.write(new OLLMrpc.Request() {
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", pin, csr, "ollmchat")
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				OLLMrpc.Bin.Serializable parsed;
				var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
				while (true) {
					try {
						parsed = bin.parse();
					} catch (GLib.IOError e) {
						if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= reply_wait) {
							GLib.warning("%s", e.message);
							return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
						}
						var reply_poll = GLib.PollFD();
						reply_poll.fd = conn.socket.fd;
						reply_poll.events = GLib.IOCondition.IN;
						GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
						continue;
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					if (!(parsed is OLLMrpc.Response)) {
						continue;
					}
					break;
				}
				var response = (OLLMrpc.Response) parsed;
				if (response.error != null) {
					return response.error.code;
				}
				var packed = (string[]) response.retval;
				if (packed.length < 2) {
					return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
				}
				try {
					GLib.FileUtils.set_contents(
						GLib.Path.build_filename(dir, "client.pem"), packed[0]);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					GLib.FileUtils.set_contents(
						GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
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
			GLib.SocketConnection again;
			try {
				again = client.connect_to_host(host, (uint16) port);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				again.socket.blocking = true;
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			GLib.TlsClientConnection tls2;
			try {
				tls2 = GLib.TlsClientConnection.@new(again, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls2.certificate = tls_files.certificate;
			tls2.database = tls_files.trust;
			tls2.accept_certificate.connect((peer_cert, errors) => {
				return peer_cert != null
					&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
			});
			try {
				tls2.handshake();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Bin.Stream bin2;
			try {
				bin2 = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(tls2.get_input_stream()),
					new GLib.DataOutputStream(tls2.get_output_stream())
				);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (has_credentials) {
				var pair_code = this.complete_pairing(bin2, again.socket, pin);
				if (pair_code != 0) {
					return pair_code;
				}
			}
			try {
				bin2.write(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Bin.Serializable hello_parsed;
			var hello_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					hello_parsed = bin2.parse();
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= hello_wait) {
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					var hello_poll = GLib.PollFD();
					hello_poll.fd = again.socket.fd;
					hello_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { hello_poll }, 200);
					continue;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (!(hello_parsed is OLLMrpc.Response)) {
					continue;
				}
				break;
			}
			var hello = (OLLMrpc.Response) hello_parsed;
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
		 * @param bin authenticated TLS bin stream
		 * @param socket raw socket polled while TLS buffers the reply
		 * @param pin current pairing PIN
		 * @return zero when the server accepts the pairing, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		private int complete_pairing(
			OLLMrpc.Bin.Stream bin,
			GLib.Socket socket,
			string pin
		) {
			try {
				bin.write(new OLLMrpc.Request() {
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var response = bin.parse() as OLLMrpc.Response;
					if (response == null) {
						continue;
					}
					if (response.error != null) {
						return response.error.code;
					}
					return 0;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK
						|| GLib.get_monotonic_time() >= wait) {
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					var poll = GLib.PollFD();
					poll.fd = socket.fd;
					poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { poll }, 200);
					continue;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
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
