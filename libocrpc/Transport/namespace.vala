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
 * Server listen and connection layer for {@link OLLMrpc}.
 *
 * The OLLMrpc.Transport namespace owns daemon-side sockets: {@link Listen}
 * accept loops, {@link Connection} per peer, and helpers for Unix socket
 * ({@link SocketListen}) or TCP ({@link TcpListen}). Each connection keeps
 * one {@link OLLMrpc.Bin.Stream} for the peer lifetime.
 *
 * == Example ==
 *
 * {{{
 * var listen = new OLLMrpc.Transport.SocketListen(socket_path);
 * if (!listen.start()) {
 *     GLib.error("failed to listen on %s", socket_path);
 * }
 * // Incoming peers become Connection instances; use broadcast() to fan out
 * }}}
 */
namespace OLLMrpc.Transport
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMrpc.Transport.
	 */
	internal class NamespaceDoc {}
}
