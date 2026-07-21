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
public class OLLMwebkit.Tool : OLLMchat.Tool.BaseTool, OLLMchat.Tool.UiWidgets
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
Interactive web browser for this chat session (Google search, open URL, press/fill,
download, whereami). Replaces google_search / web_fetch when those are off.

MUST call {"action": "help"} first if this overview is not already in context.
MUST call {"action": "help", "topic": "<action>"} (e.g. topic "search" or "fetch")
before using that action if its help page is not in context. Do not invent
argument shapes — read help, then call with the documented parameters
(e.g. search needs action + query; fetch needs action + url).""";
	} }

	public override string parameter_description { get {
		return """
@param action {string} [required] See help. One of: help, fetch, search, press, download, whereami.
@param topic {string} [optional] See help. With action help: which topic page (fetch, search, press, download, whereami, format).
@param url {string} [optional] See help. Required with action fetch or download.
@param query {string} [optional] See help. Required with action search: search terms.
@param press {integer} [optional] See help. Required with action press: press-ref id from the last a11y dump.
@param fill {object} [optional] See help. For press: map of press-ref id to text — not an action.
@param format {string} [optional] See help. a11y (default), html, or markdown.""";
	} }

	/**
	 * Browser stack for this tool instance (one per chat when wired).
	 *
	 * Created on first access — not in the constructor — so
	 * {@code register_config} / {@code setup_config_defaults} can
	 * instantiate the tool without building WebKit/GTK chrome.
	 */
	private OLLMwebkit.BrowserStack owned_stack;
	private bool has_stack = false;

	public OLLMwebkit.BrowserStack stack {
		get {
			if (this.has_stack) {
				return this.owned_stack;
			}
			this.owned_stack = new OLLMwebkit.BrowserStack();
			this.owned_stack.cloudflare_blocked.connect((browser) => {
				this.show_view();
			});
			this.has_stack = true;
			return this.owned_stack;
		}
		set {
			this.owned_stack = value;
			this.has_stack = true;
			this.owned_stack.cloudflare_blocked.connect((browser) => {
				this.show_view();
			});
		}
	}

	public string icon_name { get { return "web-browser-symbolic"; } }

	public string tooltip_text { get { return "Browser"; } }

	public GLib.Object view_widget { get { return this.stack; } }

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
