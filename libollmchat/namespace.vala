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

/**
 * LLM chat client namespace.
 *
 * The OLLMchat namespace provides a complete client library for interacting with
 * Ollama API and OpenAI-compatible REST interfaces. It handles chat conversations,
 * tool calling, streaming responses, history management, and configuration without
 * GTK dependencies, allowing use in both GUI and non-GUI contexts. The namespace
 * includes Client for API communication, Call and Response classes for API operations,
 * Message for chat messages, Tool system for function calling, History for session
 * persistence, Settings for configuration, and Prompt system for agent-based conversations.
 *
 * == Architecture Benefits ==
 *
 * * Separation of Concerns: Core logic without GUI dependencies
 * * Tool Integration: Extensible function-calling system with permissions
 * * Streaming Support: Real-time response streaming
 * * History Persistence: Automatic session management
 * * Flexible Configuration: Multiple connection support
 * * Agent System: Pluggable prompt generation
 *
 * == Usage Examples ==
 *
 * === Basic Chat ===
 *
 * {{{
 * var connection = new Settings.Connection() {
 *     url = "http://127.0.0.1:11434/api"
 * };
 * var client = new Client(connection) {
 *     model = "llama3.2"
 * };
 *
 * var response = yield client.chat("Hello, how are you?");
 * print(response.message.content);
 * }}}
 *
 * === Chat with Tools ===
 *
 * {{{
 * var client = new Client(connection) {
 *     model = "llama3.2"
 * };
 *
 * // Add a tool
 * var read_file_tool = new Tools.ReadFile(client);
 * client.addTool(read_file_tool);
 *
 * // Chat will automatically use tools when needed
 * var response = yield client.chat("Read the file README.md");
 * }}}
 *
 * === Streaming Responses ===
 *
 * {{{
 * client.stream = true;
 * client.message_created.connect((msg, content) => {
 *     if (msg.is_content && msg.is_stream) {
 *         print(content.chat_content);
 *     }
 * });
 *
 * yield client.chat("Tell me a story");
 * }}}
 *
 * === History Management ===
 *
 * {{{
 * var manager = new History.Manager(history_dir, db, client, config);
 *
 * // Create new session
 * var session = yield manager.new_session();
 *
 * // Switch to existing session
 * yield manager.switch_to_session(existing_session);
 *
 * // Save current session
 * yield manager.save_session();
 * }}}
 *
 * == Best Practices ==
 *
 *  1. Connection Setup: Always set connection before creating Client
 *  2. Model Selection: Set model from Config2's usage map if available
 *  3. Tool Registration: Add tools before starting chat conversations
 *  4. Permission Checking: Implement ChatPermission.Provider for tool security
 *  5. Error Handling: Wrap API calls in try-catch blocks
 *  6. Streaming: Use message_created signal for real-time updates
 *  7. Session Management: Use History.Manager for persistent conversations
 */
namespace OLLMchat
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMchat.
	 */
	internal class NamespaceDoc {}
}

