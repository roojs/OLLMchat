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
		private Client client;
		
		public TitleGenerator(Client client)
		{
			this.client = client;
		}
		
		/**
		 * Generate a title from a chat conversation.
		 * 
		 * Extracts the first user message and generates a concise title.
		 * 
		 * @param chat The Call.Chat object containing the conversation
		 * @return Generated title string
		 * @throws Error if generation fails
		 */
		public async string to_title(Call.Chat chat) throws Error
		{
			// Find first user message
			string first_message = "";
			foreach (var msg in chat.messages) {
				if (msg.role == "user") {
					first_message = msg.content;
					break;
				}
			}
			
			if (first_message == "") {
				return "Untitled Chat";
			}
			
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
		}
	}
}

