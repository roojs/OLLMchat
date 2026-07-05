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

namespace OLLMvector
{
	/**
	 * V2 no-op {@link Registry} — codebase search lives on {{{liboctools}}}.
	 *
	 * {@link OLLMtools.CodebaseSearch.CodebaseSearchTool} is registered by
	 * {@link OLLMtools.Registry}. This stub remains until V1 {{{libocvector}}}
	 * is removed (**2.10.4.23**).
	 */
	public class Registry : Object
	{
		public void init_config()
		{
		}

		/**
		 * @param config Loaded application config
		 */
		public void setup_config_defaults(OLLMchat.Settings.Config2 config)
		{
		}

		/**
		 * @param manager Session tool registry
		 * @param project_manager Active project manager, when available
		 */
		public void fill_tools(
			OLLMchat.History.Manager manager,
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
		}
	}
}
