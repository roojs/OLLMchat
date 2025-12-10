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

namespace OLLMchat.History
{
	/**
	 * Generates concise titles for chat conversations using LLM.
	 * 
	 * Uses the Ollama generate API to create meaningful titles from chat content.
	 */
	public class TitleGenerator : Object
	{
		private OLLMchat.Config config;
		private OLLMchat.Client client;
		
		public TitleGenerator(OLLMchat.Config config)
		{
			this.config = config;
			// Create a config for the title generation client with title_model
			var title_config = config.clone();
			title_config.model = this.config.title_model;
			this.client = new OLLMchat.Client(title_config) {
				stream = false
			};
		}
		
		/**
		 * Generate a title from a chat conversation.
		 * 
		 * Extracts the first user message and generates a concise title.
		 * If client is not set or model is not available, returns a default title.
		 * 
		 * @param session The SessionBase object containing the conversation messages
		 * @return Generated title string
		 */
		public async string to_title(SessionBase session)
		{
			// If model is empty, return default title
			if (this.client.config.model == "") {
				return this.get_default_title(session);
			}
			
			// Find first user-sent message from session.messages (not chat.messages)
			// because "user-sent" messages are only in session.messages
			string first_message = "";
			foreach (var msg in session.messages) {
				if (msg.role != "user-sent") {
					continue;
				}
				first_message = msg.content;
				break;
			}
			
			// Exit early if no user-sent message found
			if (first_message == "") {
				return this.get_default_title(session);
			}
			
			// Try to generate title, fall back to default on error
			try {
				// Build prompt for title generation
				var prompt = "Generate a concise title (maximum 8 words) for this chat conversation based on the first user message:\n\n" +
					"\"" + first_message + "\"\n\n" +
					"Respond with ONLY the title, no explanation or quotes.";
				
				// Use generate API to get title
				var response = yield this.client.generate(prompt);
				
				// Extract and clean the title
				var title = response.response.strip();
				// Remove quotes if present
				if (title.has_prefix("\"") && title.has_suffix("\"")) {
					title = title.substring(1, title.length - 2);
				}
				if (title.has_prefix("'") && title.has_suffix("'")) {
					title = title.substring(1, title.length - 2);
				}
				
				return title.strip();
			} catch (Error e) {
				GLib.warning("Title generation failed: %s", e.message);
				return this.get_default_title(session);
			}
		}
		
		/**
		 * Gets a default title from the first user-sent message.
		 */
		private string get_default_title(SessionBase session)
		{
			// Find first user-sent message from session.messages (not chat.messages)
			// because "user-sent" messages are only in session.messages
			foreach (var msg in session.messages) {
				if (msg.role != "user-sent") {
					continue;
				}
				
				var content = msg.content.strip();
				if (content == "") {
					return "Untitled Chat";
				}
				// Use first line or first 50 characters
				var lines = content.split("\n");
				var title = lines[0].strip();
				if (title.length > 50) {
					title = title.substring(0, 47) + "...";
				}
				return title;
			}
			return "Untitled Chat";
		}
	}
}

