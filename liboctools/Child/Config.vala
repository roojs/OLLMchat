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

namespace OLLMtools.Child
{
	/**
	 * Tool-specific configuration for agent tools with model usage.
	 *
	 * This configuration class extends BaseToolConfig and adds a ModelUsage
	 * property for configuring the model used by the agent tool.
	 *
	 * All properties must be GObject properties with proper metadata for
	 * Phase 2 UI generation via property introspection.
	 */
	public class Config : OLLMchat.Settings.BaseToolConfig
	{
		/**
		 * Model configuration (connection, model, options).
		 *
		 * Used for the agent tool's model preference. If not configured,
		 * falls back to the session's model.
		 */
		public OLLMchat.Settings.ModelUsage model_usage { get; set; default = new OLLMchat.Settings.ModelUsage(); }

		/**
		 * Default constructor.
		 */
		public Config()
		{
		}
	}
}
