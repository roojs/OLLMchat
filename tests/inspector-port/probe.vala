/*
 * Unauthenticated WebKit inspector exposure.
 *
 * Calls the real Linux WebDriver.prepare and WebViewAuto, then connects
 * to the loopback port with no credential and tries to read the page.
 * Exits 1 while that read or a navigation succeeds. Exits 0 once a
 * client that presents no credential cannot do either.
 *
 * Not covered here (different platform files, same prepare pattern):
 * libocwebkit/cdp/WebDriver.vala prepare, windows/WebViewAuto.vala,
 * android/WebViewAuto.vala plus webkitgtk-android's loopback CDP proxy.
 */

public class InspectorProbe : GLib.Object
{
	private const string MARKER = "INSPECTOR_PAGE_MARKER_9f3c";

	private OLLMwebkit.WebDriver driver;
	private OLLMwebkit.Browser browser;
	private Gtk.Window window;
	private GLib.MainLoop loop;
	private GLib.SocketConnection sock;
	private GLib.ByteArray inbox = new GLib.ByteArray();
	private bool listening = false;
	private bool started = false;
	private bool leaked = false;
	private bool saw_page = false;
	private bool sent_setup = false;
	private bool sent_eval = false;
	private bool sent_nav = false;
	private string inner_page = "";
	private int command_id = 0;
	private uint64 connection_id = 0;
	private uint64 target_id = 0;
	private uint64 page_target = 0;
	private uint64 automation_target = 0;
	private string page_handle = "";

	public int run()
	{
		var client_port = GLib.Environment.get_variable("INSPECTOR_CLIENT");
		if (client_port != null && client_port != "") {
			this.driver = new OLLMwebkit.WebDriver();
			this.driver.inspector_port = (uint16) int.parse(client_port);
			this.loop = new GLib.MainLoop();
			this.begin();
			GLib.Timeout.add_seconds(20, () => {
				this.loop.quit();
				return false;
			});
			this.loop.run();
			if (this.leaked) {
				stdout.printf("FAIL unauthenticated client read or navigated the page\n");
				return 1;
			}
			stdout.printf("PASS unauthenticated client did not read or navigate the page\n");
			return 0;
		}
		Gtk.init();
		this.driver = new OLLMwebkit.WebDriver();
		try {
			this.driver.prepare();
		} catch (GLib.Error e) {
			stdout.printf("prepare failed: %s\n", e.message);
			return 2;
		}
		stdout.printf("WEBKIT_INSPECTOR_SERVER=%s port=%u\n",
			GLib.Environment.get_variable("WEBKIT_INSPECTOR_SERVER"),
			this.driver.inspector_port);
		this.browser = new OLLMwebkit.Browser();
		this.browser.web_view = new OLLMwebkit.WebViewAuto(this.browser);
		this.window = new Gtk.Window();
		this.window.set_default_size(640, 480);
		this.window.set_child(this.browser.web_view);
		this.window.present();
		stdout.printf("developer_extras=%s\n",
			this.browser.web_view.get_settings().enable_developer_extras.to_string());
		this.browser.web_view.load_html(
			"<html><head><title>agent-page</title></head><body><p id=\"m\">" +
			MARKER + "</p><script>document.cookie=\"agent_session=" + MARKER +
			"\";</script></body></html>",
			"https://agent.invalid/");
		this.loop = new GLib.MainLoop();
		var serve_only = GLib.Environment.get_variable("INSPECTOR_SERVE") == "1";
		if (!serve_only) {
			this.browser.web_view.load_changed.connect((ev) => {
				if (ev != WebKit.LoadEvent.FINISHED) {
					return;
				}
				this.begin();
			});
			GLib.Timeout.add_seconds(4, () => {
				this.begin();
				return false;
			});
		} else {
			stdout.printf("SERVE port=%u\n", this.driver.inspector_port);
		}
		if (!serve_only) {
			GLib.Timeout.add_seconds(25, () => {
				stdout.printf("timeout leaked=%s saw_page=%s\n",
					this.leaked.to_string(), this.saw_page.to_string());
				this.loop.quit();
				return false;
			});
		}
		this.loop.run();
		if (this.leaked) {
			stdout.printf("FAIL unauthenticated client read or navigated the page\n");
			return 1;
		}
		stdout.printf("PASS unauthenticated client did not read or navigate the page\n");
		return 0;
	}

