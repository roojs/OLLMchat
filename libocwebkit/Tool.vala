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

/**
 * OLLMchat tool wire name ''browser'' — drives {@link BrowserStack.primary}.
 *
 * Call ''action'' ''help'' (and ''topic'') for operational pages shipped in this library’s GResource.
 */
public class OLLMwebkit.Tool : OLLMchat.Tool.BaseTool
{
	public override string name { get { return "browser"; } }

	public override Type config_class()
	{
		return typeof(OLLMchat.Settings.BaseToolConfig);
	}

	public override string title { get { return "Browser"; } }

	public override string example_call {
		get { return "{\"name\": \"browser\", \"arguments\": {\"action\": \"help\"}}"; }
	}

	public override string description { get {
		return """
General-purpose web browser for this chat session (accessibility dump, press, fill).

Call action "help" when the overview is not in context. Call action "help" with
topic set to an action name (e.g. "press") before using that action if its help
page is not in context.""";
	} }

	public override string parameter_description { get {
		return """
@param action {string} [required] One of: help, fetch, search, press, download, where. See help.
@param topic {string} [optional] With action help: which topic page (fetch, search, press, download, where, format).
@param url {string} [optional] For fetch, download, and search (search: Google URL including the query).
@param press {integer} [optional] For action press: press-ref id from the last a11y dump.
@param fill {object} [optional] For press: map of press-ref id to text, e.g. {\"1\": \"terms\"} — not an action.
@param format {string} [optional] a11y (default), html, or markdown.""";
	} }

	/**
	 * Browser stack for this tool instance (one per chat when wired).
	 */
	public OLLMwebkit.BrowserStack stack {
		get;
		set;
		default = new OLLMwebkit.BrowserStack();
	}

	public Tool()
	{
		base();
	}

	protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
	{
		return Json.gobject_deserialize(typeof(OLLMwebkit.Request), parameters_node)
			as OLLMchat.Tool.RequestBase;
	}
}
