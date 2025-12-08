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

namespace OLLMchatGtk.Tools
{
	/**
	 * GTK-specific version of RunCommand that creates SourceView widgets
	 * for displaying terminal output.
	 * 
	 * This class extends Tools.RunCommand and adds GTK widget creation.
	 * It should only be used when building with GTK dependencies.
	 */
	public class RunCommand : OLLMchat.Tools.RunCommand
	{
		public RunCommand(OLLMchat.Client client, string base_directory) throws Error
		{
			base(client, base_directory);
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestRunCommand), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

