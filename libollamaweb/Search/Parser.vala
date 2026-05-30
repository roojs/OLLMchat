/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OllamaWeb.Search
{
	/**
	 * Parses Ollama.com search and tags HTML into {@link OllamaWeb.Model} records.
	 */
	public class Parser : Object
	{
		private static string[] excluded_path_segments = {
			"signin", "download", "docs", "cloud", "models", "search", "public", "library", "tags"
		};

		/**
		 * Parse a search results HTML page into catalog models (shallow rows).
		 *
		 * @param html full page HTML
		 * @return models deduplicated by slug
		 */
		public Gee.ArrayList<OllamaWeb.Model> parse_search(string html) throws OllamaWeb.Search.Error.PARSE
		{
			var by_slug = new Gee.HashMap<string, OllamaWeb.Model>();
			unowned Xml.Doc doc = this.load_doc(html);
			var ctxt = new Xml.XPath.Context(doc);
			unowned Xml.XPath.NodeSet? nodes = this.eval_nodes(
				ctxt,
				"//*[@id='searchresults']//li[@x-test-model] | //ul[@role='list']/li[@x-test-model]"
			);
			if (nodes == null) {
				return new Gee.ArrayList<OllamaWeb.Model>();
			}
			for (int i = 0; i < nodes.length(); i++) {
				var li = nodes.item(i);
				var model = this.parse_row(li);
				if (model == null) {
					continue;
				}
				this.merge(by_slug, model);
			}
			var results = new Gee.ArrayList<OllamaWeb.Model>();
			foreach (var entry in by_slug) {
				results.add(entry.value);
			}
			return results;
		}

		/**
		 * Fill tags, features, and downloads on {@link model} from a tags page.
		 *
		 * @param model model to enrich (slug should already be set)
		 * @param html tags page HTML
		 */
		public void apply_tags(OllamaWeb.Model model, string html) throws OllamaWeb.Search.Error.PARSE
		{
			model.tags.clear();
			model.features.clear();
			model.downloads = 0;
			unowned Xml.Doc doc = this.load_doc(html);
			var ctxt = new Xml.XPath.Context(doc);
			this.page_features(ctxt, model);
			this.page_downloads(ctxt, model);
			unowned Xml.XPath.NodeSet? rows = this.eval_nodes(
				ctxt,
				"//div[contains(@class,'min-w-full') and contains(@class,'divide-y')]"
				+ "//div[contains(@class,'group') and contains(@class,'px-4')]"
			);
			if (rows == null) {
				return;
			}
			var seen_tags = new Gee.HashSet<string>();
			for (int i = 0; i < rows.length(); i++) {
				var row = rows.item(i);
				var variant = this.parse_tag(row);
				if (variant == null || seen_tags.contains(variant.name)) {
					continue;
				}
				seen_tags.add(variant.name);
				model.tags.add(variant);
			}
			model.refined = true;
			model.rebuild_unique_sizes();
		}

		private unowned Xml.Doc load_doc(string html) throws OllamaWeb.Search.Error.PARSE
		{
			int options = Html.ParserOption.RECOVER | Html.ParserOption.NOWARNING;
			unowned Html.Doc? doc = Html.Doc.read_memory(
				html.to_utf8(),
				html.length,
				"",
				null,
				options
			);
			if (doc == null) {
				throw new Error.PARSE("failed to parse HTML");
			}
			return doc;
		}

		private unowned Xml.XPath.NodeSet? eval_nodes(Xml.XPath.Context ctxt, string expr)
		{
			unowned Xml.XPath.Object? raw = ctxt.eval_expression(expr);
			if (raw == null) {
				return null;
			}
			if (raw.type != Xml.XPath.ObjectType.NODESET || raw.nodesetval == null) {
				return null;
			}
			return raw.nodesetval;
		}

		private string node_content(Xml.Node* node)
		{
			return ((Xml.Node) node).get_content().strip();
		}

		private string node_prop(Xml.Node* node, string name)
		{
			return ((Xml.Node) node).get_prop(name);
		}

		private unowned Xml.XPath.NodeSet? eval_on(Xml.Node* context, string expr)
		{
			var ctxt = new Xml.XPath.Context(((Xml.Node) context).doc);
			ctxt.node = context;
			return this.eval_nodes(ctxt, expr);
		}

		private OllamaWeb.Model? parse_row(Xml.Node* li)
		{
			unowned Xml.XPath.NodeSet? anchors = this.eval_on(
				li,
				".//a[starts-with(@href,'/library/')]"
				+ " | .//a[contains(@href,'/') and not(starts-with(@href,'/library/'))"
				+ " and not(contains(@href,'/public/')) and not(contains(@href,'/tags'))]"
			);
			Xml.Node* anchor = anchors != null && anchors.length() > 0
				? anchors.item(0)
				: this.find_elt(li, "a");
			if (anchor == null) {
				return null;
			}
			var href = this.node_prop(anchor, "href");
			var slug = this.slug_href(href);
			if (slug == null) {
				return null;
			}
			var model = new OllamaWeb.Model();
			model.slug = slug;
			model.name = this.text(anchor, ".//*[@x-test-search-response-title]");
			if (model.name == "") {
				model.name = this.text(anchor, ".//h2//span");
			}
			if (model.name == "") {
				model.name = slug;
			}
			model.description = this.text(anchor, ".//p[contains(@class,'text-neutral-800')]");
			var pulls_text = this.text(anchor, ".//*[@x-test-pull-count]");
			model.pulls = this.parse_count(pulls_text);
			this.row_features(anchor, model);
			return model;
		}

		private void row_features(Xml.Node* anchor, OllamaWeb.Model model)
		{
			unowned Xml.XPath.NodeSet? caps = this.eval_on(anchor, ".//*[@x-test-capability]");
			if (caps == null) {
				return;
			}
			for (int i = 0; i < caps.length(); i++) {
				var text = this.node_content(caps.item(i));
				if (!model.features.contains(text)) {
					model.features.add(text);
				}
			}
		}

		private void page_features(Xml.XPath.Context ctxt, OllamaWeb.Model model)
		{
			unowned Xml.XPath.NodeSet? caps = this.eval_nodes(
				ctxt,
				"//div[contains(@class,'flex-wrap') and contains(@class,'space-x-2')]"
				+ "//span[contains(@class,'bg-indigo-50')]"
			);
			if (caps == null) {
				return;
			}
			for (int i = 0; i < caps.length(); i++) {
				var text = this.node_content(caps.item(i));
				if (!model.features.contains(text)) {
					model.features.add(text);
				}
			}
		}

		private void page_downloads(Xml.XPath.Context ctxt, OllamaWeb.Model model)
		{
			unowned Xml.XPath.NodeSet? nodes = this.eval_nodes(ctxt, "//*[@x-test-pull-count]");
			if (nodes == null) {
				return;
			}
			var text = this.node_content(nodes.item(0));
			model.downloads = this.parse_count(text);
		}

		private OllamaWeb.ModelVariant? parse_tag(Xml.Node* row)
		{
			unowned Xml.XPath.NodeSet? links = this.eval_on(
				row,
				".//a[contains(@href,'/library/')]"
				+ " | .//a[contains(@href,':') and not(starts-with(@href,'http'))]"
			);
			if (links == null || links.length() == 0) {
				return null;
			}
			var href = this.node_prop(links.item(0), "href");
			var tag_name = this.tag_href(href);
			if (tag_name == null) {
				return null;
			}
			var variant = new OllamaWeb.ModelVariant();
			variant.name = tag_name;
			unowned Xml.XPath.NodeSet? cells = this.eval_on(
				row,
				".//p[contains(@class,'col-span-2') and contains(@class,'text-neutral-500')]"
				+ " | .//div[contains(@class,'col-span-2') and contains(@class,'text-neutral-500')]"
			);
			if (cells == null || cells.length() < 3) {
				return null;
			}
			variant.size = this.node_content(cells.item(0));
			variant.context = this.node_content(cells.item(1));
			variant.input = this.node_content(cells.item(2));
			return variant;
		}

		private void merge(Gee.HashMap<string, OllamaWeb.Model> by_slug, OllamaWeb.Model model)
		{
			if (!by_slug.has_key(model.slug)) {
				by_slug.set(model.slug, model);
				return;
			}
			var existing = by_slug.get(model.slug);
			if (model.pulls > existing.pulls) {
				existing.pulls = model.pulls;
			}
			if (existing.description == "" && model.description != "") {
				existing.description = model.description;
			}
		}

		private string? slug_href(string href_in)
		{
			var href = href_in;
			int q = href.index_of_char('?');
			if (q >= 0) {
				href = href.substring(0, q);
			}
			int h = href.index_of_char('#');
			if (h >= 0) {
				href = href.substring(0, h);
			}
			if (href.has_suffix("/tags")) {
				href = href.substring(0, href.length - 5);
			}
			if (href.has_prefix("/library/")) {
				return href.substring(9);
			}
			if (!href.has_prefix("/")) {
				return null;
			}
			var parts = href.split("/");
			if (parts.length != 3 || parts[1] == "" || parts[2] == "") {
				return null;
			}
			if (this.excluded(parts[1]) || this.excluded(parts[2])) {
				return null;
			}
			return parts[1] + "/" + parts[2];
		}

		private string? tag_href(string href)
		{
			int colon = href.last_index_of_char(':');
			if (colon < 0 || colon >= href.length - 1) {
				return null;
			}
			return href.substring(colon + 1);
		}

		private bool excluded(string segment)
		{
			foreach (var excluded in excluded_path_segments) {
				if (segment == excluded) {
					return true;
				}
			}
			return false;
		}

		private int64 parse_count(string text)
		{
			if (text == "") {
				return 0;
			}
			var clean = text.replace(",", "").strip().up();
			double number = 0;
			var suffix = "";
			int i = 0;
			while (i < clean.length) {
				unichar c = clean.get_char(i);
				if ((c >= '0' && c <= '9') || c == '.') {
					i++;
					continue;
				}
				break;
			}
			if (i == 0) {
				return 0;
			}
			number = double.parse(clean.substring(0, i));
			if (i < clean.length) {
				suffix = clean.substring(i).strip();
			}
			if (suffix == "K") {
				number *= 1000;
			} else if (suffix == "M") {
				number *= 1000000;
			} else if (suffix == "G") {
				number *= 1000000000;
			} else if (suffix == "T") {
				number *= 1000000000000;
			}
			return (int64) number;
		}

		private string text(Xml.Node* context, string expr)
		{
			unowned Xml.XPath.NodeSet? nodes = this.eval_on(context, expr);
			if (nodes == null || nodes.length() == 0) {
				return "";
			}
			return this.node_content(nodes.item(0));
		}

		private Xml.Node* find_elt(Xml.Node* parent, string name)
		{
			for (unowned Xml.Node? child = ((Xml.Node) parent).children; child != null; child = child.next) {
				if (child.type != Xml.ElementType.ELEMENT_NODE) {
					continue;
				}
				if (child.name == name) {
					return (Xml.Node*) child;
				}
				var found = this.find_elt((Xml.Node*) child, name);
				if (found != null) {
					return found;
				}
			}
			return null;
		}
	}
}
