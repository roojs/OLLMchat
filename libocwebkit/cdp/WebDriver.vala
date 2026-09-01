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

#if ANDROID
using WebKitGtkAndroid;
#else
using WebView2Gtk;
#endif

/**
 * Same-process CDP input client for the primary WebView.
 *
 * Meson compiles this file for Windows and Android as
 * {{{OLLMwebkit.WebDriver}}}. {{{prepare}}} binds the inspector port;
 * {{{send}}} expands Automation params to CDP {{{Input.*}}}.
 *
 * == Example ==
 *
 * {{{
 * OLLMwebkit.WebDriver.instance = new OLLMwebkit.WebDriver();
 * OLLMwebkit.WebDriver.instance.prepare();
 * yield OLLMwebkit.WebDriver.instance.fill(browser.a11y, browser.web_view, fields);
 * }}}
 *
 * @see OLLMwebkit.Browser
 */
public class OLLMwebkit.WebDriver : Object
{
	/**
	 * Process-wide client. Constructed in {{{main}}} before {{{prepare}}}.
	 */
	public static OLLMwebkit.WebDriver instance;

	/**
	 * Browsing-context handle. Empty until {{{attach}}} succeeds.
	 */
	public string session_id { get; set; default = ""; }

	/**
	 * Session id sent with {{{StartAutomationSession}}}.
	 */
	public string browser_name { get; set; default = ""; }

	/**
	 * CDP port ({{{WEBKIT_INSPECTOR_SERVER}}}).
	 */
	public uint16 inspector_port = 0;

	protected uint64 connection_id = 0;
	protected uint64 target_id = 0;
	protected int command_id = 0;
	protected int reply_id = 0;
	protected OLLMwebkit.WebDriverValue incoming_reply { get; set; default = new OLLMwebkit.WebDriverValue(); }
	protected bool have_reply = false;
	protected bool attaching = false;
	protected bool listening = false;
	protected string paste_text = "";
	protected signal void targeted ();
	protected signal void replied ();
	protected signal void attached ();

	private Soup.Session http { get; set; default = new Soup.Session(); }
	private Soup.WebsocketConnection sock;
	private string page_uri = "";
	private string page_opened = "";
	private string inbox_text = "";

