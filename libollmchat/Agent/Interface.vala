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

namespace OLLMchat.Agent
{
	/**
	 * Interface for agent implementations.
	 * 
	 * Provides the resources tools need: chat, get_permission_provider(), get_config(), and add_message().
	 * This allows tools to interact with the interface rather than the Base class directly.
	 * 
	 * Base implements this interface for agentic usage (with session).
	 * A dummy agent can implement this interface for non-agentic usage (without session).
	 * 
	 * @since 1.2.7.21
	 */
	public interface Interface : Object
	{
		/**
		 * Get the chat instance for this agent.
		 * Tools use this to create Message objects and access chat properties/methods.
		 * 
		 * @return The chat instance
		 */
		public abstract Call.ChatBase chat();
		
		/**
		 * Get the permission provider for tool execution.
		 * Tools use this to request permissions for file access, command execution, etc.
		 * 
		 * @return The permission provider instance
		 */
		public abstract ChatPermission.Provider get_permission_provider();
		
		/**
		 * Get the configuration instance for tool execution.
		 * Tools use this to access tool-specific configuration (e.g., API keys).
		 * 
		 * For agentic usage: Returns config from session.manager.config.
		 * For non-agentic usage: Dummy agent must provide a config instance.
		 * 
		 * @return The config instance
		 */
		public abstract Settings.Config2 config();
		
		/**
		 * Add a UI message to the conversation.
		 * 
		 * For agentic usage: Adds message to session.
		 * For non-agentic usage: Adds message to chat.messages or emits signal.
		 * 
		 * @param message The message to add
		 */
		public abstract void add_message(Message message);

		/**
		 * Status-bar activity ({@link OLLMrpc.Notification.method} + payload).
		 * Emit via ''notification(notif)''; {@link Agent.Base} forwards to
		 * {@link History.Manager.notification}.
		 */
		public signal void notification(OLLMrpc.Notification notif);
		
		/**
		 * Hook a tool {@link Tool.RequestBase} to assistant stream signals.
		 *
		 * Adds the request to {@link Agent.Base.monitored_requests} and connects
		 * {@link Agent.Base.stream_chunk} and {@link Agent.Base.message_completed}.
		 * Does not register or unregister tools in history.
		 *
		 * @param request_id Auto-generated id for this invocation
		 * @param request Request that implements stream callbacks
		 */
		public virtual void add_stream_monitor(
			int request_id,
			Tool.RequestBase request)
		{
			// Default: no-op for non-agentic usage
		}
		
		/**
		 * Drop a stream monitor for one request id.
		 *
		 * Disconnects stream signals and removes the entry from
		 * {@link Agent.Base.monitored_requests}.
		 *
		 * @param request_id Id passed to {@link add_stream_monitor}
		 */
		public virtual void remove_stream_monitor(int request_id)
		{
			// Default: no-op for non-agentic usage
		}
	}
}

