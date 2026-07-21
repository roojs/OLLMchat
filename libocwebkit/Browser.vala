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

#if WINDOWS
using WebView2Gtk;
#endif
#if LINUX
using WebKit;
#endif

/**
 * One WebView browser session (Snappr Browser host port).
 *
 * Load settle, Soup HEAD probe, freeze overlay, and site cookies follow
 * Snappr. ''#if LINUX'' / ''#if WINDOWS'' select WebKitGTK vs webview2-gtk
 * (same portability pattern as Snappr). Dump / fill / press delegate to
 * {@link A11y} (Phase 2.1).
 *
 * == Example ==
 *
 * {{{
 * var stack = new OLLMwebkit.BrowserStack();
 * yield stack.primary.load("https://example.com/");
 * }}}
 */
public class OLLMwebkit.Browser : Gtk.Box
{
	/**
	 * Live WebView for this session (WebKitGTK or WebView2 via ifdef).
	 */
	public WebView web_view { get; private set; }

	/**
	 * Per-host Cookie header map (Snappr site_cookies — shared with stack).
	 */
	public Gee.HashMap<string, string> site_cookies {
		get;
		private set;
		default = new Gee.HashMap<string, string>();
	}

	/**
	 * Platform accessibility dump / fill / press (Linux AT-SPI).
	 */
	public OLLMwebkit.A11y a11y { get; private set; default = new OLLMwebkit.A11y(); }

	/**
	 * Target-site Cloudflare detection (Phase 4).
	 */
	public OLLMwebkit.Cloudflare cloudflare { get; private set; }

	/**
	 * URI of the WebView (empty string when unset).
	 */
	public string current_uri {
		owned get {
			return this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
		}
	}

	/**
	 * URI currently awaited by {@link load} (redirects update this).
	 */
	public string pending_load_uri { get; private set; default = ""; }

	/**
	 * Set from tool requests so click downloads can ask permission and notify.
	 */
	public OLLMchat.Agent.Interface? agent { get; set; default = null; }

	/**
	 * Owning tool when this browser is the chat browser host (set from Request).
	 */
	public OLLMchat.Tool.BaseTool? tool { get; set; default = null; }

	/**
	 * URL → destination path while a WebKit download is in progress.
	 */
	private Gee.HashMap<string, string> downloads_inflight {
		get;
		set;
		default = new Gee.HashMap<string, string>();
	}

	/**
	 * URL → active download object (WebKit Download today; Cancel in 5.0.6).
	 * Same map on all platforms — value type is {@link GLib.Object} so Windows/Android can store their download handles later.
	 */
	private Gee.HashMap<string, GLib.Object> downloads_active {
		get;
		set;
		default = new Gee.HashMap<string, GLib.Object>();
	}

	public signal void uri_changed(string uri);

	private signal void load_settled();

	private Gtk.ScrolledWindow scrolled_window;
	private Gtk.Overlay freeze_overlay;
	private Gtk.Picture freeze_picture;
	private Gtk.DrawingArea freeze_scrim;
	private Gtk.Label freeze_status;

	private uint load_epoch = 0;
	private uint load_settle_id = 0;
	private bool load_ready_probed = false;
	private int64 load_committed_at = 0;
	private bool load_wait_active = false;
	private uint page_load_timeout_id = 0;
	private bool page_load_timed_out = false;
	private bool page_load_cancelled = false;
	private bool page_load_failed = false;
	private string page_load_fail_msg = "";
	private string await_navigation_before_uri = "";

