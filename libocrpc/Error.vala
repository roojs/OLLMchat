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

namespace OLLMrpc
{
	/**
	 * Wire error object ({{{code}}}, {{{message}}}).
	 *
	 * Not {@link GLib.Error} — {@link GLib.Object} for bin encode/decode.
	 * {@link code} is the numeric error code (a {@link RpcErrorCode} value).
	 */
	public class Error : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int code { get; set; }
		public string message { get; set; default = ""; }

		/**
		 * @param method optional RPC method (reserved; logging is on {@link Client})
		 * @param request_id optional request id (reserved)
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Error", typeof(Error));
		}

		/**
		 * @param code error number — pass {@link RpcErrorCode} constants
		 *   (e.g. {@link RpcErrorCode.INTERNAL_ERROR})
		 * @param message wire error message
		 * @param method optional RPC method (reserved; logging is on {@link Client})
		 * @param request_id optional request id (reserved)
		 */
		public Error(
			int code,
			string message,
			string method = "",
			int request_id = 0
		) {
			Object(code: code, message: message);
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}
	}
}
