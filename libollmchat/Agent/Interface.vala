/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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
		public abstract Call.Chat chat();
		
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
		 * Register a tool request for monitoring streaming chunks and message completion.
		 * 
		 * For agentic usage (Agent.Base): Connects request callbacks to agent signals.
		 * For non-agentic usage: Default implementation does nothing (no-op).
		 * 
		 * @param request_id The unique identifier for this request (auto-generated int)
		 * @param request The request object to register
		 */
		public virtual void register_tool_monitoring(int request_id, Tool.RequestBase request)
		{
			// Default: no-op for non-agentic usage
		}
		
		/**
		 * Unregister a tool request from monitoring.
		 * 
		 * For agentic usage (Agent.Base): Disconnects request callbacks and removes from registry.
		 * For non-agentic usage: Default implementation does nothing (no-op).
		 * 
		 * @param request_id The unique identifier for this request (auto-generated int)
		 */
		public virtual void unregister_tool(int request_id)
		{
			// Default: no-op for non-agentic usage
		}
	}
}