	/**
	 * @param stack owning {@link BrowserStack} (shares site_cookies)
	 */
	public Browser(OLLMwebkit.BrowserStack stack)
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
		this.site_cookies = stack.site_cookies;
		this.a11y.host = this;
		this.web_view = new WebView() {
			hexpand = true,
			vexpand = true,
		};
		this.cloudflare = new OLLMwebkit.Cloudflare(this);
		this.cloudflare.notify["is-blocked"].connect(() => {
			if (!this.cloudflare.is_blocked || !this.load_wait_active) {
				return;
			}
			this.page_load_timed_out = false;
			this.load_completed();
		});
		this.web_view.load_changed.connect((ev) => {
			var uri = "";
			if (ev == LoadEvent.COMMITTED || ev == LoadEvent.FINISHED) {
				uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
				this.uri_changed(uri);
			}
			if (ev == LoadEvent.COMMITTED) {
				if (uri != "" && (this.load_wait_active || this.cloudflare.is_blocked)) {
					this.pending_load_uri = uri;
				}
			}
			if (ev == LoadEvent.COMMITTED && this.load_wait_active) {
				this.load_committed_at = GLib.get_monotonic_time();
				this.stop_settle();
				this.load_ready_probed = false;
				this.load_settle_id = GLib.Timeout.add(200, () => {
					return this.poll_settle();
				});
			}
			if (ev != LoadEvent.FINISHED) {
				return;
			}
			if (!this.load_wait_active) {
				return;
			}
			this.stop_settle();
			this.page_load_timed_out = false;
			this.load_completed();
		});
		this.web_view.load_failed.connect((load_event, failing_uri, error) => {
			if (!this.load_wait_active) {
				return false;
			}
			if (error is NetworkError.CANCELLED) {
				return false;
			}
			if (load_event != LoadEvent.STARTED && load_event != LoadEvent.COMMITTED) {
				return false;
			}
			if (this.pending_load_uri == "" || failing_uri == ""
					|| this.normalize_uri(failing_uri) != this.pending_load_uri) {
				return false;
			}
			this.page_load_failed = true;
			this.page_load_fail_msg = error.message;
			this.load_completed();
			return false;
		});

		this.scrolled_window = new Gtk.ScrolledWindow() {
			hexpand = true,
			vexpand = true,
			child = this.web_view,
		};
		this.scrolled_window.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

		this.freeze_picture = new Gtk.Picture() {
			hexpand = true,
			vexpand = true,
			content_fit = Gtk.ContentFit.FILL,
		};
		this.freeze_scrim = new Gtk.DrawingArea() {
			hexpand = true,
			vexpand = true,
		};
		this.freeze_scrim.set_draw_func((area, cr, width, height) => {
			cr.set_source_rgba(0.0, 0.0, 0.0, 0.4);
			cr.rectangle(0.0, 0.0, (double) width, (double) height);
			cr.fill();
		});
		this.freeze_status = new Gtk.Label("") {
			halign = Gtk.Align.CENTER,
			valign = Gtk.Align.CENTER,
			use_markup = true,
		};
		this.freeze_overlay = new Gtk.Overlay() {
			halign = Gtk.Align.START,
			valign = Gtk.Align.START,
			hexpand = false,
			vexpand = false,
			visible = false,
		};
		this.freeze_overlay.set_child(this.freeze_picture);
		this.freeze_overlay.add_overlay(this.freeze_scrim);
		this.freeze_overlay.add_overlay(this.freeze_status);

