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
	public class CodebaseSearchToolConfig : 
		OLLMchat.Settings.BaseToolConfig, OLLMchat.Settings.RequiresModelsInterface
	{
		/**
		 * Embedding model configuration (connection, model, options).
		 *
		 * Used for converting code text into vector embeddings for semantic search.
		 */
		[Description(nick = "Embedding Model", blurb = "Model used for converting code text into vector embeddings for semantic search")]
		public OLLMchat.Settings.ModelUsage embed { get; set; default = new OLLMchat.Settings.ModelUsage(); }
		
		/**
		 * Analysis model configuration (connection, model, options).
		 *
		 * Used for analyzing code elements and generating descriptions during indexing.
		 *
		 * Default is "qwen3:1.7b" (smaller, faster). For better analysis quality,
		 * users can change this to "qwen3-coder:30b" in settings (larger model with
		 * better code understanding).
		 */
		[Description(nick = "Analysis Model", blurb = "Model used for analyzing code elements and generating descriptions during indexing. Default is qwen3:1.7b (smaller, faster). For better analysis quality, use qwen3-coder:30b (larger model with better code understanding).")]
		public OLLMchat.Settings.ModelUsage analysis { get; set; default = new OLLMchat.Settings.ModelUsage(); }

		/**
		 * Vision model configuration (connection, model, options).
		 * Optional. When not set or is_valid is false, image analysis is skipped during indexing.
		 */
		[Description(nick = "Vision Model", blurb = "Model used for describing images during indexing (default llama3.2-vision:latest). Optional; when invalid, image analysis is skipped.")]
		public OLLMchat.Settings.ModelUsage vision { get; set; default = new OLLMchat.Settings.ModelUsage(); }

		/**
		 * Default constructor.
		 */
		public CodebaseSearchToolConfig()
		{
		}
		
		/**
		 * Returns list of required models (embed and analysis models are required for app startup).
		 * 
		 * @return List of required ModelUsage objects
		 */
		public Gee.ArrayList<OLLMchat.Settings.ModelUsage> required_models()
		{
			var required = new Gee.ArrayList<OLLMchat.Settings.ModelUsage>();
			
			// Embed model is required for codebase search functionality
			required.add(this.embed);
			
			// Analysis model is required for code analysis during indexing
			required.add(this.analysis);
			
			return required;
		}
		
		/**
		 * Sets up default values for embed and analysis model configurations.
		 * 
		 * Sets default model names, options, and connection:
		 * - Embed: model "bge-m3:latest", temperature 0.0, num_ctx 2048
		 * - Analysis: model "qwen3:1.7b", temperature 0.0 (smaller, faster default)
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
				model = "qwen3:1.7b"  // CHANGED: from "qwen3-coder:30b" to smaller default
			};
			this.analysis.options = new OLLMchat.Call.Options() {
				temperature = 0.0
			};
			this.vision = new OLLMchat.Settings.ModelUsage() {
				connection = connection_url,
				model = "llama3.2-vision:latest"
			};
			this.vision.options = new OLLMchat.Call.Options() {
				temperature = 0.0
			};
		}
		
	}
}

