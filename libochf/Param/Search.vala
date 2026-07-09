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

namespace OLLMhf.Param
{
	/**
	 * Query parameters for Hub model search ({{{GET /api/models}}}).
	 *
	 * Non-empty properties become query string fields on
	 * {@link OLLMrpc.Client.send_http}. Pair with
	 * {{{Request.method = "/api/models"}}} and result_type typeof(ModelArray).
	 */
	public class Search : OLLMrpc.CallParam
	{
		/** Free-text search term. */
		public string search { get; set; default = ""; }

		/** Hub filter (default {{{gguf}}}). */
		public string filter { get; set; default = "gguf"; }

		/** Maximum hits to return (Hub cap 100). */
		public int limit { get; set; default = 20; }

		/** Sort field (default {{{downloads}}}). */
		public string sort { get; set; default = "downloads"; }

		/** Sort direction (default {{{-1}}} descending). */
		public string direction { get; set; default = "-1"; }

		public static void rpc_register() {
			OLLMrpc.Bin.register("ParamSearch", typeof(Search));
		}
	}
}
