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


using WebKit;

/**
 * WebView constructed for automation.
 *
 * Sets construct-only automation properties and hands
 * {{{browser.web_view}}} to the automation session.
 *
 * == Example ==
 *
 * {{{
 * this.web_view = new OLLMwebkit.WebViewAuto(this);
 * }}}
 *
 * @see OLLMwebkit.Browser
 */
public class OLLMwebkit.WebViewAuto : WebView
{
	/**
	 * @param browser owner whose {{{web_view}}} is returned when the
	 *        driver session starts
	 */
	public WebViewAuto(OLLMwebkit.Browser browser)
	{
		var context = WebContext.get_default();
		context.set_automation_allowed(true);
		Object(
			hexpand: true,
			vexpand: true,
			web_context: context,
			is_controlled_by_automation: true,
			network_session: context.get_network_session_for_automation(),
			website_policies: (WebsitePolicies) GLib.Object.new(
				typeof(WebsitePolicies),
				"autoplay", AutoplayPolicy.DENY
			)
		);
		context.automation_started.connect((session) => {
			var info = new ApplicationInfo();
			info.set_name("OLLMchat");
			info.set_version(1, 0, 0);
			session.set_application_info(info);
			session.create_web_view.connect(() => {
				return browser.web_view;
			});
			GLib.debug("automation-started session=%s", session.get_id());
		});
		this.get_settings().enable_developer_extras = true;
#if HAVE_WEBKIT_NAVIGATOR_WEBDRIVER_POLICY
		set_navigator_webdriver_active_policy(
			this.get_settings(),
			NavigatorWebDriverActivePolicy.DISABLED
		);
#endif
	}
}