	private void begin()
	{
		if (this.started) {
			return;
		}
		this.started = true;
		var client = new GLib.SocketClient();
		client.connect_to_host_async.begin("127.0.0.1", this.driver.inspector_port, null,
			(obj, res) => {
			try {
				this.sock = client.connect_to_host_async.end(res);
			} catch (GLib.Error e) {
				stdout.printf("connect failed: %s\n", e.message);
				this.loop.quit();
				return;
			}
			stdout.printf("connected without a credential\n");
			this.sock.get_socket().set_blocking(false);
			var source = this.sock.get_socket().create_source(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR, null);
			source.set_callback((socket, condition) => {
				this.ingest();
				return this.listening;
			});
			source.attach(null);
			this.listening = true;
			var hash = new GLib.Variant.bytestring("");
			this.write_msg("SetupInspectorClient", new GLib.Variant("(@ay)", hash));
		});
	}

	private void write_msg(string name, GLib.Variant parameters)
	{
		if (!this.listening && name != "SetupInspectorClient" && name != "StartAutomationSession") {
			return;
		}
		var payload = parameters.get_data_as_bytes();
		var body_size = (int) name.length + 1 + (int) payload.get_size();
		var stream = new GLib.MemoryOutputStream.resizable();
		var header = new uint8[] {
			(uint8) ((body_size >> 24) & 0xff),
			(uint8) ((body_size >> 16) & 0xff),
			(uint8) ((body_size >> 8) & 0xff),
			(uint8) (body_size & 0xff),
			1
		};
		var zero = new uint8[] { 0 };
		try {
			stream.write_all(header, null);
			stream.write_all(name.data, null);
			stream.write_all(zero, null);
			stream.write_all(payload.get_data(), null);
			stream.close();
			this.sock.get_socket().set_blocking(true);
			this.sock.get_socket().send(stream.steal_as_bytes().get_data());
			this.sock.get_socket().set_blocking(false);
		} catch (GLib.Error e) {
			stdout.printf("write %s failed: %s\n", name, e.message);
		}
	}

	private void ingest()
	{
		var chunk = new uint8[8192];
		var n = 0;
		try {
			n = (int) this.sock.get_socket().receive(chunk);
		} catch (GLib.Error e) {
			if (e is GLib.IOError.WOULD_BLOCK) {
				return;
			}
			stdout.printf("receive failed: %s\n", e.message);
			this.listening = false;
			this.loop.quit();
			return;
		}
		if (n <= 0) {
			stdout.printf("socket closed\n");
			this.listening = false;
			this.loop.quit();
			return;
		}
		this.inbox.append(chunk[0:n]);
		while (this.inbox.len >= 5) {
			if (!this.one_message()) {
				return;
			}
		}
	}

	private bool one_message()
	{
		var body_size = ((uint32) this.inbox.data[0] << 24)
			| ((uint32) this.inbox.data[1] << 16)
			| ((uint32) this.inbox.data[2] << 8)
			| (uint32) this.inbox.data[3];
		var message_size = 5 + (int) body_size;
		if (this.inbox.len < message_size) {
			return false;
		}
		var flags = this.inbox.data[4];
		var name = (string) this.inbox.data[5:message_size];
		var blob = new GLib.Bytes(this.inbox.data[(6 + name.length):message_size]);
		var rest = this.inbox.data[message_size:this.inbox.len];
		this.inbox = new GLib.ByteArray();
		this.inbox.append(rest);
		var signature = "()";
		switch (name) {
			case "SetTargetList":
				signature = "(ta(tsssb))";
				break;
			case "DidStartAutomationSession":
				signature = "(ss)";
				break;
			case "SendMessageToFrontend":
				signature = "(tts)";
				break;
			case "DidSetupInspectorClient":
				signature = "(ay)";
				break;
			default:
				stdout.printf("message %s\n", name);
				return true;
		}
		GLib.Variant incoming;
		try {
			incoming = new GLib.Variant.from_bytes(
				new GLib.VariantType(signature), blob, false);
		} catch (GLib.Error e) {
			stdout.printf("parse %s failed: %s\n", name, e.message);
			return true;
		}
		if ((flags & 1) == 0) {
			incoming = incoming.byteswap();
		}
		stdout.printf("message %s\n", name);
		switch (name) {
			case "SetTargetList":
				this.on_targets(incoming);
				break;
			case "SendMessageToFrontend":
				this.on_frontend(incoming.get_child_value(2).get_string());
				break;
			default:
				break;
		}
		return true;
	}