	construct
	{
		this.http.set_timeout(8);
	}


/**
	 * Bind a loopback inspector port and set {{{WEBKIT_INSPECTOR_SERVER}}}
	 * before any WebView is created.
	 *
	 * @throws GLib.Error when a loopback bind fails
	 */
	public void prepare() throws GLib.Error
	{
		var probe = new GLib.Socket(GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
		probe.bind(new GLib.InetSocketAddress(new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0), true);
		this.inspector_port = ((GLib.InetSocketAddress) probe.get_local_address()).get_port();
		probe.close();
		GLib.Environment.set_variable("WEBKIT_INSPECTOR_SERVER",
			"127.0.0.1:" + this.inspector_port.to_string(), true);
		GLib.Environment.set_variable("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS", "1", true);
		this.browser_name = "OLLMchat";
	}

	/**
	 * Wait for CDP, open the page WebSocket, then StartAutomationSession
	 * → Setup → {{{new_session}}}.
	 */
	public async void attach()
	{
		if (this.session_id != "") {
			return;
		}
		if (this.attaching) {
			var wait_id = 0UL;
			wait_id = this.attached.connect(() => {
				this.disconnect(wait_id);
				this.attach.callback();
			});
			yield;
			if (this.session_id != "") {
				return;
			}
		}
		this.attaching = true;
		this.target_id = 0;
		this.connection_id = 0;
		if (!this.listening) {
			if (!yield this.await_cdp()) {
				return;
			}
		}
		var caps = new GLib.VariantBuilder(new GLib.VariantType("a{sv}"));
		this.write("StartAutomationSession",
			new GLib.Variant("(s@a{sv})", this.browser_name, caps.end()));
		var target_wait = 0UL;
		target_wait = this.targeted.connect(() => {
			this.disconnect(target_wait);
			this.attach.callback();
		});
		yield;
		if (this.target_id == 0) {
			this.attaching = false;
			this.attached();
			GLib.warning("inspector: no automation target");
			return;
		}
		this.write("Setup", new GLib.Variant("(tt)", this.connection_id, this.target_id));
		try {
			yield this.new_session();
		} catch (GLib.Error session_error) {
			this.attaching = false;
			this.attached();
			GLib.warning("%s", session_error.message);
			return;
		}
		this.attaching = false;
		this.attached();
	}

	/**
	 * Wait for CDP {{{/json/version}}} and open the page WebSocket.
	 *
	 * @return false when version never becomes ready or {{{open_page}}} fails
	 */
	private async bool await_cdp()
	{
		this.http.set_timeout(2);
		var version_ok = false;
		for (var i = 0; i < 50; i++) {
			var version_url = "http://127.0.0.1:"
				+ this.inspector_port.to_string() + "/json/version";
			var version_msg = new Soup.Message("GET", version_url);
			try {
				yield this.http.send_and_read_async(
					version_msg, GLib.Priority.DEFAULT, null
				);
			} catch (GLib.Error connect_error) {
				GLib.Timeout.add(200, () => {
					this.await_cdp.callback();
					return false;
				});
				yield;
				continue;
			}
			if (version_msg.status_code == 200) {
				version_ok = true;
				break;
			}
			GLib.Timeout.add(200, () => {
				this.await_cdp.callback();
				return false;
			});
			yield;
		}
		this.http.set_timeout(8);
		if (!version_ok) {
			this.attaching = false;
			this.attached();
			GLib.warning("cdp: /json/version not ready");
			return false;
		}
		try {
			yield this.open_page();
		} catch (GLib.Error open_error) {
			this.attaching = false;
			this.attached();
			GLib.warning("%s", open_error.message);
			return false;
		}
		return true;
	}

	protected void write(string name, GLib.Variant parameters)
		{
			if (!this.listening) {
				return;
			}
			switch (name) {
				case "StartAutomationSession":
					this.connection_id = 1;
					this.target_id = 1;
					GLib.Idle.add(() => {
						this.targeted();
						return false;
					});
					return;
				case "Setup":
				case "FrontendDidClose":
				case "SendMessageToBackend":
					return;
				default:
					return;
			}
		}

/**
		 * Expand typed Automation params to CDP {{{Input.*}}}
		 * (no JSON round-trip through {{{write}}}).
		 */
		public async OLLMwebkit.WebDriverValue send(
			string method,
			GLib.Object parameters
		) throws GLib.Error {
			yield this.open_page();
			if (method == "getBrowsingContexts") {
				var result = new OLLMwebkit.WebDriverValue();
				result.contexts.add(new OLLMwebkit.WebDriverValue() {
					handle = "cdp",
				});
				return new OLLMwebkit.WebDriverValue() {
					result = result,
				};
			}
			var out_calls = new Gee.ArrayList<OLLMwebkit.WebDriverCall>();
			switch (method) {
				case "performMouseInteraction":
					this.mouse((OLLMwebkit.WebDriverMouse) parameters, out_calls);
					break;
				case "performKeyboardInteractions":
					this.keyboard((OLLMwebkit.WebDriverKeys) parameters, out_calls);
					break;
				default:
					throw new GLib.IOError.FAILED("cdp: unknown method %s", method);
			}
			if (out_calls.size == 0) {
				throw new GLib.IOError.FAILED("cdp: empty expand");
			}
			this.have_reply = false;
			var wait_id = 0UL;
			wait_id = this.replied.connect(() => {
				this.disconnect(wait_id);
				this.send.callback();
			});
			for (var i = 0; i < out_calls.size; i++) {
				this.command_id++;
				out_calls.get(i).id = this.command_id;
				if (i == out_calls.size - 1) {
					this.reply_id = this.command_id;
				}
				this.sock.send_text(Json.gobject_to_data(out_calls.get(i), null));
			}
			yield;
			if (!this.have_reply) {
				throw new GLib.IOError.FAILED("inspector: no reply");
			}
			if (this.incoming_reply.failed) {
				throw new GLib.IOError.FAILED("inspector: %s %s",
					this.incoming_reply.name, this.incoming_reply.message);
			}
			return this.incoming_reply;
		}

	public async void delete_session() throws GLib.Error
		{
			if (this.session_id == "") {
				return;
			}
			this.write("FrontendDidClose",
				new GLib.Variant("(tt)", this.connection_id, this.target_id));
			this.session_id = "";
		}

/**
	 * Click at viewport coordinates via Automation mouse.
	 * Wanders in from a nearby point, then left-clicks.
	 *
	 * @param view WebView (GDK scale)
	 * @param x viewport X
	 * @param y viewport Y
	 * @throws GLib.Error when mouse commands fail or there is no session
	 */
	public async void click(Gtk.Widget view, int x, int y) throws GLib.Error
	{
		this.page_uri = ((WebView) view).get_uri();
		if (this.session_id == "") {
			throw new GLib.IOError.FAILED("inspector: no session");
		}
		var start_x = (x + GLib.Random.int_range(-220, -40)).clamp(8, int.max(8, x));
		var start_y = (y + GLib.Random.int_range(48, 200)).clamp(8, y + 240);
		var mid_x = ((start_x + x) / 2) + GLib.Random.int_range(-40, 41);
		var mid_y = ((start_y + y) / 2) + GLib.Random.int_range(-28, 29);
		GLib.debug("click wander %d,%d %d,%d click %d,%d", start_x, start_y, mid_x, mid_y, x, y);
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() {
				x = start_x,
				y = start_y,
			},
			button = "None",
			interaction = "Move",
		});
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 80), () => {
			this.click.callback();
			return false;
		});
		yield;
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() {
				x = mid_x,
				y = mid_y,
			},
			button = "None",
			interaction = "Move",
		});
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 80), () => {
			this.click.callback();
			return false;
		});
		yield;
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() {
				x = x,
				y = y,
			},
			button = "Left",
			interaction = "SingleClick",
		});
		GLib.Timeout.add(180 + GLib.Random.int_range(0, 220), () => {
			this.click.callback();
			return false;
		});
		yield;
	}

