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
		get {
			return "{\"name\": \"browser\", \"arguments\": {\"action\": \"fetch\", \"url\": \"https://example.com\"}}";
		}
	}

	public override string description { get {
		return """
You have control over a web browser for the lifetime of this chat session.
Navigating (fetch, search, press) returns an accessibility output of the page.

Actions: fetch, search, press, download, whereami.

Default output (format "a11y"):
  # Page → URL / Title
  ## Content — layout by screen position (same y shares a line). Pressables as
    [label](^press:N){x,y}
  ## References — (^press:N): role, label; links as [text](url); values when
    editable fields expose them

Once you have output, prefer press on a ref from that output over fetch with a
hand-copied URL when the control is already listed. fill lets you fill form
fields and is used alongside action press (not a separate action). Prefer
format "a11y" (html/markdown may be unavailable).

Typical flow: search or fetch → read Content + References → press (+ fill) →
read output → repeat → download if needed.""";
	} }

	public override string parameter_description { get {
		return """
@param action {string} [required] One of:
  "fetch" — fetch a page (open URL, return page output).
  "search" — Google web search (return results output).
  "press" — press a button or link on the screen. Optional fill. Do not send url.
    Returns the resulting page after press as output.
  "download" — download the URL into the platform Downloads folder (this browser
    session). Returns once the download has started (destination path). Progress
    and completion are reported in the activity bar; if the same URL is already
    downloading, returns that it is already in progress.
  "whereami" — current browser state (returns page output; no navigation).
@param url {string} [optional] Absolute http(s) URL. Required for fetch or download. Do not send with press.
@param query {string} [optional] Required for search: search terms (not a URL).
@param press {integer} [optional] Required for press: N from [label](^press:N) / References in the last a11y output.
@param fill {object} [optional] Optional with action press: map of press-ref id → text
  (e.g. {"1": "site:example.com notes"}). Keys are press-ref ids from the a11y
  output, not HTML name attributes. Fields are typed, then the press runs; the
  tool result is the page after the press.
@param format {string} [optional] For fetch, search, press, whereami: "a11y" (default — Content + References; needed for press/fill), "html", or "markdown". Prefer a11y.""";
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
