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

/**
 * Opt-in live GObject handles for {@link OLLMrpc}.
 *
 * The OLLMrpc.Live namespace is the RPC side of
 * {@link Transport.Connection.live_handles}:
 * {@link Remote} ref and unref.
 * {@link Subscribe} for notify and named signals.
 * {@link Subscription} holds one connected handler.
 * Wire prefixes stay ''Remote'' and ''Subscribe''
 * (one-dot ''Object.method'').
 *
 * == Example ==
 *
 * {{{
 * OLLMrpc.Live.RemoteParams.rpc_register();
 * OLLMrpc.Live.SubscribeParams.rpc_register();
 * OLLMrpc.Request.register(
 *     "Remote", new OLLMrpc.Live.Remote(),
 *     typeof(OLLMrpc.Live.RemoteParams));
 * OLLMrpc.Request.register(
 *     "Subscribe", new OLLMrpc.Live.Subscribe(),
 *     typeof(OLLMrpc.Live.SubscribeParams));
 * }}}
 */
namespace OLLMrpc.Live
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMrpc.Live.
	 */
	internal class NamespaceDoc {}
}
