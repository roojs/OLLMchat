/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMchat.Settings
{
	/**
	 * Live ollama.com search backing store for Add Model ({@link GLib.ListModel} of {@link OllamaWeb.Model}).
	 *
	 * Debounces query text, owns {@link OllamaWeb.Search.Session}, and runs {@link OllamaWeb.Search.Session.refine}
	 * after each search. Empty {@link pending_query} means no in-flight debounced search.
	 */
	public class SearchResults : Object, GLib.ListModel
	{
		public string data_dir { get; construct; }

		public OllamaWeb.Search.Session session {
			get;
			private set;
			default = new OllamaWeb.Search.Session();
		}

		private Gee.ArrayList<OllamaWeb.Model> store {
			get;
			set;
			default = new Gee.ArrayList<OllamaWeb.Model>();
		}

		private uint debounce_id;
		private string pending_query { get; set; default = ""; }
		private string last_queued_query { get; set; default = ""; }

		/** True while a live search HTTP request is in flight (not during debounce). */
		public bool loading { get; private set; default = false; }

		public SearchResults(string data_dir)
		{
			Object(data_dir: data_dir);
			this.session.model_dir = GLib.Path.build_filename(this.data_dir, "ollamaweb-models");
			this.session.rows_ready.connect((rows) => {
				if (this.pending_query == "") {
					return;
				}
				this.replace_hits(rows);
				GLib.debug(
					"store ready q='%s' items=%u loading=%s",
					this.pending_query,
					this.store.size,
					this.loading.to_string()
				);
				foreach (var row in this.store) {
					row.notify_property("list_markup");
				}
			});
		}

		public Type get_item_type()
		{
			return typeof(OllamaWeb.Model);
		}

		public uint get_n_items()
		{
			return this.store.size;
		}

		public Object? get_item(uint position)
		{
			if (position >= this.store.size) {
				return null;
			}
			return this.store[(int)position];
		}

		/**
		 * Schedule a debounced search (~500 ms). Empty text clears results and cancels the session.
		 *
		 * When the user shortens the query or changes it in a non-prefix way, results are cleared
		 * immediately. When they only extend the previous query, the current list stays until
		 * the next search completes.
		 *
		 * @param query search box text from Add Model
		 * @return true if prior results were kept (query extended); false if cleared or first char
		 */
		public bool queue_search(string query)
		{
			if (this.debounce_id != 0) {
				GLib.Source.remove(this.debounce_id);
				this.debounce_id = 0;
			}
			this.pending_query = query.strip();
			if (this.pending_query == "") {
				this.last_queued_query = "";
				this.loading = false;
				this.notify_property("loading");
				this.clear_results();
				this.session.cancel();
				return false;
			}
			var kept = this.keeps_prior_results(this.pending_query);
			if (!kept) {
				this.clear_results();
			}
			this.last_queued_query = this.pending_query;
			this.session.cancel();
			this.debounce_id = GLib.Timeout.add(500, () => {
				this.debounce_id = 0;
				GLib.debug("debounced q='%s'", this.pending_query);
				this.run_search.begin();
				return false;
			});
			return kept;
		}

		private bool keeps_prior_results(string query)
		{
			if (this.last_queued_query == "") {
				return false;
			}
			if (query.length < this.last_queued_query.length) {
				return false;
			}
			return query.has_prefix(this.last_queued_query);
		}

		/**
		 * Cancel debounced search and in-flight session work.
		 */
		public void cancel()
		{
			if (this.debounce_id != 0) {
				GLib.Source.remove(this.debounce_id);
				this.debounce_id = 0;
			}
			this.pending_query = "";
			this.last_queued_query = "";
			this.loading = false;
			this.notify_property("loading");
			this.session.cancel();
		}

		private void clear_results()
		{
			var n = this.store.size;
			if (n == 0) {
				return;
			}
			this.store.clear();
			this.items_changed(0, n, 0);
		}

		private async void run_search()
		{
			if (this.pending_query == "") {
				return;
			}
			var our_query = this.pending_query;
			// GLib.debug("SearchResults run_search q='%s'", our_query);
			this.loading = true;
			this.notify_property("loading");
			GLib.debug("loading=true q='%s' store=%u", our_query, this.store.size);
			try {
				try {
					yield this.session.search(our_query, OllamaWeb.Search.Category.NONE);
				} catch (GLib.Error e) {
					GLib.warning("ollama.com search failed: " + e.message);
					return;
				}
				if (this.pending_query != our_query) {
					return;
				}
				// GLib.debug(
				// 	"SearchResults q='%s' store=%u refine_queue=%u",
				// 	our_query,
				// 	this.store.size,
				// 	this.session.refine_queue.size
				// );
				if (this.session.refine_queue.size == 0) {
					return;
				}
				yield this.session.refine();
				if (this.pending_query != our_query) {
					return;
				}
				foreach (var row in this.store) {
					row.notify_property("list_markup");
				}
			} finally {
				if (this.pending_query == our_query || this.pending_query == "") {
					this.loading = false;
					this.notify_property("loading");
					GLib.debug(
						"loading=false q='%s' store=%u",
						our_query,
						this.store.size
					);
				}
			}
		}

		private void replace_hits(Gee.ArrayList<OllamaWeb.Model> hits)
		{
			var n_old = this.store.size;
			this.store.clear();
			foreach (var hit in hits) {
				this.store.add(hit);
			}
			this.items_changed(0, n_old, this.store.size);
		}

	}
}
