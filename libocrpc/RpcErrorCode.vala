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
	 * JSON-RPC 2.0 standard and application error codes (throw/catch).
	 *
	 * Server control flow only — not the wire {@link Error} object.
	 * Constants (e.g. {@link INTERNAL_ERROR}) are {@link RpcErrorCode} values;
	 * pass them to {@link to_error} / {@link to_response} / wire {@link Error}
	 * as `int` (Vala 0.56 types errordomain members as `int` at call sites).
	 *
	 * Throw on constants: `throw (RpcErrorCode) RpcErrorCode.INVALID_PARAMS;`
	 *
	 * Static methods only — instance methods on the caught error are not
	 * supported in Vala 0.56 yet.
	 */
	public errordomain RpcErrorCode
	{
		PARSE_ERROR = -32700,
		INVALID_REQUEST = -32600,
		METHOD_NOT_FOUND = -32601,
		INVALID_PARAMS = -32602,
		INTERNAL_ERROR = -32603,
		NOT_IMPLEMENTED = -32000;

		/**
		 * Build wire {@link Error} from an RPC error number.
		 * @param code JSON-RPC error number — {@link RpcErrorCode} constant
		 *   (e.g. {@link INVALID_PARAMS})
		 */
		public static Error to_error(int code)
		{
			return new Error(code, ((RpcErrorCode) code).message);
		}

		/**
		 * @param code JSON-RPC error number — {@link RpcErrorCode} constant
		 */
		public static Response to_response(int code)
		{
			return new Response() {
				error = to_error(code)
			};
		}
	}
}