/**
	 * Fill by HTML name/id: click at a11y WINDOW coords, then paste.
	 * Clipboard + Ctrl+A / Ctrl+V (not per-character keys).
	 * Trailing newline means Return.
	 *
	 * @param a11y dump whose {{{nodes}}} hold fill_key + coordinates
	 * @param view WebView for GDK scale and clipboard
	 * @param fields fill key → text
	 * @throws GLib.Error when attach, locate, or keys fail
	 */
	public async void fill(
		OLLMwebkit.A11y a11y,
		Gtk.Widget view,
		Gee.HashMap<string, string> fields
	) throws GLib.Error {
		yield this.attach();
		foreach (var key in fields.keys) {
			var found = false;
			foreach (var node in a11y.nodes) {
				if (node.fill_key != key) {
					continue;
				}
				yield this.fill_node(view, node, fields.get(key));
				found = true;
				break;
			}
			if (found) {
				continue;
			}
			throw new GLib.IOError.INVALID_ARGUMENT("Unknown fill key %s", key);
		}
	}

/**
	 * Click one dump node and paste {{{typed}}} (trailing newline → Return).
	 *
	 * @param view WebView for GDK scale and clipboard
	 * @param node matched a11y node (fill_key already checked by caller)
	 * @param typed fill text for this key
	 * @throws GLib.Error when click or keys fail
	 */
	private async void fill_node(Gtk.Widget view, OLLMwebkit.A11yNode node, string typed) throws GLib.Error
	{
		var scale = int.max(1, view.scale_factor);
		var view_x = (node.x + node.width / 2) / scale;
		var view_y = (node.y + node.height / 2) / scale;
		GLib.debug("fill key=%s a11y=%d,%d %dx%d view=%d,%d",
			node.fill_key, node.x, node.y, node.width, node.height, view_x, view_y);
		yield this.click(view, view_x, view_y);
		var text = typed;
		var press_return = text.has_suffix("\n");
		if (press_return) {
			text = text.substring(0, text.length - 1);
			if (text.has_suffix("\r")) {
				text = text.substring(0, text.length - 1);
			}
		}
		view.get_clipboard().set_text(text);
		this.paste_text = text;
		GLib.debug("fill paste key=%s return=%s chars=%d",
			node.fill_key, press_return.to_string(), (int) text.char_count());
		var select_all = new OLLMwebkit.WebDriverKeys() {
			handle = this.session_id,
		};
		select_all.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyPress",
			key = "Control",
		});
		select_all.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "InsertByKey",
			text = "a",
		});
		select_all.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyRelease",
			key = "Control",
		});
		yield this.send("performKeyboardInteractions", select_all);
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 120), () => {
			this.fill_node.callback();
			return false;
		});
		yield;
		var paste = new OLLMwebkit.WebDriverKeys() {
			handle = this.session_id,
		};
		paste.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyPress",
			key = "Control",
		});
		paste.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "InsertByKey",
			text = "v",
		});
		paste.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyRelease",
			key = "Control",
		});
		yield this.send("performKeyboardInteractions", paste);
		if (!press_return) {
			return;
		}
		GLib.Timeout.add(220 + GLib.Random.int_range(0, 280), () => {
			this.fill_node.callback();
			return false;
		});
		yield;
		var ret = new OLLMwebkit.WebDriverKeys() {
			handle = this.session_id,
		};
		ret.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyPress",
			key = "Return",
		});
		yield this.send("performKeyboardInteractions", ret);
		GLib.Timeout.add(180 + GLib.Random.int_range(0, 220), () => {
			this.fill_node.callback();
			return false;
		});
		yield;
	}

