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
	 * HTTP client for ollama.com HTML pages.
	 */
	public class Client : Object
	{
		public const string BASE_URL = "https://ollama.com";
		public const string USER_AGENT =
			"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

		private Soup.Session session { get; set; default = new Soup.Session(); }

		public async string fetch_path(string path, GLib.Cancellable? cancellable = null) throws Error, GLib.IOError, GLib.Error
		{
			var url = BASE_URL + path;
			var message = new Soup.Message("GET", url);
			message.request_headers.append("User-Agent", USER_AGENT);
			try {
				var bytes = yield this.session.send_and_read_async(
					message,
					GLib.Priority.DEFAULT,
					cancellable
				);
				if (message.status_code == 429 || message.status_code == 503) {
					throw new Error.RATE_LIMITED("HTTP " + message.status_code.to_string());
				}
				if (message.status_code == 404) {
					throw new Error.NOT_FOUND("HTTP 404 for " + url);
				}
				if (message.status_code < 200 || message.status_code >= 300) {
					throw new Error.NETWORK("HTTP " + message.status_code.to_string() + " for " + url);
				}
				return (string) bytes.get_data();
			} catch (GLib.IOError e) {
				if (e is GLib.IOError.CANCELLED) {
					throw e;
				}
				throw new Error.NETWORK(e.message);
			}
		}
	}
}
