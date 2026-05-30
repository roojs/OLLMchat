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
	 * In-memory search result slug lists keyed by query, category, and sort set (24 h TTL).
	 */
	public class Cache : Object
	{
		private const int64 TTL_SEC = 86400;

		public class Entry : Object
		{
			public int64 cached_at_unix;
			public string[] slugs = {};
		}

		public Gee.HashMap<string, Entry> entries {
			get;
			private set;
			default = new Gee.HashMap<string, Entry>();
		}

		public bool has_key(
			string query,
			Category category,
			Sort[] sorts
		)
		{
			var key = this.cache_key(query, category, sorts);
			if (!this.entries.has_key(key)) {
				return false;
			}
			var entry = this.entries.get(key);
			int64 now = GLib.get_real_time() / 1000000;
			if (now - entry.cached_at_unix > TTL_SEC) {
				this.entries.unset(key);
				return false;
			}
			return true;
		}

		public string[] lookup(
			string query,
			Category category,
			Sort[] sorts
		)
		{
			var key = this.cache_key(query, category, sorts);
			var entry = this.entries.get(key);
			return entry.slugs;
		}

		public void store(
			string query,
			Category category,
			Sort[] sorts,
			string[] slugs
		)
		{
			var key = this.cache_key(query, category, sorts);
			var entry = new Entry();
			entry.cached_at_unix = GLib.get_real_time() / 1000000;
			entry.slugs = slugs;
			this.entries.set(key, entry);
		}

		private string cache_key(string query, Category category, Sort[] sorts)
		{
			string[] parts = {
				query.strip().down(),
				category.to_string()
			};
			foreach (var sort in sorts) {
				parts += sort.to_string();
			}
			return string.joinv("|", parts);
		}
	}
}