/**
	 * Click a press-ref at a11y WINDOW coords (WebView viewport).
	 *
	 * @param a11y dump whose {{{nodes}}} hold press-ref coordinates
	 * @param view WebView for GDK scale
	 * @param press_id press-ref from the last dump
	 * @throws GLib.Error when attach, locate, or click fails
	 */
	public async void press(OLLMwebkit.A11y a11y, Gtk.Widget view, int press_id) throws GLib.Error
	{
		yield this.attach();
		foreach (var node in a11y.nodes) {
			if (node.press_id != press_id) {
				continue;
			}
			var scale = int.max(1, view.scale_factor);
			var view_x = (node.x + node.width / 2) / scale;
			var view_y = (node.y + node.height / 2) / scale;
			GLib.debug("press press_id=%d a11y=%d,%d %dx%d view=%d,%d",
				press_id, node.x, node.y, node.width, node.height, view_x, view_y);
			yield this.click(view, view_x, view_y);
			return;
		}
		throw new GLib.IOError.INVALID_ARGUMENT("Unknown press-ref %d", press_id);
	}

/**
	 * Resolve the browsing-context handle ({{{Automation.getBrowsingContexts}}}).
	 *
	 * @throws GLib.Error when the command fails or no context exists
	 */
	public async void new_session() throws GLib.Error
	{
		var reply = yield this.send("getBrowsingContexts", new GLib.Object());
		if (reply.result.contexts.size == 0) {
			throw new GLib.IOError.NOT_FOUND("inspector: no browsing context");
		}
		this.session_id = reply.result.contexts.get(0).handle;
	}