	private void on_targets(GLib.Variant incoming)
	{
		this.connection_id = incoming.get_child_value(0).get_uint64();
		var list = incoming.get_child_value(1);
		var page = (uint64) 0;
		var automation = (uint64) 0;
		for (var i = 0; i < list.n_children(); i++) {
			var row = list.get_child_value(i);
			var kind = row.get_child_value(1).get_string();
			var tid = row.get_child_value(0).get_uint64();
			stdout.printf("target %s id=%s url=%s\n", kind, tid.to_string(),
				row.get_child_value(3).get_string());
			if (kind == "WebPage" && page == 0) {
				page = tid;
			}
			if (kind == "Automation" && automation == 0) {
				automation = tid;
			}
		}
		if (page != 0) {
			this.page_target = page;
		}
		if (automation != 0) {
			this.automation_target = automation;
		}
		if (this.page_target != 0 && !this.sent_setup) {
			this.saw_page = true;
			this.sent_setup = true;
			this.target_id = this.page_target;
			stdout.printf("setup page target %s\n", this.page_target.to_string());
			this.write_msg("Setup",
				new GLib.Variant("(tt)", this.connection_id, this.page_target));
		}
	}

	private void on_frontend(string text)
	{
		stdout.printf("frontend %s\n", text);
		if (text.contains(MARKER)) {
			this.leaked = true;
			this.loop.quit();
			return;
		}
		if (text.contains("targetCreated") && text.contains("\"type\":\"page\"")) {
			var parser = new Json.Parser();
			try {
				parser.load_from_data(text, -1);
			} catch (GLib.Error e) {
				stdout.printf("json failed: %s\n", e.message);
				return;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				return;
			}
			var info = root.get_object().get_member("params");
			if (info == null || info.get_node_type() != Json.NodeType.OBJECT) {
				return;
			}
			var target_info = info.get_object().get_member("targetInfo");
			if (target_info == null || target_info.get_node_type() != Json.NodeType.OBJECT) {
				return;
			}
			if (target_info.get_object().get_string_member("type") != "page") {
				return;
			}
			if (this.sent_eval) {
				return;
			}
			this.inner_page = target_info.get_object().get_string_member("targetId");
			this.command_id++;
			var inner_id = this.command_id;
			var inner = ("{\"id\":%d,\"method\":\"Runtime.evaluate\",\"params\":" +
				"{\"expression\":\"document.body?document.body.innerText:document.documentElement.innerText\",\"returnByValue\":true}}").printf(
				inner_id);
			var escaped = inner.replace("\\", "\\\\").replace("\"", "\\\"");
			this.command_id++;
			var outer = ("{\"id\":%d,\"method\":\"Target.sendMessageToTarget\",\"params\":" +
				"{\"targetId\":\"%s\",\"message\":\"%s\"}}").printf(
				this.command_id, this.inner_page, escaped);
			stdout.printf("send nested eval on page %s inner %s\n",
				this.page_target.to_string(), this.inner_page);
			this.write_msg("SendMessageToBackend", new GLib.Variant("(tts)",
				this.connection_id, this.page_target, outer));
			this.sent_eval = true;
			return;
		}
		if (text.contains("\"handle\"")) {
			var parser = new Json.Parser();
			try {
				parser.load_from_data(text, -1);
			} catch (GLib.Error e) {
				stdout.printf("json failed: %s\n", e.message);
				return;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				return;
			}
			var result = root.get_object().get_object_member("result");
			if (result == null || !result.has_member("contexts")) {
				return;
			}
			var contexts = result.get_array_member("contexts");
			if (contexts.get_length() == 0) {
				return;
			}
			var row = contexts.get_object_element(0);
			if (row == null || !row.has_member("handle")) {
				return;
			}
			this.page_handle = row.get_string_member("handle");
			this.command_id++;
			this.write_msg("SendMessageToBackend", new GLib.Variant("(tts)",
				this.connection_id, this.target_id,
				("{\"id\":%d,\"method\":\"Automation.evaluateJavaScriptFunction\",\"params\":{" +
				"\"browsingContextHandle\":\"%s\",\"function\":\"function(){return document.body?document.body.innerText:'';}\",\"arguments\":[]}}").printf(
					this.command_id, this.page_handle)));
			this.sent_eval = true;
			return;
		}
		if (this.sent_eval && !this.sent_nav && this.page_handle != "") {
			this.sent_nav = true;
			this.command_id++;
			this.write_msg("SendMessageToBackend", new GLib.Variant("(tts)",
				this.connection_id, this.target_id,
				("{\"id\":%d,\"method\":\"Automation.navigateBrowsingContext\",\"params\":{" +
				"\"handle\":\"%s\",\"url\":\"data:text/html,navigated-%s\"}}").printf(
					this.command_id, this.page_handle, MARKER)));
		}
	}

	public static int main(string[] args)
	{
		var probe = new InspectorProbe();
		return probe.run();
	}
}
