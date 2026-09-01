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
using AndroidAtspi;
#elif WINDOWS
using Win32Atspi;
#else
using Atspi;
#endif

/**
 * Accessibility dump for {@link Browser}.
 *
 * Platform tree via ''using'' ({@link Atspi} / {@link Win32Atspi} /
 * {@link AndroidAtspi}) — same shape as {@link A11yParse}. Dump stays
 * a11y. Linux offsloads AT-SPI dump to a GLib worker (main-thread AT-SPI
 * deadlocks; set ''GTK_A11Y=atspi'' before GTK init). Windows dump stays
 * on the UI thread (COM). Android yields {@link AndroidAtspi.refresh_async}
 * first so the host walk runs on the Android UI thread without GTK
 * sync-waiting (IME ''blockForMain'' ANR — webkitgtk-android
 * ''2026-07-23-a11y-walk-gtk-thread-anr''). Fill and press go through
 * {@link WebDriver} on every platform. No page JavaScript.
 *
 * == Example ==
 *
 * {{{
 * var a11y = new OLLMwebkit.A11y();
 * var md = yield a11y.dump(uri, title);
 * }}}
 */
public class OLLMwebkit.A11y : GLib.Object
{
	/**
	 * Press-ref id → child-index route from the AT-SPI application root.
	 */
	public Gee.HashMap<int, Gee.ArrayList<int>> press_routes {
		get; private set; default = new Gee.HashMap<int, Gee.ArrayList<int>>();
	}

	/**
	 * Press-ref id → a11y label from the last dump (permission questions).
	 */
	public Gee.HashMap<int, string> press_labels {
		get; private set; default = new Gee.HashMap<int, string>();
	}

	/**
	 * HTML form ''name='' (or ''id='' when name is missing) → child-index path
	 * from the application root (from the last dump; same path shape as
	 * {@link press_routes} values).
	 */
	public Gee.HashMap<string, Gee.ArrayList<int>> html_names {
		get; private set; default = new Gee.HashMap<string, Gee.ArrayList<int>>();
	}

	/**
	 * Nodes from the last {@link dump} (fill_key / press_id + WINDOW coords).
	 */
	public Gee.ArrayList<A11yNode> nodes { get; private set; default = new Gee.ArrayList<A11yNode>(); }

	/**
	 * Host widget whose toplevel is presented before keyboard fill.
	 */
	public Gtk.Widget host { get; set; }

	static bool atspi_ready = false;

	/**
	 * Project the page accessibility tree to a11y markdown.
	 *
	 * @param url current page URL
	 * @param title document title hint (may be empty)
	 * @return Content + References markdown
	 * @throws GLib.Error when the a11y tree cannot be read
	 */
	public async string dump(string url, string title) throws GLib.Error
	{
#if ANDROID
		yield refresh_async();
		return this.dump_sync(url, title);
#elif WINDOWS
		return this.dump_sync(url, title);
#else
		GLib.SourceFunc callback = dump.callback;
		GLib.Error? thread_error = null;
		var result = "";
		new GLib.Thread<bool>("ocwebkit-a11y-dump", () => {
			try {
				result = this.dump_sync(url, title);
			} catch (GLib.Error e) {
				thread_error = e;
			}
			Idle.add((owned) callback);
			return true;
		});
		yield;
		if (thread_error != null) {
			throw thread_error;
		}
		return result;
#endif
	}

	/**
	 * Worker / UI-thread body for {@link dump}.
	 *
	 * @param url current page URL
	 * @param title document title hint
	 * @return a11y markdown
	 * @throws GLib.Error when the tree cannot be read
	 */
	private string dump_sync(string url, string title) throws GLib.Error
	{
		if (!A11y.atspi_ready) {
			init();
			A11y.atspi_ready = true;
		}

		Accessible? app = null;
		var desktop = get_desktop(0);
		for (var i = 0; i < desktop.get_child_count(); i++) {
			var candidate = desktop.get_child_at_index(i);
			if (candidate.get_process_id() != (uint) Posix.getpid()) {
				continue;
			}
			app = candidate;
			break;
		}
		if (app == null) {
			throw new GLib.IOError.FAILED("a11y: no application for pid %u", (uint) Posix.getpid());
		}

		var walk_root = app;
		var walk_route = new Gee.ArrayList<int>();
		var find_acc = new Gee.ArrayList<Accessible>();
		var find_route = new Gee.ArrayList<Gee.ArrayList<int>>();
		find_acc.add(app);
		find_route.add(walk_route);
		while (find_acc.size > 0) {
			var cur = find_acc.remove_at(find_acc.size - 1);
			var cur_route = find_route.remove_at(find_route.size - 1);
			var role_name = cur.get_role_name();
			if (role_name == "document text" || role_name == "document frame") {
				walk_root = cur;
				walk_route = cur_route;
				break;
			}
			var child_count = cur.get_child_count();
			if (child_count <= 0) {
				continue;
			}
			for (var j = 0; j < child_count; j++) {
				find_acc.add(cur.get_child_at_index(j));
				var next_route = new Gee.ArrayList<int>();
				foreach (var part in cur_route) {
					next_route.add(part);
				}
				next_route.add(j);
				find_route.add(next_route);
			}
		}

		var parse = new A11yParse(walk_root, walk_route);
		parse.walk();
		this.press_routes = parse.press_routes;
		this.press_labels = parse.press_labels;
		this.html_names = parse.html_names;
		this.nodes = parse.nodes;

		if (title == "") {
			title = walk_root.get_name() != null ? walk_root.get_name() : "";
		}
		return "# Page\n- URL: " + url + "\n- Title: " + title
			+ "\n\n## Content\n" + parse.content
			+ "\n## References\n" + parse.refs;
	}
}
