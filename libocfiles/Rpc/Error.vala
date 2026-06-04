/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfiles.Rpc
{
	/** JSON-RPC 2.0 error object on the wire (`code`, `message`). */
	public class Error : GLib.Object, Json.Serializable
	{
		public int code { get; set; }
		public string message { get; set; default = ""; }

		/**
		 * @param method optional RPC method for {@link RpcErrorCode.INTERNAL_ERROR} logs
		 * @param request_id optional request id for {@link RpcErrorCode.INTERNAL_ERROR} logs
		 */
		public static void rpc_register()
		{
			register(typeof(Error));
		}

		public Error(
			RpcErrorCode code,
			string message,
			string method = "",
			int request_id = 0
		) {
			Object(code: (int) code, message: message);
			if (code == RpcErrorCode.INTERNAL_ERROR) {
				GLib.critical(
					"RpcClient: %s %s: %s",
					method.length > 0 ? method : "(no method)",
					request_id > 0 ? "id=" + request_id.to_string() : "",
					message
				);
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
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}
	}
}
