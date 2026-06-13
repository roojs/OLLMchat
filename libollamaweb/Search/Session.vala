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
		private const uint TAG_FETCH_INTERVAL_MS = 1000;

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
		 * Emitted when search rows are ready for display (popular page first, then merged).
		 */
		public signal void rows_ready(Gee.ArrayList<OllamaWeb.Model> results);

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
				// GLib.debug(
				// 	"ollamaweb search cache hit q='%s' slugs=%u refine_pending=%u",
				// 	query,
				// 	slugs.length,
				// 	this.refine_queue.size
				// );
				var results = this.build_result_list(slugs);
				this.rows_ready(results);
				return results;
			}
			this.cancel_search();
			this.cancel_refine();
			this.search_cancellable = new GLib.Cancellable();
			if (cancellable != null) {
				cancellable.cancelled.connect(() => this.search_cancellable.cancel());
			}
			this.service.searching = true;
			this.service.notify_property("searching");
			this.service.notify_property("busy");
			try {
				var popular_hits = yield this.service.search(
					query,
					category,
					this.search_cancellable,
					Sort.POPULAR
				);
				var partial = new Gee.ArrayList<OllamaWeb.Model>();
				foreach (var hit in popular_hits) {
					if (!OllamaWeb.Model.exists(this.model_dir, hit.slug)) {
						hit.refined = false;
						hit.save(this.model_dir);
						partial.add(hit);
						continue;
					}
					partial.add(this.load_row(hit.slug));
				}
				// GLib.debug("popular ready q='%s' items=%u", query, partial.size);
				this.rows_ready(partial);
				var newest_hits = yield this.service.search(
					query,
					category,
					this.search_cancellable,
					Sort.NEWEST
				);
				var merged_hits = Service.merge_double_search(popular_hits, newest_hits);
				string[] slugs = {};
				string[] refine_slugs = {};
				var results = new Gee.ArrayList<OllamaWeb.Model>();
				foreach (var hit in merged_hits) {
					slugs += hit.slug;
					if (!OllamaWeb.Model.exists(this.model_dir, hit.slug)) {
						hit.refined = false;
						hit.save(this.model_dir);
						refine_slugs += hit.slug;
						results.add(hit);
						continue;
					}
					var row = this.load_row(hit.slug);
					if (!row.refined || row.tags.size == 0) {
						refine_slugs += hit.slug;
					}
					results.add(row);
				}
				this.cache.store(query, category, Session.double_search_sorts, slugs);
				this.set_refine_slugs(refine_slugs);
				// GLib.debug(
				// 	"ollamaweb search q='%s' hits=%u refine_queue=%u",
				// 	query,
				// 	results.size,
				// 	refine_slugs.length
				// );
				this.result_rows.clear();
				foreach (var row in results) {
					this.result_rows.set(row.slug, row);
				}
				// GLib.debug("merged ready q='%s' items=%u", query, results.size);
				this.rows_ready(results);
				return results;
			} finally {
				this.service.searching = false;
				this.service.notify_property("searching");
				this.service.notify_property("busy");
			}
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
					if (!this.result_rows.has_key(slug)) {
						continue;
					}
					var row = this.result_rows.get(slug);
					try {
						yield this.service.fetch_tags(row, this.enrich_cancellable);
						row.save(this.model_dir);
						row.notify_property("list_markup");
					} catch (GLib.Error e) {
						GLib.warning(
							"ollama.com tags failed for %s: %s",
							slug,
							e.message
						);
					}
					if (this.refine_queue.size > 0 && !this.enrich_cancellable.is_cancelled()) {
						var throttle_done = false;
						uint throttle_id = GLib.Timeout.add(
							Session.TAG_FETCH_INTERVAL_MS,
							() => {
								throttle_done = true;
								return false;
							}
						);
						while (!throttle_done) {
							if (this.enrich_cancellable.is_cancelled()) {
								GLib.Source.remove(throttle_id);
								break;
							}
							yield;
						}
					}
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
				var row = OllamaWeb.Model.load(this.model_dir, slug);
				row.rebuild_unique_sizes();
				return row;
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
