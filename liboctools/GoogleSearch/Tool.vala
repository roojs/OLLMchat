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

namespace OLLMtools.GoogleSearch
{
	/**
	 * Tool for performing web searches using Google Custom Search API.
	 *
	 * This tool performs web searches and returns results in markdown format.
	 * Requires Google Custom Search API credentials configured in ~/.config/ollmchat/google.json
	 */
	public class Tool : OLLMchat.Tool.BaseTool
	{
	public override string name { get { return "google_search"; } }
	
	public override string description { get {
			return """
Perform a web search using Google Custom Search API and return results in markdown format.

This tool searches the web and returns a list of relevant results with titles, snippets, and links.
Results are formatted as markdown for easy reading.

The tool requires permission to access the Google Custom Search API.""";
		} }
		
		public override string parameter_description { get {
			return """
@param query {string} [required] The search query string.
@param start {int} [optional] The starting index for results (default: 1). Use this to paginate through results.""";
		} }
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
		public Tool(OLLMfiles.ProjectManager? project_manager = null)
		{
			base();
			this.project_manager = project_manager;
			this.title = "Google Search Tool";
		}
		
		public override Type config_class() { return typeof(Config); }
		
		public OLLMchat.Tool.BaseTool? clone()
		{
			return new Tool(this.project_manager);
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

