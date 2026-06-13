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
	 * High-level search and model detail fetch against ollama.com.
	 */
	public class Service : Object
	{
		public bool searching { get; set; default = false; }
		public bool fetching_detail { get; private set; default = false; }

		public bool busy {
			get {
				return this.searching || this.fetching_detail;
			}
		}

		private Client client { get; set; default = new Client(); }
		private Parser parser { get; set; default = new Parser(); }

		/**
		 * Run a catalog search: popular + newest pages merged by slug.
		 *
		 * When {@link page} is set, fetch and parse that page only and do not
		 * update {@link searching} (caller owns the busy span).
		 */
		public async Gee.ArrayList<OllamaWeb.Model> search(
			string query,
			Category category,
			GLib.Cancellable? cancellable = null,
			Sort? page = null
		) throws OllamaWeb.Search.Error, GLib.IOError, GLib.Error {
			if (query.strip() == "") {
				return new Gee.ArrayList<OllamaWeb.Model>();
			}
			if (page != null) {
				return this.parser.parse_search(
					yield this.client.fetch_path(
						this.search_path(query, category, page),
						cancellable
					)
				);
			}
			this.searching = true;
			this.notify_property("searching");
			this.notify_property("busy");
			try {
				var popular_rows = yield this.search(
					query,
					category,
					cancellable,
					Sort.POPULAR
				);
				var newest_rows = yield this.search(
					query,
					category,
					cancellable,
					Sort.NEWEST
				);
				return Service.merge_double_search(popular_rows, newest_rows);
			} finally {
				this.searching = false;
				this.notify_property("searching");
				this.notify_property("busy");
			}
		}

		/**
		 * Fetch and parse the tags page for {@link model.slug}.
		 */
		public async void fetch_tags(
			OllamaWeb.Model model,
			GLib.Cancellable? cancellable = null
		) throws OllamaWeb.Search.Error, GLib.IOError, GLib.Error {
			this.fetching_detail = true;
			this.notify_property("fetching_detail");
			this.notify_property("busy");
			try {
				var html = yield this.client.fetch_path(
					this.tags_path(model.slug),
					cancellable
				);
				this.parser.apply_tags(model, html);
			} finally {
				this.fetching_detail = false;
				this.notify_property("fetching_detail");
				this.notify_property("busy");
			}
		}

		/**
		 * Merge popular-ordered then newest-ordered search rows by slug.
		 */
		public static Gee.ArrayList<OllamaWeb.Model> merge_double_search(
			Gee.ArrayList<OllamaWeb.Model> popular,
			Gee.ArrayList<OllamaWeb.Model> newest
		)
		{
			var seen = new Gee.HashSet<string>();
			var results = new Gee.ArrayList<OllamaWeb.Model>();
			foreach (var model in popular) {
				seen.add(model.slug);
				results.add(model);
			}
			foreach (var model in newest) {
				if (!seen.contains(model.slug)) {
					results.add(model);
				}
			}
			return results;
		}

		public string search_path(string query, Category category, Sort sort)
		{
			string[] args = {};
			if (query.strip() != "") {
				args += "q=" + GLib.Uri.escape_string(query.strip(), null);
			}
			if (category != Category.NONE) {
				args += "c=" + this.category_q(category);
			}
			if (sort == Sort.NEWEST) {
				args += "o=newest";
			}
			return "/search?" + string.joinv("&", args);
		}

		public string tags_path(string slug)
		{
			if (slug.contains("/")) {
				return "/" + slug + "/tags";
			}
			return "/library/" + slug + "/tags";
		}

		private string category_q(Category category)
		{
			switch (category) {
				case Category.EMBEDDING:
					return "embedding";
				case Category.VISION:
					return "vision";
				case Category.TOOLS:
					return "tools";
				case Category.THINKING:
					return "thinking";
				default:
					return "";
			}
		}
	}
}
