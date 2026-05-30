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
	 * Cached search + per-slug model directory coordinator (debounce/cancel owned by the app).
	 *
	 * All model records live under {@link model_dir}. RAM cache holds slug lists only.
	 * {@link refine_queue} lists slugs still needing tags-page refinement.
	 */
	public class Session : Object
	{
		/**
		 * Directory of per-slug `{slug}.json` catalog files.
		 */
		public string model_dir { get; set; default = ""; }

		public Cache cache { get; private set; default = new Cache(); }

		/**
		 * Slugs from the current search still awaiting {@link refine}.
		 */
		public Gee.ArrayList<string> refine_queue {
			get;
			private set;
			default = new Gee.ArrayList<string>();
		}

		public bool searching {
			get {
				return this.service.searching;
			}
		}

		public bool enriching { get; private set; default = false; }

		public bool busy {
			get {
				return this.searching || this.enriching;
			}
		}

		private static Sort[] double_search_sorts = {
			Sort.POPULAR,
			Sort.NEWEST
		};

		private Service service { get; set; default = new Service(); }
		private Gee.HashMap<string, OllamaWeb.Model> result_rows {
			get;
			set;
			default = new Gee.HashMap<string, OllamaWeb.Model>();
		}
		private GLib.Cancellable? search_cancellable;
		private GLib.Cancellable? enrich_cancellable;

		/**
		 * Search ollama.com or return a 24 h RAM cache hit (slug list only).
		 */
		public async Gee.ArrayList<OllamaWeb.Model> search(
			string query,
			Category category,
			GLib.Cancellable? cancellable = null
		) throws OllamaWeb.Search.Error, GLib.IOError, GLib.Error {
			if (query.strip() == "") {
				this.refine_queue.clear();
				this.result_rows.clear();
				return new Gee.ArrayList<OllamaWeb.Model>();
			}
			if (this.cache.has_key(query, category, Session.double_search_sorts)) {
				var slugs = this.cache.lookup(query, category, Session.double_search_sorts);
				this.set_refine_slugs(this.pending_refine_slugs(slugs));
				return this.build_result_list(slugs);
			}
			this.cancel_search();
			this.search_cancellable = new GLib.Cancellable();
			if (cancellable != null) {
				cancellable.cancelled.connect(() => this.search_cancellable.cancel());
			}
			var hits = yield this.service.search(
				query,
				category,
				this.search_cancellable
			);
			string[] slugs = {};
			string[] refine_slugs = {};
			foreach (var hit in hits) {
				slugs += hit.slug;
				if (!OllamaWeb.Model.exists(this.model_dir, hit.slug)
						|| !OllamaWeb.Model.is_refined(this.model_dir, hit.slug)) {
					hit.refined = false;
					hit.save(this.model_dir);
				}
				if (!OllamaWeb.Model.is_refined(this.model_dir, hit.slug)) {
					refine_slugs += hit.slug;
				}
			}
			this.cache.store(query, category, Session.double_search_sorts, slugs);
			this.set_refine_slugs(refine_slugs);
			this.result_rows.clear();
			foreach (var hit in hits) {
				this.result_rows.set(hit.slug, hit);
			}
			return hits;
		}

		/**
		 * Drain {@link refine_queue}: tags fetch, set {@link OllamaWeb.Model.refined}, {@link OllamaWeb.Model.save}.
		 */
		public async void refine(
			GLib.Cancellable? cancellable = null
		) throws OllamaWeb.Search.Error, GLib.IOError, GLib.Error {
			this.cancel_refine();
			this.enrich_cancellable = new GLib.Cancellable();
			if (cancellable != null) {
				cancellable.cancelled.connect(() => this.enrich_cancellable.cancel());
			}
			this.enriching = true;
			this.notify_property("enriching");
			this.notify_property("busy");
			try {
				while (this.refine_queue.size > 0) {
					if (this.enrich_cancellable.is_cancelled()) {
						break;
					}
					var slug = this.refine_queue.remove_at(0);
					if (OllamaWeb.Model.is_refined(this.model_dir, slug)) {
						continue;
					}
					if (!this.result_rows.has_key(slug)) {
						continue;
					}
					var row = this.result_rows.get(slug);
					yield this.service.fetch_tags(row, this.enrich_cancellable);
					row.save(this.model_dir);
				}
			} finally {
				this.enriching = false;
				this.notify_property("enriching");
				this.notify_property("busy");
			}
		}

		/**
		 * Abort in-flight search and detail refinement.
		 */
		public void cancel()
		{
			this.cancel_search();
			this.cancel_refine();
			this.refine_queue.clear();
			this.result_rows.clear();
		}

		private void set_refine_slugs(string[] slugs)
		{
			this.refine_queue.clear();
			foreach (var slug in slugs) {
				this.refine_queue.add(slug);
			}
		}

		private Gee.ArrayList<OllamaWeb.Model> build_result_list(string[] slugs) throws GLib.Error
		{
			var results = new Gee.ArrayList<OllamaWeb.Model>();
			this.result_rows.clear();
			foreach (var slug in slugs) {
				var row = this.load_row(slug);
				this.result_rows.set(slug, row);
				results.add(row);
			}
			return results;
		}

		private OllamaWeb.Model load_row(string slug) throws GLib.Error
		{
			if (OllamaWeb.Model.exists(this.model_dir, slug)) {
				return OllamaWeb.Model.load(this.model_dir, slug);
			}
			var stub = new OllamaWeb.Model();
			stub.slug = slug;
			return stub;
		}

		private string[] pending_refine_slugs(string[] slugs) throws GLib.Error
		{
			string[] pending = {};
			foreach (var slug in slugs) {
				if (!OllamaWeb.Model.is_refined(this.model_dir, slug)) {
					pending += slug;
				}
			}
			return pending;
		}

		private void cancel_search()
		{
			this.search_cancellable?.cancel();
			this.search_cancellable = null;
		}

		private void cancel_refine()
		{
			this.enrich_cancellable?.cancel();
			this.enrich_cancellable = null;
		}
	}
}
