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

namespace OLLMchat.Call
{
	/**
	 * Shared surface for chat-capable API calls.
	 *
	 * Implemented by {@link Chat} (Ollama `/api/chat`) and {@link ChatCompletions}
	 * (OpenAI-compatible `/v1/chat/completions`) so {@link Response.Chat} can hold
	 * either reference and implement {@link Response.Chat.reply} uniformly.
	 */
	public interface ChatInterface : Object
	{
		/**
		 * Append messages to the call's conversation and execute one request.
		 *
		 * @return Fresh {@link Response.Chat} for this round (same type for both APIs).
		 */
		public abstract async Response.Chat send_append(
			Gee.ArrayList<Message> new_messages,
			GLib.Cancellable? cancellable = null) throws Error;
	}
}
