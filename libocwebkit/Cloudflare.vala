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

#if LINUX
using WebKit;
#endif

/**
 * Target-site Cloudflare challenge detection for a {@link Browser}.
 *
 * Watches main-document responses (Snappr Rpc.Cloudflare pattern). No PMAN
 * Client, login CF, or gateway probe APIs.
 *
 * == Example ==
 *
 * {{{
 * // Constructed by Browser; callers use browser.cloudflare.is_blocked
 * if (browser.cloudflare.is_blocked) {
 *     stack.promote();
 * }
 * }}}
 */
public class OLLMwebkit.Cloudflare : Object
{
	/**
	 * Browser whose WebView responses are watched.
	 */
	public OLLMwebkit.Browser browser { get; construct; }

	/**
	 * True when the latest main-document response needs user intervention.
	 */
	public bool is_blocked { get; set; default = false; }

	/**
	 * Emitted when {@link is_blocked} clears on a main-document response for
	 * the pending host.
	 */
	public signal void cleared();

	/**
	 * @param browser host browser (WebView + pending_load_uri)
	 */
	public Cloudflare(OLLMwebkit.Browser browser)
	{
		Object(browser: browser);
#if LINUX
		this.browser.web_view.decide_policy.connect((decision, type) => {
			if (type != PolicyDecisionType.RESPONSE) {
				return false;
			}
			var response_decision = decision as ResponsePolicyDecision;
			if (response_decision == null
					|| !response_decision.is_main_frame_main_resource()) {
				return false;
			}
			var response = response_decision.response;
			var was_blocked = this.is_blocked;
			this.is_blocked = false;
			if (this.check_browser_response(response.status_code, response.http_headers)) {
				this.is_blocked = true;
			}
			if (was_blocked && !this.is_blocked && response.uri != "") {
				var pending = this.browser.pending_load_uri;
				var same_host = false;
				if (pending != "") {
					try {
						var host_a = GLib.Uri.parse(response.uri, GLib.UriFlags.NONE).get_host();
						var host_b = GLib.Uri.parse(pending, GLib.UriFlags.NONE).get_host();
						same_host = host_a != null && host_b != null
							&& host_a.down() == host_b.down();
					} catch (GLib.Error e) {
					}
				}
				if (same_host || response.uri == pending) {
					this.cleared();
				}
			}
			return false;
		});
#endif
	}

	/**
	 * Target-site browser response — challenge-ish status + Cloudflare headers.
	 *
	 * @param status HTTP status code
	 * @param headers response headers
	 * @return true when the response looks like a CF challenge
	 */
	public bool check_browser_response(uint status, Soup.MessageHeaders headers)
	{
		switch (status) {
		case 301:
		case 302:
		case 303:
		case 307:
		case 308:
		case 403:
		case 410:
		case 503:
			break;

		default:
			return false;
		}
		var blocked = false;
		headers.foreach((name, value) => {
			if (blocked) {
				return;
			}
			var key = name.down();
			if (key == "server" && value.down() == "cloudflare") {
				blocked = true;
			} else if (key == "cf-ray" && value.strip() != "") {
				blocked = true;
			}
		});
		return blocked;
	}
}
