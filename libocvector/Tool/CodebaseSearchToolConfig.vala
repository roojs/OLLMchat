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

namespace OLLMvector.Tool
{
	/**
	 * Tool-specific configuration for codebase search with multiple model usages.
	 *
	 * This configuration class extends BaseToolConfig and adds two ModelUsage
	 * properties: one for the embedding model and one for the analysis model.
	 * The codebase search tool requires both models to function properly.
	 *
	 * All properties must be GObject properties with proper metadata for
	 * Phase 2 UI generation via property introspection.
	 *
	 * @since 1.0
	 */
	public class CodebaseSearchToolConfig : OLLMchat.Settings.BaseToolConfig
	{
		/**
		 * Embedding model configuration (connection, model, options).
		 *
		 * Used for converting code text into vector embeddings for semantic search.
		 */
		public OLLMchat.Settings.ModelUsage embed { get; set; default = new OLLMchat.Settings.ModelUsage(); }
		
		/**
		 * Analysis model configuration (connection, model, options).
		 *
		 * Used for analyzing code elements and generating descriptions during indexing.
		 */
		public OLLMchat.Settings.ModelUsage analysis { get; set; default = new OLLMchat.Settings.ModelUsage(); }

		/**
		 * Default constructor.
		 */
		public CodebaseSearchToolConfig()
		{
		}
		
		/**
		 * Sets up default values for embed and analysis model configurations.
		 * 
		 * Sets default model names, options, and connection:
		 * - Embed: model "bge-m3:latest", temperature 0.0, num_ctx 2048
		 * - Analysis: model "qwen3-coder:30b", temperature 0.0
		 * - Both use the provided connection URL
		 * 
		 * @param connection_url The connection URL to use for both embed and analysis models
		 */
		public void setup_defaults(string connection_url)
		{
			this.embed = new OLLMchat.Settings.ModelUsage() {
				connection = connection_url,
				model = "bge-m3:latest"
			};
			this.embed.options = new OLLMchat.Call.Options() {
				temperature = 0.0,
				num_ctx = 2048
			};
			
			this.analysis = new OLLMchat.Settings.ModelUsage() {
				connection = connection_url,
				model = "qwen3-coder:30b"
			};
			this.analysis.options = new OLLMchat.Call.Options() {
				temperature = 0.0
			};
		}
	}
}