		var overlay = new Gtk.Overlay() {
			hexpand = true,
			vexpand = true,
		};
		overlay.set_child(this.scrolled_window);
		overlay.add_overlay(this.freeze_overlay);
		this.append(overlay);
		this.pending_load_uri = "";
#if LINUX
		this.web_view.decide_policy.connect((decision, type) => {
			if (type != PolicyDecisionType.RESPONSE) {
				return false;
			}
			var response_decision = decision as ResponsePolicyDecision;
			if (response_decision == null) {
				return false;
			}
			if (response_decision.is_mime_type_supported()) {
				return false;
			}
			response_decision.download();
			return true;
		});
		this.web_view.get_network_session().download_started.connect(this.on_download_started);
#endif
	}

	/**
	 * Load ''uri'' and block until the main document settles (Snappr load).
	 *
	 * Ends with an extra 2000 ms quiet delay for tool dump stability.
	 *
	 * @param uri page URL
	 * @param timeout_seconds max wait before timed out
	 * @throws GLib.Error on unreachable host, cancel, timeout, or load failure
	 */
	public async void load(string uri, uint timeout_seconds = 120) throws GLib.Error
	{
		var load_uri = this.normalize_uri(uri);
		GLib.Uri.parse(load_uri, GLib.UriFlags.NONE);
		yield this.apply_site_cookies(load_uri);
		if (this.load_wait_active
				&& load_uri != this.normalize_uri(this.pending_load_uri)) {
			throw new GLib.IOError.FAILED("Page load wait already in progress");
		}
		var showed_load_mask = false;
		if (!this.load_wait_active) {
			this.show_freeze("", "<b>Testing site…</b>");
			this.web_view.load_uri("about:blank");
			if (load_uri.has_prefix("http://") || load_uri.has_prefix("https://")) {
				var probe = new Soup.Session() {
					timeout = 10,
					user_agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
				};
				var head = new Soup.Message("HEAD", load_uri);
				try {
					yield probe.send_and_read_async(head, GLib.Priority.DEFAULT, null);
				} catch (GLib.Error e) {
					this.hide_freeze();
					throw new GLib.IOError.TIMED_OUT("Site did not respond");
				}
			} else {
			}
			this.show_freeze("", "<b>Loading…</b>");
			showed_load_mask = true;
		}
		ulong settled_id = 0;
		settled_id = this.load_settled.connect(() => {
			this.disconnect(settled_id);
			load.callback();
		});
		try {
			if (!this.load_wait_active) {
				this.begin_load(load_uri, timeout_seconds);
			}
			yield;
			if (showed_load_mask) {
				this.hide_freeze();
				showed_load_mask = false;
			}
			var loaded_uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
			if (this.page_load_cancelled) {
				this.page_load_cancelled = false;
				throw new GLib.IOError.CANCELLED("Load cancelled");
			}
			if (this.page_load_timed_out) {
				if (this.pending_load_uri == "" || loaded_uri == ""
						|| this.normalize_uri(loaded_uri) != this.pending_load_uri) {
					throw new GLib.IOError.TIMED_OUT("Page load timed out");
				}
				this.page_load_timed_out = false;
			}
			if (!this.cloudflare.is_blocked) {
				yield this.await_stable_uri();
			}
			if (this.page_load_failed) {
				this.page_load_failed = false;
				throw new GLib.IOError.FAILED("load failed: %s", this.page_load_fail_msg);
			}
		} finally {
			if (showed_load_mask) {
				this.hide_freeze();
			}
		}
		GLib.Timeout.add(2000, () => {
			GLib.Idle.add(this.load.callback);
			return GLib.Source.REMOVE;
		});
		yield;

		var final_uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : load_uri;
		try {
			var host = GLib.Uri.parse(final_uri, GLib.UriFlags.NONE).get_host();
			if (host != null && host.down().contains("google.")
					&& !load_uri.contains("setprefs")
					&& !load_uri.contains("hl=en")) {
				var md = yield this.a11y.dump(
					this.current_uri,
					this.web_view.get_title() != null ? this.web_view.get_title() : ""
				);
				var re = new GLib.Regex(
					"\\(\\^press:\\d+\\): \\[[^\\]]*\\]\\((https://[^)\\s]*setprefs[^)\\s]*hl=en[^)\\s]*)\\)"
				);
				GLib.MatchInfo mi;
				if (re.match(md, 0, out mi)) {
					yield this.load(mi.fetch(1));
				}
			}
		} catch (GLib.Error e) {
		}
		yield this.harvest_site_cookies(
			this.web_view.get_uri() != null ? this.web_view.get_uri() : load_uri
		);
	}

	private void begin_load(string load_uri, uint timeout_seconds)
	{
		this.load_epoch++;
		this.cloudflare.is_blocked = false;
		this.page_load_timed_out = false;
		this.page_load_cancelled = false;
		this.page_load_failed = false;
		this.page_load_fail_msg = "";
		this.load_committed_at = 0;
		this.load_ready_probed = false;
		this.load_wait_active = true;
		this.page_load_timeout_id = GLib.Timeout.add_seconds(timeout_seconds, () => {
			if (!this.load_wait_active) {
				return false;
			}
			this.page_load_timed_out = this.load_committed_at > 0 ? false : true;
			this.load_completed();
			return false;
		});
		this.pending_load_uri = load_uri;
		var current = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
		if (current.strip() == load_uri.strip() && !this.web_view.is_loading) {
			this.web_view.reload_bypass_cache();
			return;
		}
		this.web_view.load_uri(load_uri);
	}

	private bool poll_settle()
	{
		if (!this.load_wait_active) {
			this.load_settle_id = 0;
			return false;
		}
		if (this.cloudflare.is_blocked) {
			this.page_load_timed_out = false;
			this.load_completed();
			return false;
		}
		if (!this.web_view.is_loading) {
			this.page_load_timed_out = false;
			this.load_completed();
			return false;
		}
		if (this.web_view.estimated_load_progress >= 1.0) {
			this.page_load_timed_out = false;
			this.load_completed();
			return false;
		}
		if (!this.load_ready_probed && this.load_committed_at > 0
				&& GLib.get_monotonic_time() - this.load_committed_at > 1000000) {
			this.load_ready_probed = true;
			this.probe_ready.begin();
		}
		return true;
	}

	private async void probe_ready()
	{
		if (!this.load_wait_active) {
			return;
		}
		var uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
		if (this.pending_load_uri == "" || uri == "" || this.normalize_uri(uri) != this.pending_load_uri) {
			return;
		}
		var state = "";
		try {
			state = (yield this.web_view.evaluate_javascript(
				"document.readyState",
				-1,
				null,
				"probe_ready"
			)).to_string().strip();
		} catch (GLib.Error e) {
			return;
		}
		if (!this.load_wait_active) {
			return;
		}
		if (state.has_prefix("\"") && state.has_suffix("\"")) {
			state = state.substring(1, state.length - 2);
		}
		if (state != "interactive" && state != "complete") {
			return;
		}
		uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
		if (this.pending_load_uri == "" || this.normalize_uri(uri) != this.pending_load_uri) {
			return;
		}
		this.page_load_timed_out = false;
		this.load_completed();
	}

	private void stop_settle()
	{
		if (this.load_settle_id != 0) {
			GLib.Source.remove(this.load_settle_id);
			this.load_settle_id = 0;
		}
	}

	private string normalize_uri(string uri)
	{
		if (uri.contains(".blogspot.") && !uri.contains(".blogspot.com")) {
			try {
				uri = new GLib.Regex("\\.blogspot\\..*?/").replace(
					uri,
					uri.length,
					0,
					".blogspot.com/ncr/"
				);
			} catch (GLib.RegexError e) {
				GLib.warning("blogspot normalisation failed: %s", e.message);
			}
		}
		return uri;
	}

	/**
	 * Stop an in-flight page load and unblock {@link load} / {@link await_load}.
	 */
	public void cancel_load()
	{
		this.load_epoch++;
		this.web_view.stop_loading();
		if (!this.load_wait_active) {
			return;
		}
		this.page_load_cancelled = true;
		this.load_completed();
	}

	private void load_completed()
	{
		if (!this.load_wait_active) {
			return;
		}
		var uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
		if (this.await_navigation_before_uri != "" && !this.page_load_timed_out) {
			if (uri == this.await_navigation_before_uri) {
				return;
			}
		}
		this.await_navigation_before_uri = "";
		this.stop_settle();
		this.load_committed_at = 0;
		this.load_ready_probed = false;
		if (this.page_load_timeout_id != 0) {
			GLib.Source.remove(this.page_load_timeout_id);
			this.page_load_timeout_id = 0;
		}
		this.load_wait_active = false;
		GLib.Idle.add(() => {
			this.load_settled();
			return false;
		});
	}

	private async void await_stable_uri()
	{
		var last = "";
		var stable_count = 0;
		for (var tick = 0; tick < 30; tick++) {
			var uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
			var uri_changed = uri.strip() == "" || uri != last;
			stable_count = uri_changed ? 0 : stable_count + 1;
			last = uri_changed ? uri : last;
			if (stable_count >= 2) {
				return;
			}
			GLib.Timeout.add(200, () => {
				await_stable_uri.callback();
				return false;
			});
			yield;
		}
		var final_uri = this.web_view.get_uri() != null ? this.web_view.get_uri() : "";
		if (final_uri.strip() != "") {
		}
	}

	/**
	 * Block until the current WebView load finishes (Snappr await_load).
	 *
	 * @param timeout_seconds max wait
	 * @param before_uri when set, wait for navigation away from this URI
	 * @throws GLib.Error on cancel, timeout, or load failure
	 */
	public async void await_load(uint timeout_seconds = 120, string before_uri = "") throws GLib.Error
	{
		if (before_uri == "" && !this.web_view.is_loading) {
			if (this.page_load_failed) {
				this.page_load_failed = false;
				throw new GLib.IOError.FAILED("load failed: %s", this.page_load_fail_msg);
			}
			return;
		}
		if (before_uri != "" && (this.web_view.get_uri() != null ? this.web_view.get_uri() : "") != before_uri) {
			yield this.await_stable_uri();
			if (this.page_load_failed) {
				this.page_load_failed = false;
				throw new GLib.IOError.FAILED("load failed: %s", this.page_load_fail_msg);
			}
			return;
		}
		this.await_navigation_before_uri = before_uri;
		if (this.load_wait_active) {
			throw new GLib.IOError.FAILED("Page load wait already in progress");
		}
		this.page_load_timed_out = false;
		this.page_load_cancelled = false;
		this.load_wait_active = true;
		this.page_load_timeout_id = GLib.Timeout.add_seconds(timeout_seconds, () => {
			if (!this.load_wait_active) {
				return false;
			}
			this.page_load_timed_out = true;
			this.load_completed();
			return false;
		});
		ulong settled_id = 0;
		settled_id = this.load_settled.connect(() => {
			this.disconnect(settled_id);
			await_load.callback();
		});
		yield;
		if (this.page_load_cancelled) {
			this.page_load_cancelled = false;
			throw new GLib.IOError.CANCELLED("Load cancelled");
		}
		if (this.page_load_timed_out) {
			throw new GLib.IOError.TIMED_OUT("Page load timed out");
		}
		if (this.page_load_failed) {
			this.page_load_failed = false;
			throw new GLib.IOError.FAILED("load failed: %s", this.page_load_fail_msg);
		}
	}

	private void show_freeze(string image_path, string status_markup)
	{
		this.freeze_status.label = status_markup;
		if (image_path != "") {
			this.freeze_picture.set_filename(image_path);
		} else {
			this.freeze_picture.set_filename(null);
		}
		Gdk.Rectangle web_alloc;
		Gdk.Rectangle scrolled_alloc;
		this.web_view.get_allocation(out web_alloc);
		this.scrolled_window.get_allocation(out scrolled_alloc);
		if (web_alloc.width <= 1 || web_alloc.height <= 1) {
			web_alloc = scrolled_alloc;
		}
		this.freeze_overlay.margin_end =
			scrolled_alloc.width - web_alloc.x - web_alloc.width;
		this.freeze_overlay.margin_bottom =
			scrolled_alloc.height - web_alloc.y - web_alloc.height;
		this.freeze_overlay.set_size_request(web_alloc.width, web_alloc.height);
		this.freeze_overlay.visible = true;
#if WINDOWS
		// Opacity 0 parks WebView2 off-screen (HWND above GTK overlays otherwise).
		this.web_view.set_opacity(0.0);
#endif
	}

	private void hide_freeze()
	{
		this.freeze_overlay.visible = false;
		this.freeze_overlay.margin_end = 0;
		this.freeze_overlay.margin_bottom = 0;
		this.freeze_overlay.set_size_request(-1, -1);
		this.freeze_picture.set_filename(null);
#if WINDOWS
		this.web_view.set_opacity(1.0);
#endif
	}

	/**
	 * Inject host cookies harvested earlier this session (Snappr apply_site_cookies).
	 *
	 * @param url page URL whose host selects the jar entry
	 */
	public async void apply_site_cookies(string url)
	{
		GLib.Uri parsed;
		try {
			parsed = GLib.Uri.parse(url.strip(), GLib.UriFlags.NONE);
		} catch (GLib.Error e) {
			return;
		}
		var host = parsed.get_host();
		if (host == null || host.strip() == "") {
			return;
		}
		if (!this.site_cookies.has_key(host.down())) {
			return;
		}
		var manager = this.web_view.get_network_session().get_cookie_manager();
		foreach (var part in this.site_cookies.get(host.down()).split(";")) {
			var piece = part.strip();
			if (piece == "") {
				continue;
			}
			var cookie = Soup.Cookie.parse("Set-Cookie: %s".printf(piece), parsed);
			if (cookie == null) {
				continue;
			}
			try {
				yield manager.add_cookie(cookie, null);
			} catch (GLib.Error e) {
			}
		}
	}

	/**
	 * Store Cookie header for ''uri'''s host (Snappr harvest_site_cookies).
	 *
	 * @param uri page URI to read cookies for
	 */
	public async void harvest_site_cookies(string uri)
	{
		try {
			var cookie_list = yield this.web_view
				.get_network_session()
				.get_cookie_manager()
				.get_cookies(uri, null);
			var cookie_header = "";
			foreach (var cookie in cookie_list) {
				if (cookie_header != "") {
					cookie_header += "; ";
				}
				cookie_header += cookie.get_name() + "=" + cookie.get_value();
			}
			if (cookie_header == "") {
				return;
			}
			var parsed = GLib.Uri.parse(uri, GLib.UriFlags.NONE);
			var host = parsed.get_host();
			if (host != null && host.strip() != "") {
				this.site_cookies.set(host.down(), cookie_header);
			}
		} catch (GLib.Error e) {
		}
	}

	/**
	 * Return page content for ''format'' (a11y via {@link A11y}).
	 *
	 * @param format output format string
	 * @return page dump text
	 * @throws GLib.Error when not implemented or format is unsupported
	 */
	public async string dump(string format) throws GLib.Error
	{
		switch (format) {
			case "a11y":
				return yield this.a11y.dump(this.current_uri, this.web_view.get_title() != null
					? this.web_view.get_title() : "");

			case "html":
			case "markdown":
				throw new GLib.IOError.NOT_SUPPORTED(
					"dump/%s deferred (Phase 2.1 — a11y first)", format);

			default:
				throw new GLib.IOError.INVALID_ARGUMENT("Unsupported format: %s", format);
		}
	}

	/**
	 * Apply fill map via {@link A11y}.
	 *
	 * @param fields press-ref id → text
	 * @throws GLib.Error when fill fails
	 */
	public async void fill(Gee.HashMap<string, string> fields) throws GLib.Error
	{
		yield this.a11y.fill(fields);
	}

	/**
	 * Activate press-ref via {@link A11y}.
	 *
	 * @param id press id from the last a11y dump
	 * @throws GLib.Error when press fails
	 */
	public async void press(int id) throws GLib.Error
	{
		yield this.a11y.press(id);
	}

	/**
	 * NetworkSession download-started: dedupe, wire destination/progress/finish.
	 *
	 * @param download WebKit download
	 */
