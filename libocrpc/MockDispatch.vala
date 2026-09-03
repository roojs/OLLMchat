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

namespace OLLMrpc
{
	/**
	 * Optional helper hook after {@link Ffi} miss.
	 *
	 * Registered via {@link Request.register_mock}. Return false to
	 * fall through to {@link GiMock}. When no helper is registered,
	 * {@link Request.dispatch} uses {@link Gi}.
	 * Production compositor servers must not register a helper.
	 */
	public interface MockDispatch : GLib.Object
	{
		/**
		 * Try to handle one inbound request.
		 *
		 * When returning true, must call {@link Request.reply} or
		 * {@link Transport.Connection.reply_error}. When returning false,
		 * {@link Request.dispatch} continues to {@link GiMock}.
		 *
		 * @param request inbound call with {@link Request.connection} set
		 * @return true when this helper handled the call
		 */
		public abstract bool dispatch(Request request);
	}
}
