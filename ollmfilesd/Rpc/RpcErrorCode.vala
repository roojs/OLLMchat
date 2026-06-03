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

namespace OLLMfilesd.Rpc
{
	/**
	 * JSON-RPC 2.0 standard and application error codes (throw/catch).
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

		public static Error to_error(RpcErrorCode e)
		{
			return new Error() {
				code = e.code,
				message = e.message
			};
		}

		public static Response to_response(Request request, RpcErrorCode e)
		{
			return new Response(request.id) {
				error = to_error(e)
			};
		}
	}
}