#if LINUX
	private void on_download_started(Download download)
	{
		var web_req = download.get_request();
		var url = web_req != null ? web_req.uri : "";
		if (url == "") {
			download.cancel();
			return;
		}
		if (this.downloads_inflight.has_key(url)
				&& this.downloads_inflight.get(url) != "") {
			download.cancel();
			return;
		}
		download.decide_destination.connect((suggested) => {
			return this.on_decide_destination(download, suggested);
		});
		download.received_data.connect((len) => {
			if (this.agent == null || !this.downloads_inflight.has_key(url)) {
				return;
			}
			var path = this.downloads_inflight.get(url);
			if (path == "") {
				return;
			}
			this.agent.notification(new OLLMrpc.Notification() {
				method = "event.browser.download.progress",
				message = path,
				progress_completed = (int64) download.get_received_data_length(),
				progress_total = 0,
				action = "cancel",
				action_label = "Cancel",
			});
		});
		// connect_after so Browser.download()'s finished/failed handlers can read
		// downloads_inflight before this cleanup unsets the key.
		download.failed.connect_after((err) => {
			var dest = "";
			if (this.downloads_inflight.has_key(url)) {
				dest = this.downloads_inflight.get(url);
				this.downloads_inflight.unset(url);
			}
			this.downloads_active.unset(url);
			if (dest == "") {
				return;
			}
			var msg = dest + " error: " + err.message;
			if (this.agent != null) {
				this.agent.notification(new OLLMrpc.Notification() {
					method = "event.browser.download.end",
					message = msg,
				});
			}
			var app = GLib.Application.get_default();
			if (app == null) {
				return;
			}
			var note = new GLib.Notification("Download failed");
			note.set_body(msg);
			app.send_notification(
				"ollmchat-browser-download-%u".printf((uint) GLib.get_real_time()),
				note);
		});
		download.finished.connect_after(() => {
			var dest = "";
			if (this.downloads_inflight.has_key(url)) {
				dest = this.downloads_inflight.get(url);
				this.downloads_inflight.unset(url);
			}
			this.downloads_active.unset(url);
			if (dest == "") {
				return;
			}
			if (this.agent != null) {
				this.agent.notification(new OLLMrpc.Notification() {
					method = "event.browser.download.end",
					message = dest,
				});
			}
			var app = GLib.Application.get_default();
			if (app == null) {
				return;
			}
			var note = new GLib.Notification("Download complete");
			note.set_body(dest);
			app.send_notification(
				"ollmchat-browser-download-%u".printf((uint) GLib.get_real_time()),
				note);
		});
	}

	/**
	 * Download decide-destination: permission, place under Downloads, start event.
	 *
	 * @param download WebKit download
	 * @param suggested WebKit suggested filename (may be null/empty)
	 * @return true (handler owns destination / cancel)
	 */
	private bool on_decide_destination(Download download, string? suggested)
	{
		var web_req = download.get_request();
		var url = web_req != null ? web_req.uri : "";
		var name = suggested != null && suggested != "" ? suggested : "download";
		var dir = GLib.Environment.get_user_special_dir(GLib.UserDirectory.DOWNLOAD);
		if (dir == null || dir == "") {
			dir = GLib.Environment.get_home_dir();
		}
		var dest = GLib.Path.build_filename(dir, name);
		if (this.agent == null || this.tool == null || url == "") {
			download.cancel();
			return true;
		}
		var req = new OLLMwebkit.Request() {
			action = "download",
			url = url,
			download_display_name = GLib.Path.get_basename(dest),
			agent = this.agent,
			tool = this.tool,
		};
		if (!req.build_perm_question()) {
			download.cancel();
			return true;
		}
		this.agent.get_permission_provider().request.begin(req, (obj, res) => {
			var allowed = false;
			try {
				allowed = this.agent.get_permission_provider().request.end(res);
			} catch (GLib.Error e) {
				allowed = false;
			}
			if (!allowed) {
				download.cancel();
				return;
			}
			this.downloads_inflight.set(url, dest);
			this.downloads_active.set(url, download);
			download.set_allow_overwrite(true);
			download.set_destination(dest);
			this.agent.notification(new OLLMrpc.Notification() {
				method = "event.browser.download.start",
				message = dest,
				action = "cancel",
				action_label = "Cancel",
			});
		});
		return true;
	}
