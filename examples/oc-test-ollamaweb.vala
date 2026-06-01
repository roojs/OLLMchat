/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Test / debug tool for libollamaweb HTML parsing (offline fixtures).
 *
 * Usage:
 *   oc-test-ollamaweb <file.html>              — parse search page
 *   oc-test-ollamaweb --tags <file.html>       — parse tags page (slug from filename hint)
 *   oc-test-ollamaweb --merge <a.html> <b.html> — merge two search pages (double-search)
 *   oc-test-ollamaweb --write-golden <dir>     — regenerate *.expected.json in dir
 */

int main(string[] args)
{
	var pos_args = new Gee.ArrayList<string>();
	bool tags_mode = false;
	bool merge_mode = false;
	bool write_golden = false;
	for (int i = 1; i < args.length; i++) {
		if (args[i] == "--tags") {
			tags_mode = true;
			continue;
		}
		if (args[i] == "--merge") {
			merge_mode = true;
			continue;
		}
		if (args[i] == "--write-golden") {
			write_golden = true;
			continue;
		}
		pos_args.add(args[i]);
	}
	if (pos_args.size == 0) {
		GLib.stderr.printf(
			"usage: oc-test-ollamaweb [--tags] [--merge] [--write-golden] <file.html> ...\n"
		);
		return 1;
	}
	if (merge_mode && pos_args.size != 2) {
		GLib.stderr.printf("--merge requires exactly two HTML files (popular, newest)\n");
		return 1;
	}
	var parser = new OllamaWeb.Search.Parser();
	int failures = 0;
	if (merge_mode) {
		string popular_html;
		string newest_html;
		try {
			GLib.FileUtils.get_contents(pos_args[0], out popular_html);
			GLib.FileUtils.get_contents(pos_args[1], out newest_html);
		} catch (GLib.Error e) {
			GLib.stderr.printf("failed to read fixtures: %s\n", e.message);
			return 1;
		}
		Gee.ArrayList<OllamaWeb.Model> popular_rows;
		Gee.ArrayList<OllamaWeb.Model> newest_rows;
		try {
			popular_rows = parser.parse_search(popular_html);
			newest_rows = parser.parse_search(newest_html);
		} catch (OllamaWeb.Search.Error e) {
			GLib.stderr.printf("parse failed: %s\n", e.message);
			return 1;
		}
		var merged = OllamaWeb.Search.Service.merge_double_search(popular_rows, newest_rows);
		string json = OllamaWeb.Model.json_array(merged);
		if (write_golden) {
			write_expected(pos_args[0], json, "search-double-merge");
		} else {
			GLib.stdout.printf("%s", json);
		}
		return 0;
	}
	foreach (var path in pos_args) {
		string html;
		try {
			GLib.FileUtils.get_contents(path, out html);
		} catch (GLib.Error e) {
			GLib.stderr.printf("failed to read %s: %s\n", path, e.message);
			failures++;
			continue;
		}
		bool file_tags = tags_mode || path.contains("tags-");
		if (file_tags) {
			var model = new OllamaWeb.Model();
			model.slug = slug_hint_from_fixture(path);
			try {
				parser.apply_tags(model, html);
			} catch (OllamaWeb.Search.Error e) {
				GLib.stderr.printf("parse failed %s: %s\n", path, e.message);
				failures++;
				continue;
			}
			var list = new Gee.ArrayList<OllamaWeb.Model>();
			list.add(model);
			string json = OllamaWeb.Model.json_array(list);
			if (write_golden) {
				write_expected(path, json);
			} else {
				GLib.stdout.printf("%s", json);
			}
			continue;
		}
		Gee.ArrayList<OllamaWeb.Model> models;
		try {
			models = parser.parse_search(html);
		} catch (OllamaWeb.Search.Error e) {
			GLib.stderr.printf("parse failed %s: %s\n", path, e.message);
			failures++;
			continue;
		}
		string json = OllamaWeb.Model.json_array(models);
		if (write_golden) {
			write_expected(path, json);
		} else {
			GLib.stdout.printf("%s", json);
		}
	}
	return failures > 0 ? 1 : 0;
}

string slug_hint_from_fixture(string path)
{
	var basename = GLib.Path.get_basename(path);
	if (basename.has_prefix("tags-library-")) {
		return basename.substring(13, basename.length - 18);
	}
	if (basename.has_prefix("tags-derivative-")) {
		return "andrewmccall/gemma3-tools";
	}
	return "unknown";
}

void write_expected(string html_path, string json, string? basename = null)
{
	var expected = html_path;
	if (basename != null) {
		var dir = GLib.Path.get_dirname(html_path);
		expected = GLib.Path.build_filename(dir, basename + ".expected.json");
	} else if (expected.has_suffix(".html")) {
		expected = expected.substring(0, expected.length - 5) + ".expected.json";
	} else {
		expected = expected + ".expected.json";
	}
	try {
		GLib.FileUtils.set_contents(expected, json);
		GLib.stderr.printf("wrote %s\n", expected);
	} catch (GLib.Error e) {
		GLib.stderr.printf("failed to write %s: %s\n", expected, e.message);
	}
}