private void mouse(
			OLLMwebkit.WebDriverMouse mouse,
			Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls
		) {
			switch (mouse.interaction) {
				case "Move":
					out_calls.add(new OLLMwebkit.WebDriverCall() {
						method = "Input.dispatchMouseEvent",
						params = new OLLMwebkit.WebDriverCdpMouse() {
							kind = "mouseMoved",
							x = mouse.position.x,
							y = mouse.position.y,
							button = "none",
						},
					});
					break;
				case "SingleClick":
					out_calls.add(new OLLMwebkit.WebDriverCall() {
						method = "Input.dispatchMouseEvent",
						params = new OLLMwebkit.WebDriverCdpMouse() {
							kind = "mouseMoved",
							x = mouse.position.x,
							y = mouse.position.y,
							button = "none",
						},
					});
					out_calls.add(new OLLMwebkit.WebDriverCall() {
						method = "Input.dispatchMouseEvent",
						params = new OLLMwebkit.WebDriverCdpMouse() {
							kind = "mousePressed",
							x = mouse.position.x,
							y = mouse.position.y,
							button = "left",
							buttons = 1,
							click_count = 1,
						},
					});
					out_calls.add(new OLLMwebkit.WebDriverCall() {
						method = "Input.dispatchMouseEvent",
						params = new OLLMwebkit.WebDriverCdpMouse() {
							kind = "mouseReleased",
							x = mouse.position.x,
							y = mouse.position.y,
							button = "left",
							click_count = 1,
						},
					});
					break;
			}
		}

private void keyboard(
			OLLMwebkit.WebDriverKeys keys,
			Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls
		) {
			var modifiers = 0;
			foreach (var step in keys.interactions) {
				switch (step.kind) {
					case "KeyPress":
						this.key_press(step, out_calls, ref modifiers);
						break;
					case "KeyRelease":
						this.key_release(step, out_calls, ref modifiers);
						break;
					case "InsertByKey":
						this.insert_key(step, out_calls, modifiers);
						break;
				}
			}
		}

private void key_press(
			OLLMwebkit.WebDriverKey step,
			Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls,
			ref int modifiers
		) {
			switch (step.key) {
				case "Control":
					modifiers = 2;
					out_calls.add(new OLLMwebkit.WebDriverCall() {
						method = "Input.dispatchKeyEvent",
						params = new OLLMwebkit.WebDriverCdpKey() {
							kind = "keyDown",
							key = "Control",
							code = "ControlLeft",
							modifiers = 2,
							windows_virtual_key_code = 17,
							native_virtual_key_code = 17,
						},
					});
					break;
				case "Return":
					out_calls.add(new OLLMwebkit.WebDriverCall() {
						method = "Input.dispatchKeyEvent",
						params = new OLLMwebkit.WebDriverCdpKey() {
							kind = "keyDown",
							key = "Enter",
							code = "Enter",
							windows_virtual_key_code = 13,
							native_virtual_key_code = 13,
						},
					});
					out_calls.add(new OLLMwebkit.WebDriverCall() {
						method = "Input.dispatchKeyEvent",
						params = new OLLMwebkit.WebDriverCdpKey() {
							kind = "keyUp",
							key = "Enter",
							code = "Enter",
							windows_virtual_key_code = 13,
							native_virtual_key_code = 13,
						},
					});
					break;
			}
		}

private void key_release(
			OLLMwebkit.WebDriverKey step,
			Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls,
			ref int modifiers
		) {
			if (step.key != "Control") {
				return;
			}
			out_calls.add(new OLLMwebkit.WebDriverCall() {
				method = "Input.dispatchKeyEvent",
				params = new OLLMwebkit.WebDriverCdpKey() {
					kind = "keyUp",
					key = "Control",
					code = "ControlLeft",
					windows_virtual_key_code = 17,
					native_virtual_key_code = 17,
				},
			});
			modifiers = 0;
		}