#endif

	/**
	 * Download ''url'' via WebKit into the platform Downloads folder.
	 *
	 * @param url absolute http(s) URL
	 * @return destination path, or status if already in flight
	 * @throws GLib.Error when permission denied or WebKit fails
	 */
	public async string download(string url) throws GLib.Error
	{
		var trimmed = url.strip();
		if (trimmed == "") {
			throw new GLib.IOError.INVALID_ARGUMENT("url is required for download");
		}
		if (this.downloads_inflight.has_key(trimmed)
				&& this.downloads_inflight.get(trimmed) != "") {
			return "Already downloading: " + this.downloads_inflight.get(trimmed);
		}
#if LINUX
		this.downloads_inflight.set(trimmed, "");
		var dl = this.web_view.download_uri(trimmed);
		var result_path = "";
		var result_err = "";
		SourceFunc resume = download.callback;
		ulong fin_id = 0;
		ulong fail_id = 0;
		fin_id = dl.finished.connect(() => {
			if (this.downloads_inflight.has_key(trimmed)) {
				result_path = this.downloads_inflight.get(trimmed);
			}
			dl.disconnect(fin_id);
			dl.disconnect(fail_id);
			resume();
		});
		fail_id = dl.failed.connect((err) => {
			result_err = err.message;
			dl.disconnect(fin_id);
			dl.disconnect(fail_id);
			resume();
		});
		yield;
		if (result_err != "") {
			this.downloads_inflight.unset(trimmed);
			throw new GLib.IOError.FAILED("%s", result_err);
		}
		if (result_path == "") {
			this.downloads_inflight.unset(trimmed);
			throw new GLib.IOError.FAILED("Download finished without destination");
		}
		return result_path;
#else
		throw new GLib.IOError.NOT_SUPPORTED("download is Linux WebKitGTK in this plan");
#endif
	}

	/**
	 * Banner Cancel for an in-flight download (''action'' ''cancel'').
	 *
	 * @param notif ''event.browser.download.*'' with ''message'' = destination path
	 */
	public void notification_reply(OLLMrpc.Notification notif)
	{
#if LINUX
		if (!notif.method.has_prefix("event.browser.download.")) {
			return;
		}
		if (notif.action != "cancel") {
			return;
		}
		foreach (var url in this.downloads_inflight.keys) {
			if (this.downloads_inflight.get(url) != notif.message) {
				continue;
			}
			if (!this.downloads_active.has_key(url)) {
				return;
			}
			var active = this.downloads_active.get(url) as Download;
			if (active == null) {
				return;
			}
			active.cancel();
			return;
		}
#endif
	}
}