private void insert_key(
			OLLMwebkit.WebDriverKey step,
			Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls,
			int modifiers
		) {
			if (modifiers == 2 && step.text == "v") {
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.insertText",
					params = new OLLMwebkit.WebDriverCdpText() {
						text = this.paste_text,
					},
				});
				return;
			}
			if (step.text != "a") {
				return;
			}
			out_calls.add(new OLLMwebkit.WebDriverCall() {
				method = "Input.dispatchKeyEvent",
				params = new OLLMwebkit.WebDriverCdpKey() {
					kind = "keyDown",
					key = "a",
					code = "KeyA",
					modifiers = modifiers,
					windows_virtual_key_code = 65,
					native_virtual_key_code = 65,
				},
			});
			out_calls.add(new OLLMwebkit.WebDriverCall() {
				method = "Input.dispatchKeyEvent",
				params = new OLLMwebkit.WebDriverCdpKey() {
					kind = "keyUp",
					key = "a",
					code = "KeyA",
					modifiers = modifiers,
					windows_virtual_key_code = 65,
					native_virtual_key_code = 65,
				},
			});
		}

private async void open_page() throws GLib.Error
		{
			if (this.listening && this.page_uri == this.page_opened) {
				return;
			}
			if (this.listening) {
				this.sock.close(Soup.WebsocketCloseCode.NORMAL, "");
				this.listening = false;
			}
			var list_url = "http://127.0.0.1:"
				+ this.inspector_port.to_string() + "/json/list";
			var list_msg = new Soup.Message("GET", list_url);
			var list_bytes = yield this.http.send_and_read_async(
				list_msg, GLib.Priority.DEFAULT, null
			);
			if (list_msg.status_code != 200) {
				throw new GLib.IOError.FAILED(
					"cdp: /json/list HTTP %u", list_msg.status_code
				);
			}
			var parser = new Json.Parser();
			parser.load_from_data(
				(string) list_bytes.get_data(),
				(ssize_t) list_bytes.get_size()
			);
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
				throw new GLib.IOError.FAILED("cdp: /json/list is not an array");
			}
			var arr = root.get_array();
			var picked = "";
			var picked_url = "";
			var fallback = "";
			var fallback_url = "";
			for (var i = 0; i < arr.get_length(); i++) {
				var o = arr.get_object_element(i);
				if (o == null) {
					continue;
				}
				if (o.get_string_member_with_default("type", "") != "page") {
					continue;
				}
				var url = o.get_string_member_with_default("url", "");
				var ws = o.get_string_member_with_default(
					"webSocketDebuggerUrl", ""
				);
				if (ws == "") {
					continue;
				}
				if (fallback == "") {
					fallback = ws;
					fallback_url = url;
				}
				if (this.page_uri == "") {
					continue;
				}
				if (url != this.page_uri && !url.has_prefix(this.page_uri)
					&& !this.page_uri.has_prefix(url)) {
					continue;
				}
				picked = ws;
				picked_url = url;
				break;
			}
			if (picked == "") {
				picked = fallback;
				picked_url = fallback_url;
			}
			if (picked == "") {
				throw new GLib.IOError.NOT_FOUND("cdp: no page in /json/list");
			}
			GLib.debug("cdp page url=%s want=%s", picked_url, this.page_uri);
			var http_ws = picked.replace("ws://", "http://").replace(
				"wss://", "https://"
			);
			var ws_msg = new Soup.Message("GET", http_ws);
			this.sock = yield this.http.websocket_connect_async(
				ws_msg, null, null, GLib.Priority.DEFAULT, null
			);
			this.sock.message.connect((type, message) => {
				if (type != Soup.WebsocketDataType.TEXT) {
					return;
				}
				this.inbox_text = (string) message.get_data();
				this.ingest();
			});
			this.sock.closed.connect(() => {
				this.listening = false;
				this.session_id = "";
				this.target_id = 0;
				this.replied();
				this.targeted();
			});
			this.listening = true;
			this.page_opened = this.page_uri;
		}

private void ingest()
		{
			try {
				this.incoming_reply = (OLLMwebkit.WebDriverValue) Json.gobject_from_data(
					typeof (OLLMwebkit.WebDriverValue), this.inbox_text, -1
				);
			} catch (GLib.Error json_error) {
				GLib.warning("%s", json_error.message);
				return;
			}
			if (this.incoming_reply.id != this.reply_id) {
				return;
			}
			this.have_reply = true;
			this.replied();
		}

}
